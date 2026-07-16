"""带宽测速模块 - 三轮渐进式自适应测速 (Asyncio + HTTPX)"""

from __future__ import annotations

import asyncio
import re
import shutil
import sys
import time
from dataclasses import dataclass

import httpx
import httpcore

from cfnb.config import Config


@dataclass
class SpeedResult:
    """测速结果"""
    node: str
    speed_mbps: float


class CustomNetworkBackend(httpcore.AsyncNetworkBackend):
    """自定义连接后端，绕过 SNI 并发限制并直连目标 IP"""
    def __init__(self, target_ip: str, target_port: int):
        self.target_ip = target_ip
        self.target_port = target_port
        self.default_backend = httpcore.AnyIOBackend()
        
    async def connect_tcp(self, host, port, timeout, local_address=None, socket_options=None):
        return await self.default_backend.connect_tcp(
            self.target_ip, self.target_port, timeout, local_address, socket_options
        )


class CustomHTTPTransport(httpx.AsyncHTTPTransport):
    """自定义 HTTP 传输层，忽略 SSL 验证并利用自定义后端重定向连接"""
    def __init__(self, target_ip: str, target_port: int, *args, **kwargs):
        kwargs["verify"] = False
        super().__init__(*args, **kwargs)
        self.backend = CustomNetworkBackend(target_ip, target_port)
        self._pool = httpcore.AsyncConnectionPool(
            ssl_context=self._pool._ssl_context,
            network_backend=self.backend
        )


