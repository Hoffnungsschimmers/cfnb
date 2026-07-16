"""结构化进度输出工具。

GUI 通过解析 CLI 的 stdout 来驱动进度条/仪表盘。为避免"字符串契约"脆弱
（任何打印格式改动都会静默破坏 UI），这里提供统一的 JSON 行协议：

    [PROGRESS] {"type": "speed", "value": 12.3, "node": "1.2.3.4:443"}
    [PROGRESS] {"type": "tcp", "value": 5.1, "node": "1.2.3.4:443"}
    [PROGRESS] {"type": "stage", "key": "bw", "status": "running"}
    [PROGRESS] {"type": "stage", "key": "bw", "status": "done", "progress": 100}

GUI 端用前缀 `[PROGRESS]` 识别并 json.loads 即可，与传统文本日志互不干扰。
"""

from __future__ import annotations

import json
import sys


def emit_progress(payload: dict) -> None:
    """向 stdout 输出一行结构化进度事件（带 [PROGRESS] 前缀）。"""
    try:
        line = "[PROGRESS] " + json.dumps(payload, ensure_ascii=False)
        print(line, flush=True)
    except Exception:
        pass


def emit_speed(node: str, mbps: float) -> None:
    emit_progress({"type": "speed", "node": node, "value": round(mbps, 2)})


def emit_tcp(node: str, latency_ms: float) -> None:
    emit_progress({"type": "tcp", "node": node, "value": round(latency_ms, 1)})


def emit_stage(key: str, status: str, progress: int | None = None) -> None:
    payload: dict = {"type": "stage", "key": key, "status": status}
    if progress is not None:
        payload["progress"] = progress
    emit_progress(payload)
