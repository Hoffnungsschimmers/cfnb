#!/usr/bin/env python3
"""对已获取并去重后的订阅节点做 TCP 连接延迟测试，保留延迟最优的前 N 名。

节点格式（与 addressesapi.txt 一致）：`IP:端口#国家码`，例如 `1.2.3.4:443#JP`。
延迟通过向 `IP:端口` 发起一次 TCP 连接（测量握手往返时间）来估算，
这是代理节点可用性与就近性的合理近似，且无需真正建立代理隧道。
"""

from __future__ import annotations

import json
import socket
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Optional


def parse_endpoint(node: str) -> Optional[tuple[str, int]]:
    """从 `IP:端口#CC` 节点行中解析出 (ip, port)。无法解析返回 None。"""
    if not node:
        return None
    base = node.split("#", 1)[0].strip()
    if not base:
        return None
    if base.startswith("["):
        rb = base.find("]")
        if rb == -1:
            return None
        ip = base[1:rb]
        rest = base[rb + 1:]
        if not rest.startswith(":"):
            return None
        port_str = rest[1:]
    else:
        if ":" not in base:
            return None
        ip, _, port_str = base.rpartition(":")
    try:
        port = int(port_str.strip())
    except (ValueError, TypeError):
        return None
    if port <= 0 or port > 65535:
        return None
    return ip, port


def measure_latency(ip: str, port: int, timeout: float) -> Optional[float]:
    """测量到 (ip, port) 的 TCP 连接延迟（秒）。失败/超时返回 None。"""
    start = time.perf_counter()
    try:
        sock = socket.socket(
            socket.AF_INET if ":" not in ip else socket.AF_INET6,
            socket.SOCK_STREAM,
        )
        sock.settimeout(timeout)
        sock.connect((ip, port))
        elapsed = time.perf_counter() - start
        sock.close()
        return elapsed
    except (OSError, socket.timeout):
        return None


def _node_country(node: str) -> str:
    """提取节点注释里的国家码（# 之后、@来源 之前的部分）。"""
    comment = node.split("#", 1)[1] if "#" in node else ""
    return comment.split("@", 1)[0].strip()


def latency_filter(
    input_file: str,
    output_file: str,
    topn: int,
    timeout: float,
    workers: int,
    node_source: dict[str, str] | None = None,
) -> tuple[list[str], int, int]:
    """对 input_file 中的去重节点做延迟测试，保留延迟最优的前 topn 名写入 output_file。

    node_source 为可选的 节点->来源名 映射（如 CM / IDK），若提供则在输出行的
    注释中标注来源（格式 IP:PORT#CC@来源），方便查看每个 IP 来自哪个订阅器。

    除主输出文件（人类可读的 IP:PORT#CC@来源 <延迟> ms）外，还会在同目录生成
    `<output>.json`（结构化：含 IP/端口/国家/来源/延迟，以及各来源统计），
    便于二次处理与历史对比。

    返回 (保留的节点列表, 参与测试数, 成功连通数)。
    """
    with open(input_file, encoding="utf-8") as f:
        nodes = [ln.strip() for ln in f if ln.strip()]

    targets = []
    for node in nodes:
        ep = parse_endpoint(node)
        if ep:
            targets.append((node, ep[0], ep[1]))

    results: list[tuple[str, Optional[float]]] = []

    def _work(item: tuple[str, str, int]) -> tuple[str, Optional[float]]:
        node, ip, port = item
        return node, measure_latency(ip, port, timeout)

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futures = {ex.submit(_work, t): t for t in targets}
        for fut in as_completed(futures):
            try:
                node, lat = fut.result()
            except Exception:
                node = futures[fut][0]
                lat = None
            results.append((node, lat))

    succeeded = [r for r in results if r[1] is not None]
    failed = [r for r in results if r[1] is None]

    succeeded.sort(key=lambda r: r[1])
    ordered = succeeded + failed

    kept = [node for node, _ in ordered[:topn]]

    # 主输出文件：人类可读，每行 IP:PORT#CC@来源 <延迟> ms
    with open(output_file, "w", encoding="utf-8", newline="\n") as f:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        f.write(f"# 延迟优选结果 @ {ts} | 共测 {len(targets)} 连通 {len(succeeded)} 保留 {min(topn, len(ordered))}\n")
        for node, lat in ordered[:topn]:
            src = ""
            if node_source and node in node_source:
                src = "@" + node_source[node]
            if lat is None:
                f.write(f"{node}{src} 超时\n")
            else:
                f.write(f"{node}{src} {lat * 1000:.2f} ms\n")

    # 结构化 JSON：每条含 IP/端口/国家/来源/延迟(ms)，并附各来源统计
    records = []
    for node, lat in ordered[:topn]:
        ip, port = parse_endpoint(node) or ("", 0)
        records.append({
            "ip": ip,
            "port": port,
            "country": _node_country(node),
            "source": node_source.get(node, "") if node_source else "",
            "latency_ms": None if lat is None else round(lat * 1000, 2),
        })
    source_stats = Counter(r["source"] or "未知" for r in records)
    json_path = str(Path(output_file).with_suffix(".json"))
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(
            {
                "generated_at": ts,
                "tested": len(targets),
                "connected": len(succeeded),
                "kept": len(records),
                "source_stats": dict(source_stats),
                "nodes": records,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    return kept, len(targets), len(succeeded)


def save_latency_history(output_file: str, topn_kept: int, tested: int,
                         connected: int) -> Optional[str]:
    """把本轮延迟优选摘要追加写入 history/latency_history.csv，便于趋势对比。

    返回写入的历史文件路径；history 目录不存在时自动创建。
    CSV 列：时间, 测试数, 连通数, 保留数。
    """
    out = Path(output_file)
    hist_dir = out.parent / "history"
    hist_dir.mkdir(parents=True, exist_ok=True)
    hist_file = hist_dir / "latency_history.csv"
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header = "time,tested,connected,kept\n"
    line = f"{ts},{tested},{connected},{topn_kept}\n"
    try:
        if not hist_file.exists():
            with open(hist_file, "w", encoding="utf-8") as f:
                f.write(header)
        with open(hist_file, "a", encoding="utf-8") as f:
            f.write(line)
        return str(hist_file)
    except Exception:
        return None
