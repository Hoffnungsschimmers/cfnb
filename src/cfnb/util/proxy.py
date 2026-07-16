"""代理环境变量开关工具。

测速 / TCP / 可用性检测需要直连，避免系统代理干扰结果。
CLI 与 GUI 都会用到同一套逻辑，这里集中实现，避免两边重复且不一致。
"""

from __future__ import annotations

import os
from typing import Dict, Optional

_PROXY_VARS = [
    "http_proxy",
    "https_proxy",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "all_proxy",
]


def disable_proxy() -> Dict[str, Optional[str]]:
    """临时禁用系统代理（直连测试）。

    返回被修改前各代理变量的值映射，传给 restore_proxy 即可还原。
    """
    saved: Dict[str, Optional[str]] = {}
    for var in _PROXY_VARS:
        saved[var] = os.environ.pop(var, None)
    os.environ["NO_PROXY"] = "*"
    return saved


def restore_proxy(saved: Dict[str, Optional[str]]) -> None:
    """还原 disable_proxy 保存的代理变量。"""
    if not saved:
        return
    for var, val in saved.items():
        if val is not None:
            os.environ[var] = val
        elif var in os.environ:
            del os.environ[var]
    os.environ.pop("NO_PROXY", None)
