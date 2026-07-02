"""带宽测速模块 - 两轮自适应测速"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass

from config import Config


@dataclass
class SpeedResult:
    """测速结果"""

    node: str
    speed_mbps: float


# curl 输出分隔符
CURL_RESULT_PREFIX = "\n<<<CFNB_RESULT>>>"


def measure_bandwidth_curl(node_str: str, url: str, timeout: int, connect_timeout: int) -> SpeedResult:
    """使用 curl 测量单个节点的带宽"""
    import re

    m = re.match(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#", node_str)
    if not m:
        return SpeedResult(node=node_str, speed_mbps=0)
    ip, port = m.group(1), m.group(2)

    test_url = url
    _timeout = timeout
    _conn_timeout = connect_timeout

    null_device = "NUL" if sys.platform == "win32" else "/dev/null"
    curl_cmd = [
        "curl",
        "-s",
        "-o",
        null_device,
        "-w",
        CURL_RESULT_PREFIX + "%{size_download}|%{time_total}",
        "--connect-to",
        f"speed.cloudflare.com:{port}:{ip}:{port}",
        "--connect-timeout",
        str(_conn_timeout),
        "--max-time",
        str(_timeout),
        "--insecure",
        test_url,
    ]

    si = None
    cf = 0
    if sys.platform == "win32":
        si = subprocess.STARTUPINFO()
        si.dwFlags = subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 0
        cf = 0x08000000

    try:
        result = subprocess.run(
            curl_cmd,
            capture_output=True,
            text=True,
            timeout=_timeout + 5,
            startupinfo=si,
            creationflags=cf,
            encoding="utf-8",
            errors="ignore",
        )
        if result.returncode == 0 and result.stdout:
            idx = result.stdout.rfind(CURL_RESULT_PREFIX)
            data_part = result.stdout[idx + len(CURL_RESULT_PREFIX) :].strip() if idx >= 0 else result.stdout.strip()
            parts = data_part.split("|")
            if len(parts) >= 2:
                size_bytes = float(parts[0])
                time_total = float(parts[1])
                if time_total > 0 and size_bytes > 0:
                    speed_mbps = (size_bytes * 8) / (time_total * 1000 * 1000)
                    return SpeedResult(node=node_str, speed_mbps=speed_mbps)
    except Exception:
        pass
    return SpeedResult(node=node_str, speed_mbps=0)


def _run_speed_pass(
    candidates: list[str], url: str, timeout: int, connect_timeout: int, workers: int, tag: str
) -> dict[str, float]:
    """单轮并发测速，返回 {node: speed} 字典"""
    if not candidates:
        return {}

    print(f"\n[{tag}] {len(candidates)} 个节点 · 文件 {url.split('bytes=')[-1]}B · 超时 {timeout}s · 并发 {workers}")

    results: dict[str, float] = {}
    completed = 0
    total = len(candidates)
    last_print = time.time()

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(measure_bandwidth_curl, node, url, timeout, connect_timeout): node for node in candidates
        }
        for future in as_completed(futures):
            completed += 1
            result = future.result()
            if result.speed_mbps > 0:
                results[result.node] = result.speed_mbps
            now = time.time()
            if now - last_print >= 1 or completed == total:
                print(
                    f"\r[{tag}] 进度：{completed}/{total} ({(completed / total) * 100:.1f}%) "
                    f"已测出速度：{len(results)}",
                    end="",
                    flush=True,
                )
                last_print = now
    print()
    return results


def run_two_pass_speed_test(candidates: list[str], config: Config) -> list[SpeedResult]:
    """两轮自适应测速：探速 -> 精测"""
    if not candidates:
        return []

    if not shutil.which("curl"):
        print("未检测到 curl 命令，带宽测速将跳过。")
        return []

    # 第一轮探速：小文件 + 短超时 + 高并发
    probe_bytes = 262144  # 256KB
    probe_timeout = 6
    probe_connect_timeout = 3
    probe_workers = max(config.BANDWIDTH_WORKERS, 40)

    probe_url = config.BANDWIDTH_URL_TEMPLATE.format(bytes=probe_bytes)
    probe_speed = _run_speed_pass(candidates, probe_url, probe_timeout, probe_connect_timeout, probe_workers, "探速")

    alive_nodes = list(probe_speed.keys())
    if not alive_nodes:
        print("探速轮所有节点均无速度，跳过精测。")
        return []

    # 第二轮精测：对所有探速通过的节点用配置的大文件精测
    refine_speed = _run_speed_pass(
        alive_nodes,
        config.BANDWIDTH_URL_TEMPLATE.format(bytes=int(config.BANDWIDTH_SIZE_MB * 1024 * 1024)),
        config.BANDWIDTH_TIMEOUT,
        config.BANDWIDTH_CONNECT_TIMEOUT,
        config.BANDWIDTH_WORKERS,
        "精测",
    )

    # 合并：精测优先，缺失则用探速值
    final_speed: dict[str, float] = {}
    for node in alive_nodes:
        final_speed[node] = refine_speed.get(node, probe_speed[node])

    print(f"\n两轮测速完成：候选 {len(candidates)} → 存活 {len(alive_nodes)} → 最终 {len(final_speed)} 个节点")

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

    if not shutil.which("curl"):
        print("未检测到 curl 命令，带宽测速将跳过。")
        return []

    print(
        f"\n开始带宽测速（对前 {len(candidates)} 个节点，并发 {config.BANDWIDTH_WORKERS}"
        f"，超时 {config.BANDWIDTH_TIMEOUT}s）..."
    )

    for attempt in range(1, config.BANDWIDTH_RETRY_MAX + 1):
        print(f"\n[带宽测速] 第 {attempt} 轮测试...")
        results = run_two_pass_speed_test(candidates, config)
        if results:
            return results
        if attempt < config.BANDWIDTH_RETRY_MAX:
            print(f"本轮测速无有效结果，等待 {config.BANDWIDTH_RETRY_DELAY} 秒后重试...")
            time.sleep(config.BANDWIDTH_RETRY_DELAY)

    print(f"带宽测速经 {config.BANDWIDTH_RETRY_MAX} 轮尝试后仍无有效结果。")
    return []
