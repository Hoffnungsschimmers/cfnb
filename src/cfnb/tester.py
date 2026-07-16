"""TCP 延迟测试与可用性检测模块"""

from __future__ import annotations

import re
import socket
import ssl
import time
import asyncio
import httpx
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Any

from cfnb.config import Config
from cfnb.fetcher import NODE_PATTERN, IP_PORT_PATTERN


@dataclass
class TcpResult:
    """TCP 测试结果"""

    node: str
    latency: float
    country: str
    success_count: int


@dataclass
class AvailabilityResult:
    """可用性检测结果"""

    node: str
    ok: bool
    stack: str
    exit_info: dict[str, Any]


async def test_tcp_latency_async(ip: str, port: int, timeout: float, probes: int) -> tuple[float, int]:
    """异步测试单个 IP 的 TCP 延迟，返回最小延迟和成功次数 (回归串行，以保证家宽质量与精度)"""
    min_latency = float("inf")
    success = 0
    for _ in range(probes):
        try:
            start = time.time()
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(ip, port),
                timeout=timeout
            )
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
            latency = time.time() - start
            if latency < min_latency:
                min_latency = latency
            success += 1
        except Exception:
            continue
    return min_latency, success


async def test_node_async(node_str: str, config: Config, semaphore: asyncio.Semaphore) -> TcpResult | None:
    """异步测试单个节点的 TCP 连接"""
    m = NODE_PATTERN.match(node_str)
    if not m:
        return None
    ip, port, country = m.groups()
    
    async with semaphore:
        min_lat, success = await test_tcp_latency_async(ip, int(port), config.TIMEOUT, config.TCP_PROBES)

    if success == 0 or (success / config.TCP_PROBES) < config.MIN_SUCCESS_RATE:
        return None

    return TcpResult(node=node_str, latency=min_lat, country=country, success_count=success)


async def run_tcp_tests_async(nodes: list[str], config: Config) -> list[TcpResult]:
    """异步运行 TCP 测试并实时打印进度"""
    if not nodes:
        return []

    max_workers = config.MAX_WORKERS
    print(f"开始异步 TCP 连接测试（超时 {config.TIMEOUT}s，最大并发 {max_workers}）...")

    results: list[TcpResult] = []
    completed = 0
    total = len(nodes)
    last_print = time.time()
    
    semaphore = asyncio.Semaphore(max_workers)
    
    tasks = [test_node_async(node, config, semaphore) for node in nodes]
    
    for coro in asyncio.as_completed(tasks):
        res = await coro
        completed += 1
        if res:
            results.append(res)
            print(f"[TCP_POINT] {res.node} | {res.latency * 1000:.1f}", flush=True)
            from cfnb.gui.widgets.progress_helper import emit_tcp
            emit_tcp(res.node, res.latency * 1000)
            
        now = time.time()
        if now - last_print >= config.PROGRESS_PRINT_INTERVAL or completed == total:
            import sys
            if sys.stdout.isatty():
                print(f"\r进度：{completed}/{total} ({(completed / total) * 100:.1f}%)", end="", flush=True)
            else:
                print(f"进度：{completed}/{total} ({(completed / total) * 100:.1f}%)", flush=True)
            last_print = now

    print("\nTCP 测试完成！")
    return results


def run_tcp_tests(nodes: list[str], config: Config, skip_tcp: bool = False) -> list[TcpResult]:
    """同步包装器，调用异步 TCP 测试逻辑"""
    if skip_tcp:
        print(f"跳过 TCP 测试，直接进入可用性检测（共 {len(nodes)} 个节点）。")
        return [
            TcpResult(node=n, latency=0, country=n.split("#")[-1] if "#" in n else "", success_count=3) for n in nodes
        ]
    return asyncio.run(run_tcp_tests_async(nodes, config))


_shared_ssl_ctx = None

def get_shared_ssl_context():
    global _shared_ssl_ctx
    if _shared_ssl_ctx is None:
        _shared_ssl_ctx = ssl.create_default_context()
        _shared_ssl_ctx.check_hostname = False
        _shared_ssl_ctx.verify_mode = ssl.CERT_NONE
    return _shared_ssl_ctx


def check_node_availability_sync(node_str: str, config: Config) -> tuple[str, bool, str]:
    """同步测试单个节点的 TLS 可用性并推断 IP 栈类型"""
    m = IP_PORT_PATTERN.match(node_str)
    if not m:
        return node_str, False, "unknown"
    ip, port = m.group(1), m.group(2)
    
    # 依据 IP 格式推断栈类型
    stack = "ipv6_only" if ":" in ip else "ipv4_only"
    
    # 执行 TLS 握手连接测试
    sock = None
    ssl_sock = None
    try:
        sock = socket.socket(socket.AF_INET6 if ":" in ip else socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(config.AVAILABILITY_CONNECT_TIMEOUT)
        
        # 先建立 TCP 连接，避免 TLS 握手阶段的超时不受控
        sock.connect((ip, int(port)))
        
        ctx = get_shared_ssl_context()
        
        # 包装 socket 并进行握手
        ssl_sock = ctx.wrap_socket(sock, server_hostname="speed.cloudflare.com")
        
        return node_str, True, stack
    except Exception:
        return node_str, False, "unknown"
    finally:
        if ssl_sock:
            try:
                ssl_sock.close()
            except Exception:
                pass
        elif sock:
            try:
                sock.close()
            except Exception:
                pass


def run_availability_tests(
    candidates: list[str], config: Config
) -> tuple[list[str], dict[str, str], dict[str, dict]]:
    """使用线程池同步并行执行可用性检测，彻底解决 Proactor 挂起与 API 卡死瓶颈"""
    if not config.TEST_AVAILABILITY or not candidates:
        return candidates, {}, {}

    max_workers = config.AVAILABILITY_WORKERS
    print(f"开始并行可用性检测（线程数 {max_workers}，超时 {config.AVAILABILITY_CONNECT_TIMEOUT}s）...")
    
    passed: list[str] = []
    ip_info: dict[str, str] = {}
    exit_details: dict[str, dict] = {}
    
    completed = 0
    total = len(candidates)
    last_print = time.time()
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(check_node_availability_sync, node, config): node for node in candidates}
        
        for future in as_completed(futures):
            try:
                node, ok, stack = future.result()
                completed += 1
                if ok:
                    passed.append(node)
                    ip_info[node] = stack
                    exit_details[node] = {}
                
                # 打印进度
                now = time.time()
                if now - last_print >= config.PROGRESS_PRINT_INTERVAL or completed == total:
                    print(f"[可用性检测] 进度：{completed}/{total} ({(completed / total) * 100:.1f}%) 通过数量：{len(passed)}", flush=True)
                    last_print = now
            except Exception:
                completed += 1
                
    print(f"可用性检测完成，共有 {len(passed)} 个节点通过可用性筛选。")
    return passed, ip_info, exit_details
