"""TCP 延迟测试与可用性检测模块"""

from __future__ import annotations

import re
import socket
import ssl
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Any

from config import Config

# 预编译正则
NODE_PATTERN = re.compile(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#(.+)$")
IP_PORT_PATTERN = re.compile(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#")


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


def test_tcp_latency(ip: str, port: int, timeout: float, probes: int) -> tuple[float, int]:
    """测试单个 IP 的 TCP 延迟，返回最小延迟和成功次数"""
    min_latency = float("inf")
    success = 0
    for _ in range(probes):
        try:
            start = time.time()
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(timeout)
                sock.connect((ip, port))
            latency = time.time() - start
            if latency < min_latency:
                min_latency = latency
            success += 1
        except Exception:
            continue
    return min_latency, success


def test_node(node_str: str, config: Config) -> TcpResult | None:
    """测试单个节点的 TCP 连接"""
    m = NODE_PATTERN.match(node_str)
    if not m:
        return None
    ip, port, country = m.groups()
    min_lat, success = test_tcp_latency(ip, int(port), config.TIMEOUT, config.TCP_PROBES)

    if success == 0 or (success / config.TCP_PROBES) < config.MIN_SUCCESS_RATE:
        return None

    return TcpResult(node=node_str, latency=min_lat, country=country, success_count=success)


def check_availability(node_str: str, config: Config) -> AvailabilityResult:
    """通过 TLS 握手检测节点可用性，并通过 API 获取 IP 栈类型"""
    m = IP_PORT_PATTERN.match(node_str)
    if not m:
        return AvailabilityResult(node=node_str, ok=False, stack="unknown", exit_info={})
    ip, port = m.group(1), m.group(2)

    # 先做本地 TLS 握手（快速判断端口是否开放）
    sock = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(config.AVAILABILITY_CONNECT_TIMEOUT)
        sock.connect((ip, int(port)))

        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ssock = ctx.wrap_socket(sock, server_hostname="speed.cloudflare.com")
        ssock.close()
        sock.close()
    except Exception:
        try:
            if sock:
                sock.close()
        except Exception:
            pass
        return AvailabilityResult(node=node_str, ok=False, stack="unknown", exit_info={})

    # 通过可用性检测 API 查询实际 IP 栈类型（ipv4_only / ipv6_only / dual_stack）
    # 作用：让 dns.py 的 IPv6 落地过滤（FILTER_IPV6_AVAILABILITY）能正确工作
    try:
        resp = requests.get(
            config.AVAILABILITY_CHECK_API,
            params={"proxyip": f"{ip}:{port}"},
            timeout=(config.AVAILABILITY_CONNECT_TIMEOUT, config.AVAILABILITY_TIMEOUT),
        )
        if resp.status_code == 200:
            data = resp.json()
            # API 返回 inferred_stack: "ipv4_only" / "ipv6_only" / "dual_stack"
            stack = data.get("inferred_stack", "unknown")
            if stack in ("ipv4_only", "ipv6_only", "dual_stack"):
                return AvailabilityResult(node=node_str, ok=True, stack=stack, exit_info={})
    except Exception:
        pass

    # API 查询失败时回退为 ipv4_only（保守策略：本地 TLS 已通，视为 IPv4 可用）
    return AvailabilityResult(node=node_str, ok=True, stack="ipv4_only", exit_info={})


def run_tcp_tests(nodes: list[str], config: Config, skip_tcp: bool = False) -> list[TcpResult]:
    """并发运行 TCP 测试"""
    if skip_tcp:
        print(f"跳过 TCP 测试，直接进入可用性检测（共 {len(nodes)} 个节点）。")
        return [
            TcpResult(node=n, latency=0, country=n.split("#")[-1] if "#" in n else "", success_count=3) for n in nodes
        ]

    print(f"开始 TCP 连接测试（超时 {config.TIMEOUT}s，并发 {config.MAX_WORKERS}）...")

    results: list[TcpResult] = []
    completed = 0
    total = len(nodes)
    last_print = time.time()

    with ThreadPoolExecutor(max_workers=config.MAX_WORKERS) as executor:
        futures = {executor.submit(test_node, node, config): node for node in nodes}
        for future in as_completed(futures):
            completed += 1
            res = future.result()
            if res:
                results.append(res)
            now = time.time()
            if now - last_print >= config.PROGRESS_PRINT_INTERVAL or completed == total:
                print(f"\r进度：{completed}/{total} ({(completed / total) * 100:.1f}%)", end="", flush=True)
                last_print = now

    print("\nTCP 测试完成！")
    return results


def run_availability_tests(candidates: list[str], config: Config) -> tuple[list[str], dict[str, str], dict[str, dict]]:
    """运行可用性检测（带重试）"""
    if not config.TEST_AVAILABILITY or not candidates:
        return candidates, {}, {}

    passed: list[str] = []
    ip_info: dict[str, str] = {}
    exit_details: dict[str, dict] = {}

    for attempt in range(1, config.AVAILABILITY_RETRY_MAX + 1):
        print(f"\n[可用性检测] 第 {attempt} 轮检测...")
        passed, ip_info, exit_details = _run_availability_round(candidates, config)
        if passed:
            print(f"可用性检测通过 {len(passed)} 个节点")
            return passed, ip_info, exit_details
        if attempt < config.AVAILABILITY_RETRY_MAX:
            print(f"本轮可用性检测通过率为 0%，等待 {config.AVAILABILITY_RETRY_DELAY} 秒后重试...")
            time.sleep(config.AVAILABILITY_RETRY_DELAY)

    print(f"可用性检测经 {config.AVAILABILITY_RETRY_MAX} 轮重试后仍无节点通过。")
    # 回退到原候选列表
    return candidates, {}, {}


def _run_availability_round(candidates: list[str], config: Config) -> tuple[list[str], dict[str, str], dict[str, dict]]:
    """单轮可用性检测"""
    passed = []
    ip_info = {}
    exit_details = {}
    completed = 0
    total = len(candidates)
    last_print = time.time()

    with ThreadPoolExecutor(max_workers=config.AVAILABILITY_WORKERS) as executor:
        futures = {executor.submit(check_availability, node, config): node for node in candidates}
        for future in as_completed(futures):
            completed += 1
            result = future.result()
            if result.ok:
                passed.append(result.node)
                ip_info[result.node] = result.stack
                exit_details[result.node] = result.exit_info
            now = time.time()
            if now - last_print >= config.PROGRESS_PRINT_INTERVAL or completed == total:
                print(
                    f"\r[可用性检测] 进度：{completed}/{total}"
                    f" ({(completed / total) * 100:.1f}%) 通过数量：{len(passed)}",
                    end="",
                    flush=True,
                )
                last_print = now
    print()
    return passed, ip_info, exit_details
