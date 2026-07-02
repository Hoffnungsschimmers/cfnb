#!/usr/bin/env python3
"""CF优选工具 - 图形界面（全面修复版 v5）

修复：
- 主布局改用 grid，彻底解决内容区不显示的问题
- 移除所有 Frame 构造器中传入的无效 padx/pady 参数
- Settings 页滚动容器修复
- 日志区背景色修复
- 所有区域正确 expand
"""

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time

import tkinter as tk
from tkinter import ttk, messagebox
from tkinter.scrolledtext import ScrolledText

# ═══════════════════════════════════════════════════════════════════
# 路径 & 常量
# ═══════════════════════════════════════════════════════════════════
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "config.json")
IP_FILE = os.path.join(SCRIPT_DIR, "ip.txt")
GUI_LOG_FILE = os.path.join(SCRIPT_DIR, "gui.log")
PYTHON = sys.executable

SP_KW: dict = {}
if sys.platform == "win32":
    _si = subprocess.STARTUPINFO()
    _si.dwFlags = subprocess.STARTF_USESHOWWINDOW
    _si.wShowWindow = 0
    SP_KW = {"startupinfo": _si, "creationflags": 0x08000000}

# ═══════════════════════════════════════════════════════════════════
# 统一色板 & 设计系统
# ═══════════════════════════════════════════════════════════════════
C = {
    "bg":            "#f8fafc",
    "surface":       "#ffffff",
    "sidebar":       "#0f172a",
    "sidebar_hover": "#1e293b",
    "sidebar_active":"#2563eb",
    "primary":       "#2563eb",
    "primary_hover": "#1d4ed8",
    "primary_light": "#eff6ff",
    "primary_lighter": "#f0f7ff",
    "text":          "#1e293b",
    "text_secondary":"#475569",
    "text_dim":      "#64748b",
    "text_inv":      "#f1f5f9",
    "text_inv_dim":  "#94a3b8",
    "border":        "#e2e8f0",
    "border_light":  "#f1f5f9",
    "success":       "#10b981",
    "success_light": "#ecfdf5",
    "warning":       "#f59e0b",
    "warning_light": "#fffbeb",
    "danger":        "#ef4444",
    "danger_light":  "#fef2f2",
    "log_bg":        "#1e293b",
    "log_fg":        "#e2e8f0",
    "shadow":        "#00000010",
    "accent":        "#6366f1",
}

SP = {
    "xs": 4, "sm": 8, "md": 12,
    "lg": 16, "xl": 24, "xxl": 32,
}

_FF = "微软雅黑" if sys.platform == "win32" else "Segoe UI"
FONT = {
    "title":   (_FF, 18, "bold"),
    "h1":      (_FF, 14, "bold"),
    "h2":      (_FF, 12, "bold"),
    "h3":      (_FF, 11, "bold"),
    "normal":  (_FF, 10),
    "small":   (_FF, 9),
    "mono":    ("Consolas", 9),
    "btn":     (_FF, 10, "bold"),
    "btn_lg":  (_FF, 11, "bold"),
    "status":  (_FF, 9),
}

STAGES: list[tuple[str, str, str, str]] = [
    ("cfdata", "CFData",   "扫描网段",   "🔍"),
    ("fetch",  "获取IP",   "拉取节点",   "📥"),
    ("avail",  "TCP检测",  "可用性检测", "🔗"),
    ("bw",     "带宽测速", "测速",       "⚡"),
    ("push",   "推送",     "GitHub",     "🚀"),
]

SKIP_LINES = [
    "当前模式", "最低成功率", "IP 可用性", "IPv6 客户端",
    "DNS黑名单", "IP 风险等级", "带宽测速候选数",
    "前置白名单", "日志已启用", "等待", "已尝试", "批量查询中",
]

LOG_MAX = 2000

SETTINGS_FIELDS = [
    ("筛选设置", "端口过滤",     "PRE_FILTER_PORT_ENABLED",     "bool",     None),
    ("筛选设置", "允许端口",     "PRE_FILTER_PORTS",            "list_int", None),
    ("筛选设置", "黑名单过滤",   "PRE_FILTER_BLOCKED_ENABLED",  "bool",     None),
    ("筛选设置", "屏蔽国家",     "PRE_FILTER_BLOCKED_COUNTRIES","list_str", None),
    ("筛选设置", "白名单过滤",   "FILTER_COUNTRIES_ENABLED",    "bool",     None),
    ("筛选设置", "允许国家",     "ALLOWED_COUNTRIES",           "list_str", None),
    ("筛选设置", "最低成功率",   "MIN_SUCCESS_RATE",            "float",    (0.0, 1.0, 0.05)),
    ("测速设置", "候选数",       "BANDWIDTH_CANDIDATES",        "int",      (100, 5000, 100)),
    ("测速设置", "下载大小(MB)", "BANDWIDTH_SIZE_MB",           "float",    (0.1, 100.0, 0.5)),
    ("测速设置", "测速超时(秒)", "BANDWIDTH_TIMEOUT",           "int",      (5, 300, 10)),
    ("测速设置", "测速并发",     "BANDWIDTH_WORKERS",           "int",      (1, 200, 5)),
    ("DNS设置",  "DNS更新",      "CF_ENABLED",                  "bool",     None),
    ("DNS设置",  "API Token",    "CF_API_TOKEN",                "string",   None),
    ("DNS设置",  "Zone ID",      "CF_ZONE_ID",                  "string",   None),
    ("DNS设置",  "记录名",       "CF_DNS_RECORD_NAME",          "string",   None),
    ("DNS设置",  "TTL",          "CF_TTL",                      "int",      (60, 86400, 60)),
    ("DNS设置",  "记录类型",     "DNS_RECORD_TYPE",             "choice",   ("A", "TXT")),
    ("DNS设置",  "DNS更新数",    "DNS_UPDATE_TARGET_COUNT",     "int",      (1, 200, 15)),
    ("输出设置", "全局模式",     "USE_GLOBAL_MODE",             "bool",     None),
    ("输出设置", "保留节点数",   "GLOBAL_TOP_N",                "int",      (1, 200, 38)),
    ("输出设置", "显示带宽",     "IP_TXT_SHOW_BANDWIDTH",       "bool",     None),
    ("输出设置", "显示延迟",     "IP_TXT_SHOW_LATENCY",         "bool",     None),
]