async def measure_bandwidth_async(
    node_str: str, url: str, timeout: float, connect_timeout: float
) -> SpeedResult:
    """使用 httpx 异步测量单个节点的带宽"""
    m = re.match(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#", node_str)
    if not m:
        return SpeedResult(node=node_str, speed_mbps=0.0)
    ip, port = m.group(1), int(m.group(2))

    # 使用自定义传输层实现域名直连特定 IP 且带正确 SNI / Host
    transport = CustomHTTPTransport(ip, port)
    start_time = time.time()
    downloaded_bytes = 0
    
    try:
        limits = httpx.Limits(max_keepalive_connections=1, max_connections=1)
        async with httpx.AsyncClient(
            transport=transport,
            limits=limits,
            timeout=httpx.Timeout(timeout, connect=connect_timeout)
        ) as client:
            async with client.stream("GET", url) as response:
                if response.status_code == 200:
                    async for chunk in response.aiter_bytes():
                        downloaded_bytes += len(chunk)
                        # 手动检测超时以支持流式下载的早停
                        if time.time() - start_time >= timeout:
                            break
    except Exception:
        pass
        
    duration = time.time() - start_time
    if duration > 0 and downloaded_bytes > 0:
        speed_mbps = (downloaded_bytes * 8) / (duration * 1000 * 1000)
        return SpeedResult(node=node_str, speed_mbps=speed_mbps)
        
    return SpeedResult(node=node_str, speed_mbps=0.0)


async def _run_speed_pass_async(
    candidates: list[str],
    url: str,
    timeout: float,
    connect_timeout: float,
    workers: int,
    tag: str,
    early_stop_target: int | None = None
) -> dict[str, float]:
    """单轮异步并发测速"""
    if not candidates:
        return {}

    print(f"\n[{tag}] {len(candidates)} 个节点 · 目标大小 {url.split('bytes=')[-1]} 字节 · 超时 {timeout}s · 并发 {workers}")

    results: dict[str, float] = {}
    completed = 0
    total = len(candidates)
    last_print = time.time()

    semaphore = asyncio.Semaphore(workers)

    async def worker(node: str) -> SpeedResult:
        try:
            async with semaphore:
                return await measure_bandwidth_async(node, url, timeout, connect_timeout)
        except asyncio.CancelledError:
            return SpeedResult(node=node, speed_mbps=0.0)

    tasks = [asyncio.create_task(worker(node)) for node in candidates]

    for coro in asyncio.as_completed(tasks):
        res = await coro
        completed += 1
        if res.speed_mbps > 0:
            results[res.node] = res.speed_mbps
            print(f"[SPEED_POINT] {res.node} | {res.speed_mbps:.2f}", flush=True)
            from cfnb.gui.widgets.progress_helper import emit_speed
            emit_speed(res.node, res.speed_mbps)

        # 早停条件检测
        if early_stop_target and len(results) >= early_stop_target:
            print(f"\n[{tag}] 已达到早停目标数（{early_stop_target}），取消剩余 {total - completed} 个任务...")
            for t in tasks:
                if not t.done():
                    t.cancel()
            break

        now = time.time()
        if now - last_print >= 1.0 or completed == total:
            import sys
            if sys.stdout.isatty():
                print(
                    f"\r[{tag}] 进度：{completed}/{total} ({(completed / total) * 100:.1f}%) "
                    f"已测出速度：{len(results)}",
                    end="",
                    flush=True,
                )
            else:
                print(
                    f"[{tag}] 进度：{completed}/{total} ({(completed / total) * 100:.1f}%) "
                    f"已测出速度：{len(results)}",
                    flush=True,
                )
            last_print = now
    print()
    return results


async def run_multi_pass_speed_test_async(candidates: list[str], config: Config) -> list[SpeedResult]:
    """两轮漏斗式测速：探速 -> 精测

    探速阶段使用 256KB 小文件快速筛出有速度的节点并排名，
    精测阶段只对探速排名前 300 名使用 1MB 文件精确测定带宽。
    """
    if not candidates:
        return []

    # ── 第一轮：探速 (Probe) ── 256KB, 4s 超时, 高并发 ──
    probe_bytes = 262144
    probe_timeout = 4.0
    probe_connect = 2.0
    probe_workers = config.BANDWIDTH_WORKERS
    probe_url = config.BANDWIDTH_URL_TEMPLATE.format(bytes=probe_bytes)

    probe_speed = await _run_speed_pass_async(
        candidates, probe_url, probe_timeout, probe_connect, probe_workers, "探速"
    )

    fast_nodes = sorted(probe_speed.keys(), key=lambda x: probe_speed[x], reverse=True)
    if not fast_nodes:
        print("探速轮所有节点均无速度，跳过精测。")
        return []

    # ── 第二轮：精测 (Refine) ── 1MB, 15s 超时, 低并发 ──
    refine_top_n = 300
    refine_candidates = fast_nodes[:refine_top_n]

    refine_bytes = 1 * 1024 * 1024   # 固定 1MB，精度足够且速度快
    refine_url = config.BANDWIDTH_URL_TEMPLATE.format(bytes=refine_bytes)
    refine_timeout = 15.0
    refine_connect = 5.0
    refine_workers = max(1, config.BANDWIDTH_WORKERS // 2)

    # 早停：收集到 3 倍 GLOBAL_TOP_N 即可停止
    early_stop_target = int(config.GLOBAL_TOP_N * 3)

    refine_speed = await _run_speed_pass_async(
        refine_candidates,
        refine_url,
        refine_timeout,
        refine_connect,
        refine_workers,
        "精测",
        early_stop_target=early_stop_target
    )

    # ── 结果合并：精测优先，探速兜底 ──
    final_speed: dict[str, float] = {}
    for node in fast_nodes:
        if node in refine_speed:
            final_speed[node] = refine_speed[node]
        elif node in probe_speed and probe_speed[node] > 0:
            final_speed[node] = probe_speed[node]

    print(
        f"\n两轮测速完成：候选 {len(candidates)}"
        f" → 探速有效 {len(probe_speed)}"
        f" → 精测候选 {len(refine_candidates)}"
        f" → 精测有效 {len(refine_speed)} 个节点"
    )

    results = sorted(
        (SpeedResult(node=node, speed_mbps=speed) for node, speed in final_speed.items()),
        key=lambda x: x.speed_mbps,
        reverse=True,
    )
    return results


def run_speed_test_with_retry(candidates: list[str], config: Config) -> list[SpeedResult]:
    """带重试的带宽测速"""
    if not candidates:
        return []

    print(
        f"\n开始带宽测速（对前 {len(candidates)} 个节点，并发 {config.BANDWIDTH_WORKERS}"
        f"，超时 {config.BANDWIDTH_TIMEOUT}s）..."
    )

    for attempt in range(1, config.BANDWIDTH_RETRY_MAX + 1):
        print(f"\n[带宽测速] 第 {attempt} 轮测试...")
        try:
            results = asyncio.run(run_multi_pass_speed_test_async(candidates, config))
            if results:
                return results
        except Exception as e:
            print(f"带宽测速执行异常: {e}")

        if attempt < config.BANDWIDTH_RETRY_MAX:
            print(f"本轮测速无有效结果，等待 {config.BANDWIDTH_RETRY_DELAY} 秒后重试...")
            time.sleep(config.BANDWIDTH_RETRY_DELAY)

    print(f"带宽测速经 {config.BANDWIDTH_RETRY_MAX} 轮尝试后仍无有效结果。")
    return []
