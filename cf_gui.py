#!/usr/bin/env python3
"""CF优选工具 - 图形界面（模块化重构版）
"""

from __future__ import annotations

import sys
import os
import queue
import re
import subprocess
import threading
import time

import tkinter as tk
from tkinter import ttk, messagebox
from tkinter.scrolledtext import ScrolledText

# Path configuration injection
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, "src"))

from cfnb.gui.constants import (
    C, SP, FONT, STAGES, CONFIG_FILE, IP_FILE, GUI_LOG_FILE
)
from cfnb.gui.styles import apply_theme, NavButton, make_button
from cfnb.gui.widgets.stepper import StepperWidget
from cfnb.gui.widgets.settings import SettingsPanel
from cfnb.gui.widgets.results import ResultsPanel
from cfnb.gui.widgets.dashboard import DashboardPanel

PYTHON = sys.executable

SP_KW = {}
if sys.platform == "win32":
    _si = subprocess.STARTUPINFO()
    _si.dwFlags = subprocess.STARTF_USESHOWWINDOW
    _si.wShowWindow = 0
    SP_KW = {"startupinfo": _si, "creationflags": 0x08000000}

SKIP_LINES = [
    "当前模式", "最低成功率", "IP 可用性", "IPv6 客户端",
    "DNS黑名单", "IP 风险等级", "带宽测速候选数",
    "前置白名单", "日志已启用", "等待", "已尝试", "批量查询中",
]

