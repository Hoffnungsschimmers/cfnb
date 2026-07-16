"""订阅器管理面板：列出所有候选订阅器，支持开关与查看最近运行状态"""

from __future__ import annotations

import time
import tkinter as tk
from cfnb.gui.constants import C, SP, FONT
from cfnb.subscription import load_generators_state


def _fmt_ts(ts: float) -> str:
    if not ts:
        return "从未运行"
    try:
        return time.strftime("%m-%d %H:%M", time.localtime(ts))
    except Exception:
        return "—"


class SubscriptionManagerPanel(tk.Frame):
    """展示 SUB_GENERATORS 列表，提供启用/禁用与最近一次运行结果"""

    def __init__(self, parent, on_changed=None, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._on_changed = on_changed
        self._rows: dict[str, dict] = {}
        self._build_ui()

    def _build_ui(self):
        header = tk.Frame(self, bg=C["bg"])
        header.pack(fill=tk.X, padx=SP["xl"], pady=(SP["lg"], SP["sm"]))
        tk.Label(header, text="订阅器管理", font=FONT["h1"],
                 bg=C["bg"], fg=C["text"]).pack(side=tk.LEFT)
        tk.Label(header, text="勾选启用的订阅器，自动执行时生效",
                 font=FONT["small"], bg=C["bg"], fg=C["text_dim"]
                 ).pack(side=tk.LEFT, padx=(SP["md"], 0))

        from cfnb.gui.widgets.scrollframe import ScrollFrame
        self._scroll = ScrollFrame(self, bg=C["bg"])
        self._scroll.pack(fill=tk.BOTH, expand=True, padx=SP["md"], pady=(0, SP["sm"]))
        self.lb_frame = self._scroll.inner

        bf = tk.Frame(self, bg=C["bg"])
        bf.pack(fill=tk.X, padx=SP["xl"], pady=SP["sm"])
        tk.Button(
            bf, text="刷新状态", font=FONT["small"], bg=C["surface"],
            fg=C["text"], activebackground=C["border"], relief=tk.FLAT,
            cursor="hand2", bd=0, padx=SP["sm"], pady=SP["xs"],
            highlightthickness=1, highlightbackground=C["border"],
            command=self.refresh,
        ).pack(side=tk.LEFT)

    def refresh(self):
        """重建列表（从 config 读取当前订阅器集合）"""
        for w in self.lb_frame.winfo_children():
            w.destroy()
        self._rows.clear()

        from cfnb.config import get_config
        config = get_config()
        gens = [e for e in getattr(config, "SUB_GENERATORS", []) if e and e.strip()]
        disabled = set(getattr(config, "SUB_DISABLED_GENERATORS", set()) or set())
        state = load_generators_state()

        if not gens:
            tk.Label(self.lb_frame, text="未配置任何订阅器（请在「设置」中添加 SUB_GENERATORS）",
                     font=FONT["normal"], bg=C["bg"], fg=C["text_dim"]
                     ).pack(fill=tk.X, padx=SP["md"], pady=SP["md"])
            return

        for entry in gens:
            name = entry.split("|", 1)[0].strip() or entry
            enabled = name not in disabled
            info = state.get(name, {})
            ok = info.get("ok")
            status_txt = "从未运行" if ok is None else ("成功" if ok else "失败")
            status_color = (C["text_dim"] if ok is None
                            else (C["primary"] if ok else C["danger"]))

            row = tk.Frame(self.lb_frame, bg=C["surface"],
                           highlightthickness=1, highlightbackground=C["border"],
                           padx=SP["md"], pady=SP["sm"])
            row.pack(fill=tk.X, pady=SP["xs"])

            var = tk.BooleanVar(value=enabled)
            cb = tk.Checkbutton(
                row, variable=var, bg=C["surface"], fg=C["text"],
                selectcolor=C["surface"], activebackground=C["surface"],
                font=FONT["normal"], cursor="hand2",
                command=lambda n=name, v=var: self._toggle(n, v),
            )
            cb.pack(side=tk.LEFT, padx=(0, SP["sm"]))

            info_f = tk.Frame(row, bg=C["surface"])
            info_f.pack(side=tk.LEFT, fill=tk.X, expand=True)
            tk.Label(info_f, text=name, font=FONT["normal"],
                     bg=C["surface"], fg=C["text"], anchor="w").pack(fill=tk.X)
            sub = tk.Label(
                info_f,
                text=f"节点 {info.get('nodes', 0)} · {status_txt} · {_fmt_ts(info.get('ts', 0))}",
                font=FONT["small"], bg=C["surface"], fg=status_color, anchor="w",
            )
            sub.pack(fill=tk.X)

            self._rows[name] = {"var": var, "status": sub, "info": info}

        self._scroll.refresh_bindings()

    def _toggle(self, name: str, var: tk.BooleanVar):
        from cfnb.config import get_config, reload_config
        config = get_config()
        disabled = set(getattr(config, "SUB_DISABLED_GENERATORS", set()) or set())
        if var.get():
            disabled.discard(name)
        else:
            disabled.add(name)
        self._write_disabled(disabled)
        reload_config()
        if self._on_changed:
            self._on_changed()

    def _write_disabled(self, disabled: set):
        import json
        from cfnb.gui.constants import CONFIG_FILE
        raw = json.loads(open(CONFIG_FILE, encoding="utf-8").read())
        clean = {k: v for k, v in raw.items() if not str(k).startswith("_comment")}
        clean["SUB_DISABLED_GENERATORS"] = sorted(disabled)
        # 保留注释键
        out = {k: v for k, v in raw.items() if str(k).startswith("_comment")}
        out.update(clean)
        json.dump(out, open(CONFIG_FILE, "w", encoding="utf-8"),
                  indent=4, ensure_ascii=False)

    def apply_theme(self):
        try:
            self.configure(bg=C["bg"])
            self.lb_frame.configure(bg=C["bg"])
            for name, rec in self._rows.items():
                info = rec.get("info", {})
                ok = info.get("ok")
                rec["status"].configure(
                    fg=(C["text_dim"] if ok is None
                        else (C["primary"] if ok else C["danger"]))
                )
        except Exception:
            pass