# ═══════════════════════════════════════════════════════════════════
# StepperWidget — 时间线进度指示器
# ═══════════════════════════════════════════════════════════════════
class StepperWidget(tk.Frame):
    """5 步时间线进度指示器，带脉冲动画"""

    def __init__(self, parent, stages, height=56, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._stages = stages
        self._status = {k: "idle" for k, _, _, _ in stages}
        self._pulse_phase = 0
        self._animating = False
        self._canvas = tk.Canvas(
            self, bg=self.cget("bg"), height=max(height, 70), highlightthickness=0,
        )
        self._canvas.pack(fill=tk.BOTH, expand=True)
        self._canvas.bind("<Configure>", self._draw)

    def set_status(self, key, status):
        self._status[key] = status
        if status == "running" and not self._animating:
            self._animating = True
            self._animate()
        elif status != "running" and self._animating:
            self._animating = False
        self._draw()

    def reset(self):
        for k in self._status:
            self._status[k] = "idle"
        self._animating = False
        self._draw()

    def _animate(self):
        if not self._animating:
            return
        self._pulse_phase = (self._pulse_phase + 1) % 20
        self._draw()
        self.after(50, self._animate)

    def _draw(self, _evt=None):
        c = self._canvas
        c.delete("all")
        w = max(c.winfo_width(), 300)
        n = len(self._stages)
        margin = max(16, int(w * 0.04))
        sp = (w - 2 * margin) / max(n - 1, 1)
        cy = 22
        r = 13

        pal = {
            "idle":    C["border"],
            "running": C["primary"],
            "done":    C["success"],
            "fail":    C["danger"],
        }

        for i, (key, short, desc, icon) in enumerate(self._stages):
            x = margin + i * sp
            st = self._status.get(key, "idle")
            col = pal.get(st, C["border"])

            if i > 0:
                x0 = margin + (i - 1) * sp
                prev_done = self._status[self._stages[i - 1][0]] == "done"
                lc = C["success"] if prev_done else C["border"]
                c.create_line(
                    x0 + r + 2, cy, x - r - 2, cy,
                    fill=lc, width=2.5, capstyle=tk.ROUND,
                )

            if st == "running":
                pulse_r = r + 5 + (self._pulse_phase % 10) * 0.8
                c.create_oval(
                    x - pulse_r, cy - pulse_r, x + pulse_r, cy + pulse_r,
                    outline=C["primary"], width=1.5,
                )

            if st == "done":
                c.create_oval(x - r, cy - r, x + r, cy + r, fill=col, outline="")
                c.create_text(x, cy, text="✓", fill="white",
                              font=("", 10, "bold"))
            elif st == "fail":
                c.create_oval(x - r, cy - r, x + r, cy + r, fill=col, outline="")
                c.create_text(x, cy, text="✗", fill="white",
                              font=("", 10, "bold"))
            else:
                c.create_oval(
                    x - r - 2, cy - r - 2, x + r + 2, cy + r + 2,
                    fill=C["surface"], outline=col, width=2,
                )
                c.create_text(x, cy, text=icon, fill=col, font=("", 12))

            c.create_text(x, cy + r + 12, text=short,
                          fill=C["text"] if st == "idle" else C["primary"],
                          font=FONT["h3"])
            c.create_text(x, cy + r + 28, text=desc,
                          fill=C["text_dim"], font=FONT["small"])


# ═══════════════════════════════════════════════════════════════════
# SettingsPanel — 卡片式设置面板
# ═══════════════════════════════════════════════════════════════════
class SettingsPanel(tk.Frame):
    """分栏卡片式设置面板，支持滚动"""

    def __init__(self, parent, on_save=None, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._on_save = on_save
        self._orig: dict = {}
        self._vars: dict[str, tk.Variable] = {}
        self._types: dict[str, str] = {}
        self._opts: dict = {}
        self._build_ui()

    def _build_ui(self):
        # 标题栏
        header = tk.Frame(self, bg=C["bg"])
        header.pack(fill=tk.X, padx=SP["xl"], pady=(SP["lg"], SP["sm"]))
        tk.Label(header, text="设置", font=FONT["h1"],
                 bg=C["bg"], fg=C["text"]).pack(side=tk.LEFT)
        tk.Label(header, text="修改后点击「保存」生效",
                 font=FONT["small"], bg=C["bg"], fg=C["text_dim"]
                 ).pack(side=tk.LEFT, padx=(SP["md"], 0))

        # 滚动容器（使用 Canvas + Frame）
        outer = tk.Frame(self, bg=C["bg"])
        outer.pack(fill=tk.BOTH, expand=True)

        canvas = tk.Canvas(outer, bg=C["bg"], highlightthickness=0)
        sb = ttk.Scrollbar(outer, orient=tk.VERTICAL, command=canvas.yview)
        canvas.configure(yscrollcommand=sb.set)

        container = tk.Frame(canvas, bg=C["bg"])
        canvas_window = canvas.create_window((0, 0), window=container, anchor="nw")

        sb.pack(side=tk.RIGHT, fill=tk.Y)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        def _on_canvas_configure(_evt):
            canvas.itemconfig(canvas_window, width=canvas.winfo_width())
            canvas.configure(scrollregion=canvas.bbox("all"))

        container.bind("<Configure>", _on_canvas_configure)
        canvas.bind("<Configure>", _on_canvas_configure)

        def _mw(evt):
            canvas.yview_scroll(int(-1 * (evt.delta / 120)), "units")

        canvas.bind("<MouseWheel>", _mw)
        container.bind("<MouseWheel>", _mw)

        # 设置项
        cur_cat = None
        for cat, label, key, wtype, opts in SETTINGS_FIELDS:
            if cat != cur_cat:
                cur_cat = cat
                cat_frame = tk.Frame(container, bg=C["bg"])
                cat_frame.pack(fill=tk.X, padx=SP["lg"], pady=(SP["lg"], SP["xs"]))
                tk.Label(cat_frame, text=f"  {cat}", font=FONT["h2"],
                         bg=C["bg"], fg=C["primary"], anchor="w"
                         ).pack(fill=tk.X)

            row = tk.Frame(container, bg=C["surface"],
                           padx=SP["lg"], pady=SP["sm"],
                           highlightthickness=1,
                           highlightbackground=C["border"])
            row.pack(fill=tk.X, padx=SP["lg"], pady=SP["xs"])

            lbl = tk.Label(row, text=label, font=FONT["normal"],
                           bg=C["surface"], fg=C["text"],
                           width=12, anchor="w")
            lbl.pack(side=tk.LEFT)

            widget = self._create_widget(row, key, wtype, opts)
            widget.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(SP["sm"], 0))

        # 底部按钮
        bf = tk.Frame(self, bg=C["bg"])
        bf.pack(fill=tk.X, padx=SP["xl"], pady=SP["md"])
        ttk.Button(bf, text="保存配置", command=self.save, width=12
                   ).pack(side=tk.RIGHT, padx=(SP["xs"], 0))
        ttk.Button(bf, text="重置", command=self.reload, width=8
                   ).pack(side=tk.RIGHT)

    def _create_widget(self, parent, key, wtype, opts):
        var = None
        if wtype == "bool":
            var = tk.BooleanVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Checkbutton(parent, variable=var)

        if wtype == "int":
            var = tk.IntVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Spinbox(
                parent, from_=opts[0], to=opts[1],
                increment=opts[2], textvariable=var, width=16,
            )

        if wtype == "float":
            var = tk.DoubleVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Spinbox(
                parent, from_=opts[0], to=opts[1],
                increment=opts[2], textvariable=var, width=16,
                format="%.2f",
            )

        if wtype == "string":
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Entry(parent, textvariable=var, width=24)

        if wtype in ("list_int", "list_str"):
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Entry(parent, textvariable=var, width=24)

        if wtype == "choice":
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = tuple(opts) if opts else ()
            return ttk.Combobox(
                parent, textvariable=var,
                values=list(opts or []),
                state="readonly", width=24,
            )

        var = tk.StringVar()
        self._vars[key] = var
        self._types[key] = "string"
        self._opts[key] = opts
        return ttk.Entry(parent, textvariable=var, width=24)

    def load_config(self):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                raw = json.load(f)
            data = {k: v for k, v in raw.items()
                    if not str(k).startswith("_comment")}
            self._orig = dict(data)
            for key, var in self._vars.items():
                if key in data:
                    self._apply(key, data[key])
        except Exception as e:
            messagebox.showerror("错误", f"加载配置失败: {e}")

    def save(self):
        try:
            payload = {}
            for key, var in self._vars.items():
                payload[key] = self._extract(key, var)

            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                raw = json.load(f)
            clean = {k: v for k, v in raw.items()
                     if not str(k).startswith("_comment")}
            clean.update(payload)

            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(clean, f, indent=4, ensure_ascii=False)

            self._orig = clean
            try:
                from config import reload_config
                reload_config()
            except ImportError:
                pass
            if self._on_save:
                self._on_save()
            messagebox.showinfo("设置", "配置已保存")
        except Exception as e:
            messagebox.showerror("错误", f"保存失败: {e}")

    def reload(self):
        for key, var in self._vars.items():
            if key in self._orig:
                self._apply(key, self._orig[key])

    def _apply(self, key, val):
        wtype = self._types[key]
        try:
            if wtype == "bool":
                self._vars[key].set(bool(val))
            elif wtype == "int":
                self._vars[key].set(int(val))
            elif wtype == "float":
                self._vars[key].set(float(val))
            elif wtype == "list_int":
                v = ", ".join(map(str, val)) if isinstance(val, list) else str(val)
                self._vars[key].set(v)
            elif wtype == "list_str":
                v = ", ".join(val) if isinstance(val, list) else str(val)
                self._vars[key].set(v)
            else:
                self._vars[key].set(str(val) if val is not None else "")
        except Exception:
            pass

    def _extract(self, key, var):
        wtype = self._types[key]
        try:
            if wtype == "bool":
                return var.get()
            if wtype == "int":
                return int(var.get())
            if wtype == "float":
                return float(var.get())
            if wtype == "list_int":
                return [int(x.strip()) for x in str(var.get()).split(",") if x.strip()]
            if wtype == "list_str":
                return [x.strip() for x in str(var.get()).split(",") if x.strip()]
            return str(var.get())
        except Exception:
            if wtype == "bool":
                return False
            if wtype == "int":
                return 0
            if wtype == "float":
                return 0.0
            if wtype in ("list_int", "list_str"):
                return []
            return ""


# ═══════════════════════════════════════════════════════════════════
# ResultsPanel — 结果表格
# ═══════════════════════════════════════════════════════════════════
class ResultsPanel(tk.Frame):
    """表格展示 ip.txt，支持排序、颜色编码、斑马纹、复制"""

    COLS = ("rank", "ip_port", "country", "speed", "latency")
    COL_NAMES = {
        "rank": "#", "ip_port": "IP:端口", "country": "国家",
        "speed": "带宽(Mbps)", "latency": "延迟(ms)",
    }
    COL_WIDTHS = {
        "rank": 50, "ip_port": 200, "country": 75,
        "speed": 100, "latency": 85,
    }
    TAG_COLORS = {
        "fast":    C["success"],
        "medium":  C["warning"],
        "slow":    C["danger"],
        "unknown": C["text_dim"],
    }

    def __init__(self, parent, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._data: list[dict] = []
        self._sort_col = None
        self._sort_rev = False
        self._build_ui()

    def _build_ui(self):
        sf = tk.Frame(self, bg=C["bg"])
        sf.pack(fill=tk.X, padx=SP["xl"], pady=(SP["lg"], SP["sm"]))
        tk.Label(sf, text="优选结果", font=FONT["h1"],
                 bg=C["bg"], fg=C["text"]).pack(side=tk.LEFT)
        self._stats_lbl = tk.Label(
            sf, text="点击「刷新」加载数据", font=FONT["small"],
            bg=C["bg"], fg=C["text_dim"],
        )
        self._stats_lbl.pack(side=tk.RIGHT)

        tb = tk.Frame(self, bg=C["surface"], padx=SP["lg"], pady=SP["sm"])
        tb.pack(fill=tk.X, padx=SP["xl"], pady=(0, SP["sm"]))

        self._info_lbl = tk.Label(tb, text="", font=FONT["small"],
                                  bg=C["surface"], fg=C["text_dim"])
        self._info_lbl.pack(side=tk.LEFT)

        btn_frame = tk.Frame(tb, bg=C["surface"])
        btn_frame.pack(side=tk.RIGHT)
        ttk.Button(btn_frame, text="刷新", command=self.refresh, width=8
                   ).pack(side=tk.RIGHT, padx=(SP["xs"], 0))
        ttk.Button(btn_frame, text="复制全部", command=self._copy_all, width=8
                   ).pack(side=tk.RIGHT, padx=(SP["xs"], 0))
        ttk.Button(btn_frame, text="复制选中", command=self._copy_sel, width=8
                   ).pack(side=tk.RIGHT)

        tf = tk.Frame(self, bg=C["surface"], padx=SP["lg"], pady=SP["sm"])
        tf.pack(fill=tk.BOTH, expand=True, padx=SP["xl"], pady=(0, SP["lg"]))

        self._tree = ttk.Treeview(
            tf, columns=self.COLS, show="headings", selectmode="extended",
        )
        for col in self.COLS:
            self._tree.heading(col, text=self.COL_NAMES[col],
                               command=lambda c=col: self._sort(c))
            w = self.COL_WIDTHS.get(col, 80)
            anchor = (
                "center" if col in ("rank", "country")
                else ("e" if col in ("speed", "latency") else "w")
            )
            self._tree.column(col, width=w, anchor=anchor, minwidth=40)

        tsb = ttk.Scrollbar(tf, orient=tk.VERTICAL, command=self._tree.yview)
        self._tree.configure(yscrollcommand=tsb.set)

        self._tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tsb.pack(side=tk.RIGHT, fill=tk.Y)

        for tag, color in self.TAG_COLORS.items():
            self._tree.tag_configure(tag, foreground=color)
        self._tree.tag_configure("even", background=C["border_light"])
        self._tree.tag_configure("odd", background=C["surface"])

        self._tree.bind("<Double-1>", lambda e: self._copy_sel())

    def refresh(self):
        self._data = []
        self._tree.delete(*self._tree.get_children())
        if not os.path.exists(IP_FILE):
            self._stats_lbl.config(text="ip.txt 不存在")
            self._info_lbl.config(text="")
            return
        try:
            with open(IP_FILE, encoding="utf-8") as f:
                for line in f:
                    p = self._parse(line)
                    if p:
                        self._data.append(p)
        except OSError as e:
            self._stats_lbl.config(text=f"读取失败: {e}")
            return
        self._render()
        self._calc_stats()

    @staticmethod
    def _parse(line):
        s = line.strip()
        if not s or s.startswith("#"):
            return None
        parts = s.split("#", 1)
        ip = parts[0].strip()
        country = spd = lat = ""
        if len(parts) > 1:
            rest = parts[1].strip()
            tkns = rest.split()
            if tkns and len(tkns[0]) == 2 and tkns[0].isupper():
                country = tkns[0]
                rest = " ".join(tkns[1:])
            for t in rest.split():
                if "Mbps" in t:
                    try:
                        spd = f"{float(t.replace('Mbps', '').strip()):.2f}"
                    except ValueError:
                        pass
                elif "ms" in t:
                    try:
                        lat = f"{float(t.replace('ms', '').strip()):.2f}"
                    except ValueError:
                        pass
        return {"ip_port": ip, "country": country,
                "speed": spd, "latency": lat} if ip else None

    def _render(self):
        self._tree.delete(*self._tree.get_children())
        data = list(self._data)
        if self._sort_col:
            col = self._sort_col
            rev = self._sort_rev
            keymap = {
                "speed": lambda x: float(x["speed"]) if x["speed"] else 0,
                "latency": lambda x: float(x["latency"]) if x["latency"] else 0,
            }
            fn = keymap.get(col, lambda x: x.get(col, ""))
            data.sort(key=fn, reverse=rev)

        for i, d in enumerate(data):
            spd_val = float(d["speed"]) if d["speed"] else 0
            tag = (
                "fast" if spd_val > 50
                else ("medium" if spd_val > 20
                      else ("slow" if spd_val > 0 else "unknown"))
            )
            row_tag = "even" if i % 2 == 0 else "odd"
            vals = (
                i + 1, d["ip_port"], d["country"],
                d["speed"] if d["speed"] else "\u2014",
                d["latency"] if d["latency"] else "\u2014",
            )
            self._tree.insert("", tk.END, values=vals, tags=(tag, row_tag))

    def _sort(self, col):
        if self._sort_col == col:
            self._sort_rev = not self._sort_rev
        else:
            self._sort_col = col
            self._sort_rev = False
        self._render()

    def _calc_stats(self):
        if not self._data:
            self._stats_lbl.config(text="无数据")
            self._info_lbl.config(text="")
            return
        speeds = [float(d["speed"]) for d in self._data if d["speed"]]
        cnt = len(self._data)
        if speeds:
            self._stats_lbl.config(text=f"共 {cnt} 个节点")
            self._info_lbl.config(
                text=(
                    f"平均 {sum(speeds) / len(speeds):.1f} Mbps"
                    f"  |  最快 {max(speeds):.1f}"
                    f"  |  最慢 {min(speeds):.1f}"
                ),
            )
        else:
            self._stats_lbl.config(text=f"共 {cnt} 个节点")
            self._info_lbl.config(text="暂无测速数据")

    def _copy_sel(self):
        sel = self._tree.selection()
        if not sel:
            messagebox.showinfo("提示", "请先选择节点")
            return
        txt = "\n".join(self._tree.item(s)["values"][1] for s in sel)
        self._clip(txt)

    def _copy_all(self):
        if not self._data:
            messagebox.showinfo("提示", "没有可复制的数据")
            return
        self._clip("\n".join(d["ip_port"] for d in self._data))

    def _clip(self, txt):
        self.clipboard_clear()
        self.clipboard_append(txt)
        messagebox.showinfo("提示", f"已复制 {len(txt.splitlines())} 行到剪贴板")


# ═══════════════════════════════════════════════════════════════════
# CFGui — 主应用
# ═══════════════════════════════════════════════════════════════════
class CFGui:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("CF优选工具 v2.0")
        self.root.geometry("960x680")
        self.root.minsize(860, 600)
        self.root.configure(bg=C["bg"])

        try:
            if sys.platform == "win32":
                self.root.iconbitmap(default="")
        except Exception:
            pass

        self.busy = False
        self.stage_status = {k: "idle" for k, _, _, _ in STAGES}
        self.current_process = None
        self._current_page = ""
        self.log_collapsed = False
        self._run_start_time = None
        self._stopped = False  # 用户主动停止标记

        # 启动时检查依赖
        self._check_dependencies()

        self._build_ui()

    # ═══════════════════════════════════════════════════════════════
    #  整体布局（grid 主框架）
    # ═══════════════════════════════════════════════════════════════
    def _build_ui(self):
        root = self.root

        # root grid: 列0=侧边栏(固定160px)，列1=内容区(弹性)
        root.grid_columnconfigure(0, weight=0, minsize=160)
        root.grid_columnconfigure(1, weight=1)
        root.grid_rowconfigure(0, weight=1)

        # ── 侧边栏 ──
        sb = tk.Frame(root, bg=C["sidebar"], width=160)
        sb.grid(row=0, column=0, sticky="nsw")
        sb.grid_propagate(False)
        self._sidebar = sb

        # Logo 区域
        lf = tk.Frame(sb, bg=C["sidebar"])
        lf.pack(fill=tk.X, padx=SP["lg"], pady=(SP["xxl"], SP["md"]))
        tk.Label(lf, text="🌐", font=("", 22),
                 bg=C["sidebar"], fg=C["text_inv"]).pack(side=tk.LEFT)
        tk.Label(lf, text="CF优选", font=FONT["title"],
                 bg=C["sidebar"], fg=C["text_inv"]).pack(
            side=tk.LEFT, padx=(SP["sm"], 0))

        ttk.Separator(sb, orient=tk.HORIZONTAL).pack(
            fill=tk.X, padx=SP["lg"], pady=(0, SP["sm"]))

        # 导航按钮
        self._nav_btns: dict[str, tk.Button] = {}
        nav_items = [
            ("run",      "▶",  "运行",  "一键执行完整流程"),
            ("settings", "⚙",  "设置",  "配置参数"),
            ("results",  "📊", "结果",  "查看优选结果"),
        ]
        for key, icon, label, _tooltip in nav_items:
            btn_frame = tk.Frame(sb, bg=C["sidebar"])
            btn_frame.pack(fill=tk.X, padx=SP["sm"], pady=SP["xs"])

            b = tk.Button(
                btn_frame,
                text=f"  {icon}  {label}",
                font=FONT["normal"],
                bg=C["sidebar"],
                fg=C["text_inv_dim"],
                activebackground=C["sidebar_hover"],
                activeforeground=C["text_inv"],
                relief=tk.FLAT,
                cursor="hand2",
                bd=0,
                padx=SP["lg"],
                pady=SP["md"],
                anchor="w",
                command=lambda k=key: self._switch_page(k),
            )
            b.pack(fill=tk.X)
            b.bind(
                "<Enter>",
                lambda e, btn=b, k=key: self._nav_hover(btn, k, True),
            )
            b.bind(
                "<Leave>",
                lambda e, btn=b, k=key: self._nav_hover(btn, k, False),
            )
            self._nav_btns[key] = b

        # 底部版本信息
        vf = tk.Frame(sb, bg=C["sidebar"])
        vf.pack(side=tk.BOTTOM, fill=tk.X, padx=SP["lg"], pady=SP["md"])
        tk.Label(vf, text="v2.0.0", font=FONT["small"],
                 bg=C["sidebar"], fg=C["text_inv_dim"]).pack()

        # ── 内容区（grid: row0=页面 80%, row1=日志 20%） ──
        content = tk.Frame(root, bg=C["bg"])
        content.grid(row=0, column=1, sticky="nsew")
        content.grid_rowconfigure(0, weight=4)   # 页面区占 80%
        content.grid_rowconfigure(1, weight=1)   # 日志区占 20%
        content.grid_columnconfigure(0, weight=1)
        self._content = content

        # 页面容器
        pages_frame = tk.Frame(content, bg=C["bg"])
        pages_frame.grid(row=0, column=0, sticky="nsew")
        pages_frame.grid_rowconfigure(0, weight=1)
        pages_frame.grid_columnconfigure(0, weight=1)
        self._pages_frame = pages_frame

        # 创建三个页面（叠放，用 tkraise 切换）
        run_pg = tk.Frame(pages_frame, bg=C["bg"])
        run_pg.grid(row=0, column=0, sticky="nsew")
        self._build_run(run_pg)

        self._panel_settings = SettingsPanel(
            pages_frame, on_save=self._settings_saved,
        )
        self._panel_settings.grid(row=0, column=0, sticky="nsew")

        self._panel_results = ResultsPanel(pages_frame)
        self._panel_results.grid(row=0, column=0, sticky="nsew")

        self._pages = {
            "run":      run_pg,
            "settings": self._panel_settings,
            "results":  self._panel_results,
        }

        # 日志区
        self._build_log()

        # 默认显示运行页
        self._switch_page("run")

    # ═══════════════════════════════════════════════════════════════
    #  运行页
    # ═══════════════════════════════════════════════════════════════
    def _build_run(self, pg):
        """构建运行页面"""
        # 顶部状态栏
        top = tk.Frame(pg, bg=C["surface"])
        top.pack(fill=tk.X, padx=SP["md"], pady=(SP["sm"], 0))

        self.lbl_status = tk.Label(
            top, text="就绪", font=FONT["h2"],
            bg=C["surface"], fg=C["primary"],
        )
        self.lbl_status.pack(side=tk.LEFT)

        self.lbl_nodes = tk.Label(
            top, text="", font=FONT["small"],
            bg=C["surface"], fg=C["text_dim"],
        )
        self.lbl_nodes.pack(side=tk.RIGHT)

        # Stepper（紧凑）
        stf = tk.Frame(pg, bg=C["bg"])
        stf.pack(fill=tk.X, padx=SP["md"], pady=(SP["xs"], 0))
        self._stepper = StepperWidget(stf, STAGES, height=70)
        self._stepper.pack(fill=tk.X)

        # 按钮区
        bf = tk.Frame(pg, bg=C["bg"])
        bf.pack(fill=tk.X, padx=SP["md"], pady=SP["xs"])

        # 主按钮行
        r1 = tk.Frame(bf, bg=C["bg"])
        r1.pack(fill=tk.X, pady=(0, SP["xs"]))

        self.btn_all = tk.Button(
            r1, text="▶  一键全部执行", font=FONT["btn"],
            bg=C["primary"], fg="white",
            activebackground=C["primary_hover"],
            relief=tk.FLAT, cursor="hand2", bd=0,
            padx=SP["md"], pady=SP["xs"],
            command=self._run_all,
        )
        self.btn_all.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.btn_stop = tk.Button(
            r1, text="⏹ 停止", font=FONT["small"],
            bg=C["danger"], fg="white",
            activebackground=C["danger"],
            relief=tk.FLAT, cursor="hand2", bd=0,
            padx=SP["sm"], pady=SP["xs"],
            command=self.stop_run,
        )
        self.btn_stop.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        self.btn_preview = tk.Button(
            r1, text="👁 预览", font=FONT["small"],
            bg=C["surface"], fg=C["text"],
            activebackground=C["border"],
            relief=tk.FLAT, cursor="hand2", bd=0,
            highlightthickness=1, highlightbackground=C["border"],
            padx=SP["sm"], pady=SP["xs"],
            command=self.preview,
        )
        self.btn_preview.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        # 分步按钮行
        r2 = tk.Frame(bf, bg=C["bg"])
        r2.pack(fill=tk.X, pady=SP["xs"])
        self._stage_btns = {}
        for key, short, desc, icon in STAGES:
            b = tk.Button(
                r2,
                text=f"{icon} {short}",
                font=FONT["small"],
                bg=C["surface"],
                fg=C["text"],
                activebackground=C["border"],
                relief=tk.FLAT,
                cursor="hand2",
                bd=0,
                highlightthickness=1,
                highlightbackground=C["border"],
                padx=SP["sm"],
                pady=SP["xs"],
                command=lambda k=key: self.run_stage(k),
            )
            b.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=SP["xs"])
            self._stage_btns[key] = b

        # 进度条
        pf = tk.Frame(pg, bg=C["bg"])
        pf.pack(fill=tk.X, padx=SP["lg"], pady=(SP["sm"], 0))

        self.lbl_prog = tk.Label(
            pf, text="就绪", font=FONT["small"],
            bg=C["bg"], fg=C["text_dim"], anchor="w")
        self.lbl_prog.pack(fill=tk.X)

        sty = ttk.Style()
        sty.theme_use("default")
        sty.configure(
            "Blue.Horizontal.TProgressbar",
            troughcolor=C["border"],
            background=C["primary"],
            bordercolor=C["border"],
            lightcolor=C["primary"],
            darkcolor=C["primary_hover"],
        )
        self.prog = ttk.Progressbar(
            pf, mode="determinate",
            style="Blue.Horizontal.TProgressbar",
        )
        self.prog.pack(fill=tk.X, pady=(SP["xs"], 0))

        # 底部弹性空间，把内容顶上去
        spacer = tk.Frame(pg, bg=C["bg"])
        spacer.pack(fill=tk.BOTH, expand=True)

        self._update_node_count()

    # ═══════════════════════════════════════════════════════════════
    #  日志栏
    # ═══════════════════════════════════════════════════════════════
    def _build_log(self):
        content = self._content

        # 日志外框（深色背景，由 grid 权重控制比例）
        log_outer = tk.Frame(content, bg=C["log_bg"])
        log_outer.grid(row=1, column=0, sticky="nsew")
        log_outer.grid_rowconfigure(1, weight=1)
        log_outer.grid_columnconfigure(0, weight=1)
        self._log_outer = log_outer

        # 头部
        lh = tk.Frame(log_outer, bg=C["log_bg"])
        lh.grid(row=0, column=0, sticky="ew")

        tk.Label(lh, text="📋 运行日志", font=FONT["small"],
                 bg=C["log_bg"], fg=C["text_inv_dim"]).pack(side=tk.LEFT)

        btn_group = tk.Frame(lh, bg=C["log_bg"])
        btn_group.pack(side=tk.RIGHT)

        tk.Button(btn_group, text="清空", font=FONT["small"], width=4,
                  bg=C["log_bg"], fg=C["text_inv_dim"],
                  relief=tk.FLAT, cursor="hand2", bd=0,
                  command=self.clear_log).pack(side=tk.RIGHT, padx=(SP["xs"], 0))
        tk.Button(btn_group, text="打开目录", font=FONT["small"],
                  bg=C["log_bg"], fg=C["text_inv_dim"],
                  relief=tk.FLAT, cursor="hand2", bd=0,
                  command=self.open_dir).pack(
            side=tk.RIGHT, padx=(SP["xs"], 0))
        tk.Button(btn_group, text="−", font=FONT["small"], width=3,
                  bg=C["log_bg"], fg=C["text_inv_dim"],
                  relief=tk.FLAT, cursor="hand2", bd=0,
                  command=self._toggle_log).pack(side=tk.RIGHT)

        # 日志正文
        log_body = tk.Frame(log_outer, bg=C["log_bg"])
        log_body.grid(row=1, column=0, sticky="nsew",
                      padx=SP["sm"], pady=(0, SP["sm"]))
        self._log_body = log_body

        mono_font = (_FF, 9) if sys.platform == "win32" else ("Consolas", 9)
        self.log = ScrolledText(
            log_body, font=mono_font,
            state=tk.DISABLED, bg=C["log_bg"], fg=C["log_fg"],
            insertbackground=C["log_fg"],
            relief=tk.FLAT, bd=0, wrap=tk.WORD,
        )
        self.log.pack(fill=tk.BOTH, expand=True)

    def _toggle_log(self):
        if self.log_collapsed:
            self._log_body.grid()
            self.log_collapsed = False
        else:
            self._log_body.grid_remove()
            self.log_collapsed = True

    # ═══════════════════════════════════════════════════════════════
    #  日志 & 状态
    # ═══════════════════════════════════════════════════════════════
    def log_msg(self, msg):
        self.log.config(state=tk.NORMAL)
        ts = time.strftime("%H:%M:%S")
        self.log.insert(tk.END, f"[{ts}] {msg}\n")
        lc = int(self.log.index("end-1c").split(".")[0])
        if lc > LOG_MAX:
            self.log.delete(1.0, f"{lc - LOG_MAX}.0")
        self.log.see(tk.END)
        self.log.config(state=tk.DISABLED)
        try:
            with open(GUI_LOG_FILE, "a", encoding="utf-8") as f:
                f.write(f"[{ts}] {msg}\n")
        except OSError:
            pass

    def clear_log(self):
        self.log.config(state=tk.NORMAL)
        self.log.delete(1.0, tk.END)
        self.log.config(state=tk.DISABLED)

    def open_dir(self):
        try:
            if sys.platform == "win32":
                os.startfile(SCRIPT_DIR)
            elif sys.platform == "darwin":
                subprocess.Popen(["open", SCRIPT_DIR])
            else:
                subprocess.Popen(["xdg-open", SCRIPT_DIR])
        except Exception as e:
            self.log_msg(f"打开目录失败: {e}")

    def set_status(self, text, color=C["text_dim"]):
        self.lbl_status.config(text=text, fg=color)

    def _update_node_count(self):
        nf = os.path.join(SCRIPT_DIR, "nodes_raw.txt")
        try:
            if os.path.exists(nf):
                with open(nf, encoding="utf-8") as f:
                    cnt = sum(1 for _ in f)
                self.lbl_nodes.config(text=f"{cnt} 节点")
        except OSError:
            pass

    def _nav_hover(self, btn, key, entering):
        if key != self._current_page:
            btn.config(
                bg=C["sidebar_hover"] if entering else C["sidebar"],
            )

    def _switch_page(self, name):
        if self.busy:
            return
        for key, btn in self._nav_btns.items():
            is_active = (key == name)
            btn.config(
                bg=C["sidebar_active"] if is_active else C["sidebar"],
                fg="white" if is_active else C["text_inv_dim"],
            )
        pg = self._pages.get(name)
        if pg:
            pg.tkraise()
        self._current_page = name
        if name == "settings":
            self.root.after(80, self._panel_settings.load_config)
        elif name == "results":
            self.root.after(80, self._panel_results.refresh)

    def set_btns_enabled(self, on):
        s = tk.NORMAL if on else tk.DISABLED
        for b in self._stage_btns.values():
            b.config(state=s)
        self.btn_all.config(state=s)
        self.btn_preview.config(state=s)
        # 停止按钮始终保持可用（运行时可以随时取消）
        self.btn_stop.config(state=tk.NORMAL)

    def set_stage_status(self, key, status):
        self.stage_status[key] = status
        btn = self._stage_btns.get(key)
        if not btn:
            return
        solid = {
            "running": C["primary"],
            "done":    C["success"],
            "fail":    C["danger"],
        }
        if status in solid:
            col = solid[status]
            btn.config(bg=col, fg="white", activebackground=col,
                       highlightbackground=col)
        else:
            btn.config(bg=C["surface"], fg=C["text"],
                       activebackground=C["border"],
                       highlightbackground=C["border"])
        self._stepper.set_status(key, status)

    def reset_stage_colors(self):
        for key, _, _, _ in STAGES:
            self.set_stage_status(key, "idle")

    def set_progress(self, idx, name, value):
        self.prog["value"] = value
        self.lbl_prog.config(text=f"{name} · {value:.0f}%")

    # ═══════════════════════════════════════════════════════════════
    #  子进程执行器
    # ═══════════════════════════════════════════════════════════════
    def run_cmd(self, cmd, on_line=None, callback=None):
        q: queue.Queue = queue.Queue()

        def _decode(line_bytes: bytes) -> str:
            """尝试多种编码解码子进程输出"""
            try:
                text = line_bytes.decode("utf-8")
            except UnicodeDecodeError:
                try:
                    text = line_bytes.decode("gbk")
                except UnicodeDecodeError:
                    try:
                        text = line_bytes.decode("gb2312")
                    except UnicodeDecodeError:
                        text = line_bytes.decode("utf-8", errors="replace")
            # 去掉首尾空白和回车符，避免 \r 导致 Text 控件渲染异常
            return text.strip("\r\n")

        def reader():
            try:
                p = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    bufsize=1,
                    **SP_KW,
                )
                self.current_process = p
                last_raw = ""
                for raw_line in p.stdout:
                    line = _decode(raw_line).rstrip("\r\n")
                    # 跳过与上一行完全相同的重复行（_Tee 重定向导致）
                    if line == last_raw:
                        continue
                    last_raw = line
                    q.put(line)
                p.wait()
                q.put(None)
            except Exception as e:
                q.put(f"错误: {e}")
                q.put(None)

        threading.Thread(target=reader, daemon=True).start()

        def poll():
            try:
                # 每批最多处理 50 行，避免阻塞事件循环
                last_line = ""
                for _ in range(50):
                    ln = q.get_nowait()
                    if ln is None:
                        self.current_process = None
                        if callback:
                            callback()
                        return
                    # 跳过与上一行完全相同的重复行（_Tee 重定向导致）
                    if ln == last_line:
                        continue
                    last_line = ln
                    self.log_msg(ln)
                    if on_line and not any(kw in ln for kw in SKIP_LINES):
                        on_line(ln)
            except queue.Empty:
                pass
            # 强制刷新界面
            try:
                self.root.update_idletasks()
            except Exception:
                pass
            self.root.after(30, poll)

        poll()

    def stop_run(self):
        self._stopped = True
        if self.current_process and self.current_process.poll() is None:
            self.current_process.terminate()
            try:
                self.current_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.current_process.kill()
            self.log_msg("⏹ 用户取消了当前操作")
            self.set_status("已停止", C["warning"])
            self.current_process = None
            self.busy = False
            self.set_btns_enabled(True)
        else:
            self.log_msg("没有正在运行的操作")

    def _tick(self, line):
        clean = line.strip("\r").strip()

        # 模式1: [获取] X/Y
        m = re.match(r"^\[获取\]\s+(\d+)/(\d+)", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = cur / tot * 100 if tot > 0 else 0
                self.prog["value"] = pct
                self.lbl_prog.config(
                    text=f"获取IP · {cur}/{tot} · {pct:.0f}%")
            except (ValueError, IndexError):
                pass
            self.log_msg(clean)
            return

        # 模式2: [DC] 进度: X/Y (Z%) 或 [DC] : X/Y (Z%) 或 [DC] X/Y (Z%)
        m = re.search(r"\[(\w+)\]\s*[：:]?\s*(?:进度[：:]\s*)?(\d+)/(\d+)\s*\(([\d.]+)%\)", clean)
        if m:
            try:
                dc = m.group(1)
                cur, tot = int(m.group(2)), int(m.group(3))
                pct = float(m.group(4))
                self.prog["value"] = pct
                self.lbl_prog.config(
                    text=f"扫描 {dc} · {cur}/{tot} · {pct:.0f}%")
            except (ValueError, IndexError):
                pass
            self.log_msg(clean)
            return

        # 模式3: [X/Y Z%]
        m = re.search(r"\[(\d+)/(\d+)\s+([\d.]+)%\]", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = float(m.group(3))
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"扫描中 · {cur}/{tot} · {pct:.0f}%")
            except (ValueError, IndexError):
                pass
            self.log_msg(clean)
            return

        # 模式3b: [X/Y] 描述（不带百分比，cfdata.exe 输出）
        m = re.search(r"\[(\d+)/(\d+)\]\s*([^\d%])", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = cur / tot * 100 if tot > 0 else 0
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"扫描中 · {cur}/{tot} · {pct:.0f}%")
            except (ValueError, IndexError):
                pass
            self.log_msg(clean)
            return

        # 模式4: (X%)
        if re.search(r"\((\d+(?:\.\d+)?)%\)", clean):
            try:
                pct = float(re.search(r"\((\d+(?:\.\d+)?)%\)", clean).group(1))
                self.prog["value"] = pct
                cur = self.lbl_prog.cget("text")
                if "·" in cur:
                    base = cur.rsplit("·", 1)[0].rstrip()
                    self.lbl_prog.config(text=f"{base} · {pct:.0f}%")
            except (ValueError, IndexError):
                pass

        self.log_msg(clean)

    # ═══════════════════════════════════════════════════════════════
    #  依赖检查
    # ═══════════════════════════════════════════════════════════════
    def _check_dependencies(self):
        """检查必要的 Python 包是否已安装"""
        required = {
            "pydantic": "pydantic",
            "pydantic_settings": "pydantic-settings",
            "requests": "requests",
        }
        missing = []
        for mod, pkg in required.items():
            try:
                __import__(mod)
            except ImportError:
                missing.append(pkg)

        if missing:
            msg = "缺少必要的依赖包：\n\n"
            msg += "\n".join(f"  • {pkg}" for pkg in missing)
            msg += "\n\n请运行以下命令安装：\n\n"
            msg += f"  pip install {' '.join(missing)}"
            messagebox.showerror("依赖缺失", msg)

    # ═══════════════════════════════════════════════════════════════
    #  代理管理
    # ═══════════════════════════════════════════════════════════════
    def _off_proxy(self):
        saved = {}
        for v in ["http_proxy", "https_proxy", "HTTP_PROXY",
                  "HTTPS_PROXY", "ALL_PROXY", "all_proxy"]:
            saved[v] = os.environ.pop(v, None)
        os.environ["NO_PROXY"] = "*"
        return saved

    def _on_proxy(self, saved):
        for v, val in saved.items():
            if val is not None:
                os.environ[v] = val
            elif v in os.environ:
                del os.environ[v]
        os.environ.pop("NO_PROXY", None)

    # ═══════════════════════════════════════════════════════════════
    #  阶段完成回调
    # ═══════════════════════════════════════════════════════════════
    def _make_done(self, stage_key, idx, name, color, msg,
                   nxt=None, saved_proxy=None):
        def done():
            if saved_proxy is not None:
                self._on_proxy(saved_proxy)
            self._update_node_count()
            self.set_stage_status(stage_key, "done")
            self.set_progress(idx, name, 100)
            self.set_status(f"✓ {msg}", color)
            if self._stopped:
                # 用户主动停止，不继续下一阶段
                self.busy = False
                self.set_btns_enabled(True)
                self.set_status("已停止", C["warning"])
                return
            if nxt is not None:
                self.root.after(300, nxt)
            else:
                self.busy = False
                self.set_btns_enabled(True)
        return done

    # ═══════════════════════════════════════════════════════════════
    #  各阶段执行
    # ═══════════════════════════════════════════════════════════════
    def do_cfdata(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("cfdata", "running")
        self.set_progress(1, "更新CFData", 0)
        self.set_status("正在扫描 Cloudflare 网段...", C["primary"])
        self.log_msg("=" * 50)
        self.log_msg("阶段1：更新 CFData")
        self.log_msg("=" * 50)
        done = self._make_done(
            "cfdata", 1, "更新CFData", C["success"],
            "CFData 更新完成", nxt)
        self.run_cmd(
            [PYTHON, "-u", os.path.join(SCRIPT_DIR, "update_cfdata.py")],
            on_line=self._tick, callback=done)

    def do_fetch(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("fetch", "running")
        self.set_progress(2, "获取IP列表", 0)
        self.set_status("正在获取 IP 列表...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段2：获取 IP 列表")
        self.log_msg("=" * 50)
        done = self._make_done(
            "fetch", 2, "获取IP列表", C["success"], "获取完成", nxt)
        self.run_cmd(
            [PYTHON, "-u", os.path.join(SCRIPT_DIR, "main.py"), "--fetch-only"],
            on_line=self._tick, callback=done)

    def do_avail(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("avail", "running")
        self.set_progress(3, "TCP+可用性检测", 0)
        self.set_status("正在 TCP + 可用性检测（直连）...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段3：TCP + 可用性检测（直连）")
        self.log_msg("=" * 50)
        saved = self._off_proxy()
        self.log_msg("已禁用代理，直连检测。")
        done = self._make_done(
            "avail", 3, "TCP+可用性检测", C["success"],
            "TCP+可用性检测完成", nxt, saved_proxy=saved)
        self.run_cmd(
            [PYTHON, "-u", os.path.join(SCRIPT_DIR, "main.py"),
             "--skip-fetch", "--skip-bandwidth"],
            on_line=self._tick, callback=done)

    def do_bw(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("bw", "running")
        self.set_progress(4, "带宽测速", 0)
        self.set_status("正在带宽测速（直连）...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段4：带宽测速（直连）")
        self.log_msg("=" * 50)
        saved = self._off_proxy()
        self.log_msg("已禁用代理，直连测速。")
        done = self._make_done(
            "bw", 4, "带宽测速", C["success"],
            "带宽测速完成", nxt, saved_proxy=saved)
        self.run_cmd(
            [PYTHON, "-u", os.path.join(SCRIPT_DIR, "main.py"),
             "--skip-fetch", "--skip-tcp", "--skip-availability"],
            on_line=self._tick, callback=done)

    def do_push(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("push", "running")
        self.set_progress(5, "推送GitHub", 0)
        self.set_status("正在推送到 GitHub...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段5：推送到 GitHub")
        self.log_msg("=" * 50)
        if not os.path.exists(IP_FILE):
            self.log_msg("错误: ip.txt 不存在")
            self.set_stage_status("push", "fail")
            self.set_status("推送失败: ip.txt 不存在", C["danger"])
            self.busy = False
            self.set_btns_enabled(True)
            if nxt:
                nxt()
            return
        ps1 = os.path.join(SCRIPT_DIR, "scripts", "git_sync.ps1")
        if not os.path.exists(ps1):
            self.log_msg(f"错误: 未找到 {ps1}")
            self.set_stage_status("push", "fail")
            self.set_status("推送失败: 缺少 git_sync.ps1", C["danger"])
            self.busy = False
            self.set_btns_enabled(True)
            if nxt:
                nxt()
            return
        done = self._make_done(
            "push", 5, "推送GitHub", C["success"], "推送完成", nxt)
        self.run_cmd(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", ps1],
            callback=done)

    # ═══════════════════════════════════════════════════════════════
    #  预览
    # ═══════════════════════════════════════════════════════════════
    def preview(self):
        if not os.path.exists(IP_FILE):
            self.log_msg("错误: ip.txt 不存在，请先运行测速")
            return
        self.log_msg("=" * 50)
        self.log_msg("预览 ip.txt（前 50 行）")
        self.log_msg("=" * 50)
        try:
            with open(IP_FILE, encoding="utf-8") as f:
                lines = f.readlines()
        except OSError as e:
            self.log_msg(f"读取失败: {e}")
            return
        for line in lines[:50]:
            self.log_msg(line.rstrip())
        if len(lines) > 50:
            self.log_msg(f"... 共 {len(lines)} 行")
        self.log_msg("")

    # ═══════════════════════════════════════════════════════════════
    #  运行入口
    # ═══════════════════════════════════════════════════════════════
    def run_stage(self, stage):
        if self.busy:
            return
        self._stopped = False
        self.root.after(100, self._exec_stage, stage)

    def _exec_stage(self, stage):
        self.reset_stage_colors()
        if stage == "cfdata":
            self.do_cfdata()
        elif stage == "fetch":
            self.do_fetch()
        elif stage == "avail":
            self.do_avail()
        elif stage == "bw":
            self.do_bw()
        elif stage == "push":
            self.do_push()

    def _run_all(self):
        self._stopped = False
        self.reset_stage_colors()

        def s5():
            if self._stopped:
                return
            self.do_push(nxt=self._all_done)

        def s4():
            if self._stopped:
                return
            self.do_bw(nxt=s5)

        def s3():
            if self._stopped:
                return
            self.do_avail(nxt=s4)

        def s2():
            if self._stopped:
                return
            self.do_fetch(nxt=s3)

        self.do_cfdata(nxt=s2)

    def _all_done(self):
        self.busy = False
        self.set_btns_enabled(True)
        self.set_status("全部完成!", C["primary"])
        self.log_msg("=" * 50)
        self.log_msg("全部阶段执行完成")
        self.log_msg("=" * 50)

    def _settings_saved(self):
        self.log_msg("⚙ 设置已保存")


# ═══════════════════════════════════════════════════════════════════
#  入口
# ═══════════════════════════════════════════════════════════════════
def main():
    root = tk.Tk()
    app = CFGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