LOG_MAX = 2000

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

        # 运用 Windows 11 DWM 标题栏深色主题与圆角属性
        self._apply_windows_theme()

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
        self._nav_btns = {}
        nav_items = [
            ("run",      "▶",  "运行",  "一键执行完整流程"),
            ("subs",     "🔗", "订阅器", "管理订阅来源"),
            ("settings", "⚙",  "设置",  "配置参数"),
            ("results",  "📊", "结果",  "查看优选结果"),
        ]
        for key, icon, label, _tooltip in nav_items:
            btn_frame = tk.Frame(sb, bg=C["sidebar"])
            btn_frame.pack(fill=tk.X, padx=SP["sm"], pady=SP["xs"])

            b = NavButton(
                btn_frame,
                text=f"  {icon}  {label}",
                command=lambda k=key: self._switch_page(k),
            )
            b.pack(fill=tk.X)
            self._nav_btns[key] = b

        # 底部版本信息
        vf = tk.Frame(sb, bg=C["sidebar"])
        vf.pack(side=tk.BOTTOM, fill=tk.X, padx=SP["lg"], pady=SP["md"])
        tk.Label(vf, text="v2.0.0", font=FONT["small"],
                 bg=C["sidebar"], fg=C["text_inv_dim"]).pack()

        # ── 内容区（grid: col0=主页面, col1=右侧日志） ──
        content = tk.Frame(root, bg=C["bg"])
        content.grid(row=0, column=1, sticky="nsew")
        content.grid_rowconfigure(0, weight=1)
        content.grid_columnconfigure(0, weight=3) # 主页面占 75%
        content.grid_columnconfigure(1, weight=1) # 日志栏占 25%
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

        from cfnb.gui.widgets.sub_manager import SubscriptionManagerPanel
        self._panel_subs = SubscriptionManagerPanel(
            pages_frame, on_changed=lambda: None)
        self._panel_subs.grid(row=0, column=0, sticky="nsew")

        self._pages = {
            "run":      run_pg,
            "subs":     self._panel_subs,
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

        # Log visibility toggle button
        self.btn_toggle_log = tk.Button(
            top, text="📋 日志", font=FONT["small"],
            bg=C["surface"], fg=C["primary"], # active by default (glowing blue)
            activebackground=C["border"],
            relief=tk.FLAT, cursor="hand2", bd=0,
            highlightthickness=1, highlightbackground=C["border"],
            padx=SP["sm"], pady=1,
            command=self._toggle_log
        )
        self.btn_toggle_log.pack(side=tk.RIGHT, padx=(0, SP["sm"]))

        stf = tk.Frame(pg, bg=C["bg"])
        stf.pack(fill=tk.X, padx=SP["md"], pady=(SP["xs"], 0))
        self._stepper = StepperWidget(stf, STAGES, height=70)
        self._stepper.pack(fill=tk.X)

        bf = tk.Frame(pg, bg=C["bg"])
        bf.pack(fill=tk.X, padx=SP["md"], pady=SP["xs"])

        r1 = tk.Frame(bf, bg=C["bg"])
        r1.pack(fill=tk.X, pady=(0, SP["xs"]))

        self.btn_all = make_button(
            r1, "▶  一键全部执行", self._run_all, variant="primary",
            font_key="btn", padx=SP["md"], pady=SP["xs"])
        self.btn_all.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.btn_stop = make_button(r1, "⏹ 停止", self.stop_run, variant="danger",
                                    padx=SP["sm"], pady=SP["xs"])
        self.btn_stop.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        self.btn_preview = make_button(r1, "👁 预览", self.preview, variant="ghost",
                                       padx=SP["sm"], pady=SP["xs"])
        self.btn_preview.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        self.btn_sub = make_button(r1, "🔗 订阅IP", self.run_subscription, variant="accent",
                                   padx=SP["sm"], pady=SP["xs"])
        self.btn_sub.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        self.btn_latency = make_button(r1, "⚡ 延迟优选", self.run_latency, variant="accent",
                                       padx=SP["sm"], pady=SP["xs"])
        self.btn_latency.pack(side=tk.LEFT, padx=(SP["xs"], 0))

        r2 = tk.Frame(bf, bg=C["bg"])
        r2.pack(fill=tk.X, pady=SP["xs"])
        self._stage_btns = {}
        for key, short, desc, icon in STAGES:
            b = make_button(
                r2, f"{icon} {short}", lambda k=key: self.run_stage(k),
                variant="ghost", padx=SP["sm"], pady=SP["xs"])
            b.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=SP["xs"])
            self._stage_btns[key] = b

        pf = tk.Frame(pg, bg=C["bg"])
        pf.pack(fill=tk.X, padx=SP["lg"], pady=(SP["sm"], 0))

        self.lbl_prog = tk.Label(
            pf, text="就绪", font=FONT["small"],
            bg=C["bg"], fg=C["text_dim"], anchor="w")
        self.lbl_prog.pack(fill=tk.X)

        sty = ttk.Style()
        # 注意：不要在这里切换 theme_use，否则会丢弃 apply_theme 的统一配置
        # （改用 clam 主题下的统一进度条样式）
        sty.configure(
            "Run.Horizontal.TProgressbar",
            troughcolor=C["border"],
            background=C["primary"],
            bordercolor=C["border"],
            lightcolor=C["primary"],
            darkcolor=C["primary_hover"],
        )
        self.prog = ttk.Progressbar(
            pf, mode="determinate",
            style="Run.Horizontal.TProgressbar",
        )
        self.prog.pack(fill=tk.X, pady=(SP["xs"], 0))

        self._dashboard = DashboardPanel(pg)
        self._dashboard.pack(fill=tk.BOTH, expand=True, pady=(SP["sm"], 0))

        # 定时执行控制条
        sched = tk.Frame(pg, bg=C["surface"],
                         highlightthickness=1, highlightbackground=C["border"],
                         padx=SP["lg"], pady=SP["sm"])
        sched.pack(fill=tk.X, padx=SP["md"], pady=(SP["xs"], SP["sm"]))

        self._sched_on = tk.BooleanVar(value=False)
        self._sched_cb = tk.Checkbutton(
            sched, text="⏰ 自动调度", variable=self._sched_on,
            bg=C["surface"], fg=C["text"], selectcolor=C["surface"],
            activebackground=C["surface"], font=FONT["normal"], cursor="hand2",
            command=self._on_sched_toggle,
        )
        self._sched_cb.pack(side=tk.LEFT)

        tk.Label(sched, text="间隔(小时):", font=FONT["small"],
                 bg=C["surface"], fg=C["text_dim"]).pack(side=tk.LEFT, padx=(SP["sm"], 0))
        self._sched_hours = tk.StringVar(value="6.0")
        tk.Spinbox(sched, from_=0.5, to=720, increment=0.5,
                   textvariable=self._sched_hours, width=8,
                   font=FONT["small"]).pack(side=tk.LEFT, padx=(SP["xs"], 0))

        self.lbl_sched = tk.Label(sched, text="未启用", font=FONT["small"],
                                  bg=C["surface"], fg=C["text_dim"])
        self.lbl_sched.pack(side=tk.LEFT, padx=(SP["md"], 0))

        self._sched_timer = None
        self._load_sched_config()

        self._update_node_count()

    # ═══════════════════════════════════════════════════════════════
    #  日志区
    # ═══════════════════════════════════════════════════════════════
    def _build_log(self):
        content = self._content

        log_outer = tk.Frame(content, bg=C["log_bg"])
        log_outer.grid(row=0, column=1, sticky="nsew")
        log_outer.grid_rowconfigure(1, weight=1)
        log_outer.grid_columnconfigure(0, weight=1)
        self._log_outer = log_outer

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

        log_body = tk.Frame(log_outer, bg=C["log_bg"])
        log_body.grid(row=1, column=0, sticky="nsew",
                      padx=SP["sm"], pady=(0, SP["sm"]))
        self._log_body = log_body

        mono_font = FONT["mono"]
        self.log = ScrolledText(
            log_body, font=mono_font,
            state=tk.DISABLED, bg=C["log_bg"], fg=C["log_fg"],
            insertbackground=C["log_fg"],
            relief=tk.FLAT, bd=0, wrap=tk.WORD,
            width=32
        )
        self.log.pack(fill=tk.BOTH, expand=True)

    def _toggle_log(self):
        if self.log_collapsed:
            self._log_outer.grid(row=0, column=1, sticky="nsew")
            self.btn_toggle_log.config(fg=C["primary"])
            self.log_collapsed = False
        else:
            self._log_outer.grid_remove()
            self.btn_toggle_log.config(fg=C["text_dim"])
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

    def log_msg_batch(self, lines):
        self.log.config(state=tk.NORMAL)
        ts = time.strftime("%H:%M:%S")
        text_to_insert = "".join(f"[{ts}] {line}\n" for line in lines)
        self.log.insert(tk.END, text_to_insert)
        lc = int(self.log.index("end-1c").split(".")[0])
        if lc > LOG_MAX:
            self.log.delete(1.0, f"{lc - LOG_MAX}.0")
        self.log.see(tk.END)
        self.log.config(state=tk.DISABLED)

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

    def _switch_page(self, name):
        if self.busy:
            return
        for key, btn in self._nav_btns.items():
            btn.set_active(key == name)
        pg = self._pages.get(name)
        if pg:
            pg.tkraise()
        self._current_page = name
        if name == "settings":
            self.root.after(80, self._panel_settings.load_config)
        elif name == "results":
            self.root.after(80, self._panel_results.refresh)
        elif name == "subs":
            self.root.after(80, self._panel_subs.refresh)

    def set_btns_enabled(self, on):
        s = tk.NORMAL if on else tk.DISABLED
        for b in self._stage_btns.values():
            b.config(state=s)
        self.btn_all.config(state=s)
        self.btn_preview.config(state=s)
        self.btn_stop.config(state=tk.NORMAL)

    def _stage_index(self, key: str) -> int:
        """把阶段 key 映射到进度条序号（与 STAGES 顺序一致，1 基）。"""
        for i, (k, *_rest) in enumerate(STAGES, start=1):
            if k == key:
                return i
        return 1

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
        self._dashboard.reset()

    def set_progress(self, idx, name, value):
        self.prog["value"] = value
        self.lbl_prog.config(text=f"{name} · {value:.0f}%")

    # ═══════════════════════════════════════════════════════════════
    #  子进程执行器
    # ═══════════════════════════════════════════════════════════════
    def run_cmd(self, cmd, on_line=None, callback=None):
        q = queue.Queue()

        def _decode(line_bytes: bytes) -> str:
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
            return text.strip("\r\n")

        def reader():
            try:
                new_env = os.environ.copy()
                src_path = os.path.join(SCRIPT_DIR, "src")
                if "PYTHONPATH" in new_env:
                    new_env["PYTHONPATH"] = src_path + os.pathsep + new_env["PYTHONPATH"]
                else:
                    new_env["PYTHONPATH"] = src_path

                p = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    bufsize=1,
                    env=new_env,
                    **SP_KW,
                )
                self.current_process = p
                _seen = set()
                _max_seen = 500
                for raw_line in p.stdout:
                    line = _decode(raw_line).rstrip("\r\n")
                    if not line:
                        continue
                    if line in _seen:
                        continue
                    if len(_seen) < _max_seen:
                        _seen.add(line)
                    q.put(line)
                    try:
                        ts = time.strftime("%H:%M:%S")
                        with open(GUI_LOG_FILE, "a", encoding="utf-8") as f:
                            f.write(f"[{ts}] {line}\n")
                    except OSError:
                        pass
                p.wait()
                q.put(None)
            except Exception as e:
                q.put(f"错误: {e}")
                q.put(None)

        threading.Thread(target=reader, daemon=True).start()

        def poll():
            try:
                lines_to_log = []
                last_line = ""
                for _ in range(100):
                    try:
                        ln = q.get_nowait()
                        if ln is None:
                            if lines_to_log:
                                self.log_msg_batch(lines_to_log)
                            self.current_process = None
                            if callback:
                                callback()
                            return
                        if ln == last_line:
                            continue
                        last_line = ln
                        lines_to_log.append(ln)
                        if on_line and not any(kw in ln for kw in SKIP_LINES):
                            on_line(ln)
                    except queue.Empty:
                        break
                    except Exception as e:
                        try:
                            self.log_msg(f"GUI 解析日志行出错: {e}")
                        except Exception:
                            pass
                if lines_to_log:
                    self.log_msg_batch(lines_to_log)
            except Exception as e:
                try:
                    self.log_msg(f"GUI Poll 发生严重错误: {e}")
                except Exception:
                    pass
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

    # ═══════════════════════════════════════════════════════════════
    #  自动调度
    # ═══════════════════════════════════════════════════════════════
    def _load_sched_config(self):
        try:
            from cfnb.config import get_config
            cfg = get_config()
            self._sched_on.set(bool(getattr(cfg, "AUTO_SCHEDULE_ENABLED", False)))
            self._sched_hours.set(str(getattr(cfg, "AUTO_SCHEDULE_INTERVAL_HOURS", 6.0)))
        except Exception:
            pass
        self._update_sched_label()

    def _update_sched_label(self):
        if self._sched_on.get():
            self.lbl_sched.config(
                text=f"已启用 · 每 {self._sched_hours.get()}h 自动执行", fg=C["primary"])
        else:
            self.lbl_sched.config(text="未启用", fg=C["text_dim"])

    def _on_sched_toggle(self):
        on = self._sched_on.get()
        self._save_sched_config()
        self._update_sched_label()
        if on:
            self._start_sched_timer()
        else:
            self._stop_sched_timer()

    def _save_sched_config(self):
        import json
        from cfnb.gui.constants import CONFIG_FILE
        from cfnb.config import reload_config
        try:
            raw = json.loads(open(CONFIG_FILE, encoding="utf-8").read())
            clean = {k: v for k, v in raw.items() if not str(k).startswith("_comment")}
            clean["AUTO_SCHEDULE_ENABLED"] = self._sched_on.get()
            try:
                clean["AUTO_SCHEDULE_INTERVAL_HOURS"] = float(self._sched_hours.get())
            except ValueError:
                clean["AUTO_SCHEDULE_INTERVAL_HOURS"] = 6.0
            out = {k: v for k, v in raw.items() if str(k).startswith("_comment")}
            out.update(clean)
            json.dump(out, open(CONFIG_FILE, "w", encoding="utf-8"),
                      indent=4, ensure_ascii=False)
            reload_config()
        except Exception as e:
            self.log_msg(f"保存调度配置失败: {e}")

    def _start_sched_timer(self):
        self._stop_sched_timer()
        try:
            hours = float(self._sched_hours.get())
        except ValueError:
            hours = 6.0
        ms = max(30 * 60 * 1000, int(hours * 3600 * 1000))
        self.log_msg(f"⏰ 自动调度已启动（间隔 {hours}h）")
        self._sched_timer = self.root.after(ms, self._schedule_fire)

    def _stop_sched_timer(self):
        if self._sched_timer is not None:
            self.root.after_cancel(self._sched_timer)
            self._sched_timer = None

    def _schedule_fire(self):
        self._sched_timer = None
        if not self._sched_on.get():
            return
        self.log_msg("⏰ 定时触发：开始自动执行")
        # 复用一键全部执行流程（非阻塞子进程）
        self._run_all()
        # 重新排期
        if self._sched_on.get():
            self._start_sched_timer()

    def _tick(self, line):
        clean = line.strip("\r").strip()

        # 0. 结构化进度协议 [PROGRESS] {...}（与文本日志互不干扰）
        if clean.startswith("[PROGRESS]"):
            try:
                import json
                payload = json.loads(clean[len("[PROGRESS]"):].strip())
                ptype = payload.get("type")
                if ptype == "speed" and "value" in payload:
                    self._dashboard.add_speed(float(payload["value"]))
                elif ptype == "tcp" and "value" in payload:
                    self._dashboard.add_latency(float(payload["value"]))
                elif ptype == "stage" and "key" in payload:
                    self.set_stage_status(payload["key"], payload.get("status", "idle"))
                    if payload.get("progress") is not None:
                        self.set_progress(
                            self._stage_index(payload["key"]),
                            payload.get("name", payload["key"]),
                            payload["progress"],
                        )
            except Exception:
                pass
            return

        # 1. 拦截机器读取前缀
        if clean.startswith("[SPEED_POINT]"):
            try:
                parts = clean.split("|")
                speed = float(parts[1].strip())
                self._dashboard.add_speed(speed)
            except Exception:
                pass
            return

        if clean.startswith("[TCP_POINT]"):
            try:
                parts = clean.split("|")
                lat = float(parts[1].strip())
                self._dashboard.add_latency(lat)
            except Exception:
                pass
            return

        # 2. 匹配具体进度的格式
        # A. 带宽测速各阶段进度
        m = re.search(r"\[(快筛|探速|精测)\]\s+进度：(\d+)/(\d+)\s*\(([\d.]+)%\)\s+已测出速度：(\d+)", clean)
        if m:
            try:
                tag = m.group(1)
                cur, tot = int(m.group(2)), int(m.group(3))
                pct = float(m.group(4))
                passed = int(m.group(5))
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"带宽测速({tag}) · {cur}/{tot} · {pct:.0f}%")
                self._dashboard.update_nodes(cur, tot, passed)
            except Exception:
                pass
            return

        # B. 可用性检测进度
        m = re.search(r"\[可用性检测\]\s+进度：(\d+)/(\d+)\s*\(([\d.]+)%\)\s+通过数量：(\d+)", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = float(m.group(3))
                passed = int(m.group(4))
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"可用性检测 · {cur}/{tot} · {pct:.0f}%")
                self._dashboard.update_nodes(cur, tot, passed)
            except Exception:
                pass
            return

        # C. 异步 TCP 测试进度
        m = re.match(r"^进度：(\d+)/(\d+)\s*\(([\d.]+)%\)", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = float(m.group(3))
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"TCP测试 · {cur}/{tot} · {pct:.0f}%")
                self._dashboard.update_nodes(cur, tot, len(self._dashboard.latencies))
            except Exception:
                pass
            return

        # D. 数据源拉取进度
        m = re.match(r"^\[获取\]\s+(\d+)/(\d+)", clean)
        if m:
            try:
                cur, tot = int(m.group(1)), int(m.group(2))
                pct = cur / tot * 100 if tot > 0 else 0
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"获取IP · {cur}/{tot} · {pct:.0f}%")
                self._dashboard.update_nodes(cur, tot, 0)
            except Exception:
                pass
            return

        # E. 扫描数据中心进度
        m = re.search(r"\[(\w+)\]\s*[：:]?\s*(?:进度[：:]\s*)?(\d+)/(\d+)\s*\(([\d.]+)%\)", clean)
        if m:
            try:
                dc = m.group(1)
                cur, tot = int(m.group(2)), int(m.group(3))
                pct = float(m.group(4))
                self.prog["value"] = pct
                self.lbl_prog.config(text=f"扫描 {dc} · {cur}/{tot} · {pct:.0f}%")
                self._dashboard.update_nodes(cur, tot, 0)
            except Exception:
                pass
            return

        # F. 兜底百分比匹配
        m = re.search(r"\((\d+(?:\.\d+)?)%\)", clean)
        if m:
            try:
                pct = float(m.group(1))
                self.prog["value"] = pct
                cur = self.lbl_prog.cget("text")
                if "·" in cur:
                    base = cur.rsplit("·", 1)[0].rstrip()
                    self.lbl_prog.config(text=f"{base} · {pct:.0f}%")
            except Exception:
                pass
            return

    def _tick_time(self):
        if self.busy:
            self._dashboard.update_time()
            self.root.after(1000, self._tick_time)
        else:
            self._time_timer_running = False

    def start_time_timer(self):
        if not getattr(self, "_time_timer_running", False):
            self._time_timer_running = True
            self.root.after(1000, self._tick_time)

    # ═══════════════════════════════════════════════════════════════
    #  依赖检查
    # ═══════════════════════════════════════════════════════════════
    def _check_dependencies(self):
        required = {
            "pydantic": "pydantic",
            "pydantic_settings": "pydantic-settings",
            "httpx": "httpx",
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

    def _apply_windows_theme(self):
        if sys.platform != "win32":
            return
        try:
            import ctypes
            self.root.update()
            hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
            if not hwnd:
                hwnd = self.root.winfo_id()

            # 1. Light Mode Titlebar (DWMWA_USE_IMMERSIVE_DARK_MODE = 20 & 19, set to 0)
            rendering_policy = ctypes.c_int(0)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, 20, ctypes.byref(rendering_policy), ctypes.sizeof(rendering_policy)
            )
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, 19, ctypes.byref(rendering_policy), ctypes.sizeof(rendering_policy)
            )

            # 2. Windows 11 Rounded Corners (DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2)
            corner_preference = ctypes.c_int(2)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, 33, ctypes.byref(corner_preference), ctypes.sizeof(corner_preference)
            )
        except Exception as e:
            self.log_msg(f"应用 Windows 11 DWM 标题栏深色主题与圆角属性失败: {e}")

    # ═══════════════════════════════════════════════════════════════
    #  代理管理
    # ═══════════════════════════════════════════════════════════════
    def _off_proxy(self):
        from cfnb.util.proxy import disable_proxy
        return disable_proxy()

    def _on_proxy(self, saved):
        from cfnb.util.proxy import restore_proxy
        restore_proxy(saved)

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
        self._dashboard.update_stage("更新 CFData")
        self.start_time_timer()
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
        self._dashboard.update_stage("获取 IP 列表")
        self.start_time_timer()
        self.set_status("正在获取 IP 列表...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段2：获取 IP 列表")
        self.log_msg("=" * 50)
        done = self._make_done(
            "fetch", 2, "获取IP列表", C["success"], "获取完成", nxt)
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--fetch-only"],
            on_line=self._tick, callback=done)

    def do_tcp(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("tcp", "running")
        self.set_progress(3, "TCP检测", 0)
        self._dashboard.update_stage("TCP 检测")
        self.start_time_timer()
        self.set_status("正在进行 TCP 检测（直连）...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段3：TCP 检测（直连）")
        self.log_msg("=" * 50)
        saved = self._off_proxy()
        self.log_msg("已禁用代理，直连检测。")
        done = self._make_done(
            "tcp", 3, "TCP检测", C["success"],
            "TCP 检测完成", nxt, saved_proxy=saved)
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--skip-fetch", "--tcp-only"],
            on_line=self._tick, callback=done)

    def do_avail(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("avail", "running")
        self.set_progress(4, "可用检测", 0)
        self._dashboard.update_stage("安全可用性检测")
        self.start_time_timer()
        self.set_status("正在进行安全可用性检测（直连）...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段4：安全可用性检测（直连）")
        self.log_msg("=" * 50)
        saved = self._off_proxy()
        self.log_msg("已禁用代理，直连检测。")
        done = self._make_done(
            "avail", 4, "可用检测", C["success"],
            "可用性检测完成", nxt, saved_proxy=saved)
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--skip-fetch", "--skip-tcp", "--skip-bandwidth", "--skip-dns", "--skip-push"],
            on_line=self._tick, callback=done)

    def do_bw(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("bw", "running")
        self.set_progress(5, "带宽测速", 0)
        self._dashboard.update_stage("带宽测速")
        self.start_time_timer()
        self.set_status("正在带宽测速（直连）...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段5：带宽测速（直连）")
        self.log_msg("=" * 50)
        saved = self._off_proxy()
        self.log_msg("已禁用代理，直连测速。")
        done = self._make_done(
            "bw", 5, "带宽测速", C["success"],
            "带宽测速完成", nxt, saved_proxy=saved)
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--skip-fetch", "--skip-tcp", "--skip-availability", "--skip-push"],
            on_line=self._tick, callback=done)

    def do_push(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.set_stage_status("push", "running")
        self.set_progress(6, "推送GitHub", 0)
        self._dashboard.update_stage("推送到 GitHub")
        self.start_time_timer()
        self.set_status("正在推送到 GitHub...", C["primary"])
        self.log_msg("\n" + "=" * 50)
        self.log_msg("阶段6：推送到 GitHub")
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
        done = self._make_done(
            "push", 6, "推送GitHub", C["success"], "推送完成", nxt)
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--push-only"],
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
    #  订阅转换（获取别人订阅器里的 IP → addressesapi.txt → 推送）
    # ═══════════════════════════════════════════════════════════════
    def run_subscription(self):
        if self.busy:
            return
        self._stopped = False
        self.root.after(100, self._exec_subscription)

    def _exec_subscription(self):
        self.reset_stage_colors()
        self.do_sub()

    def do_sub(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.start_time_timer()
        self.set_status("正在获取订阅节点 IP...", C["primary"])
        self._dashboard.update_stage("订阅转换")
        self.log_msg("\n" + "=" * 50)
        self.log_msg("订阅转换：拉取订阅 → 提取 IP → 写入 addressesapi.txt（本地，不推送）")
        self.log_msg("=" * 50)

        def done():
            self._update_node_count()
            self.set_status("✓ 订阅转换完成（未推送，可用「延迟优选」筛选并推送）", C["success"])
            self.busy = False
            self.set_btns_enabled(True)
            if nxt is not None:
                self.root.after(300, nxt)

        # --sub-only 会拉取订阅（跟随系统代理）、写入独立文件，不再推送
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--sub-only"],
            on_line=self._tick, callback=done)

    def run_latency(self):
        if self.busy:
            return
        self._stopped = False
        self.root.after(100, self._exec_latency)

    def _exec_latency(self):
        self.reset_stage_colors()
        self.do_latency()

    def do_latency(self, nxt=None):
        self.busy = True
        self.set_btns_enabled(False)
        self.start_time_timer()
        self.set_status("正在延迟优选并推送...", C["primary"])
        self._dashboard.update_stage("延迟优选")
        self.log_msg("\n" + "=" * 50)
        self.log_msg("延迟优选：读取 addressesapi.txt → TCP 延迟测试 → 保留前 N 名 → 推送新文件")
        self.log_msg("=" * 50)

        def done():
            self._update_node_count()
            self.set_status("✓ 延迟优选完成", C["success"])
            self.busy = False
            self.set_btns_enabled(True)
            if nxt is not None:
                self.root.after(300, nxt)

        # --latency-only 读取已去重的 addressesapi.txt，延迟测试后保留前 N 名并推送新文件
        self.run_cmd(
            [PYTHON, "-u", "-m", "cfnb", "--latency-only"],
            on_line=self._tick, callback=done)

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
        elif stage == "tcp":
            self.do_tcp()
        elif stage == "avail":
            self.do_avail()
        elif stage == "bw":
            self.do_bw()
        elif stage == "push":
            self.do_push()

    def _run_all(self):
        self._stopped = False
        self.reset_stage_colors()

        def s6():
            if self._stopped:
                return
            self.do_push(nxt=self._all_done)

        def s5():
            if self._stopped:
                return
            self.do_bw(nxt=s6)

        def s4():
            if self._stopped:
                return
            self.do_avail(nxt=s5)

        def s3():
            if self._stopped:
                return
            self.do_tcp(nxt=s4)

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
        # 应用外观主题（明暗切换）
        try:
            from cfnb.gui.styles import apply_theme
            from cfnb.config import get_config
            theme = getattr(get_config(), "GUI_THEME", "light") or "light"
            apply_theme(self.root, theme)
            self._apply_theme_to_widgets()
        except Exception as e:
            self.log_msg(f"主题切换失败: {e}")

    def _apply_theme_to_widgets(self):
        """主题切换后刷新各面板与状态栏配色（canvas 组件在下次重绘时读取 C）。"""
        try:
            self.root.configure(bg=C["bg"])
            for w in (self._panel_settings, self._panel_results, self._panel_run, self._panel_subs):
                if w:
                    w.configure(bg=C["bg"])
            self._panel_subs.apply_theme()
            self.lbl_status.configure(bg=C["bg"], fg=C["text"])
            self.lbl_nodes.configure(bg=C["bg"], fg=C["text_dim"])
            self.lbl_prog.configure(bg=C["bg"], fg=C["text_dim"])
            self._dashboard.apply_theme()
        except Exception:
            pass


def main():
    root = tk.Tk()
    try:
        from cfnb.config import get_config
        startup_theme = getattr(get_config(), "GUI_THEME", "light") or "light"
    except Exception:
        startup_theme = "light"
    apply_theme(root, startup_theme)
    app = CFGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
