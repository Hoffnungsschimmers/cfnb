"""仪表盘首页及实时图表组件"""

from __future__ import annotations

import math
import time
import tkinter as tk
from tkinter import ttk
from cfnb.gui.constants import C, SP, FONT, THRESHOLDS


class DashboardPanel(tk.Frame):
    """仪表盘面板：卡片网格 + 实时测速折线图"""

    def __init__(self, parent, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self.speeds: list[float] = []
        self.latencies: list[float] = []
        self.all_speeds_count = 0
        self.all_speeds_sum = 0.0
        self.all_speeds_max = 0.0
        self.start_time: float | None = None
        self._last_w = 0
        self._last_h = 0
        self._build_ui()

    def apply_theme(self):
        """主题切换后刷新本面板配色并重绘图表。"""
        try:
            self.configure(bg=C["bg"])
            for card in (getattr(self, "card_nodes", None),
                         getattr(self, "card_speed", None),
                         getattr(self, "card_time", None)):
                if card:
                    card.configure(bg=C["surface"], highlightbackground=C["border"])
            self.draw_chart()
        except Exception:
            pass

    def _build_ui(self):
        # 顶部网格卡片容器
        grid_frame = tk.Frame(self, bg=C["bg"])
        grid_frame.pack(fill=tk.X, padx=SP["xl"], pady=(SP["lg"], SP["sm"]))
        grid_frame.columnconfigure(0, weight=1)
        grid_frame.columnconfigure(1, weight=1)
        grid_frame.columnconfigure(2, weight=1)

        # 卡片 1: 节点统计
        self.card_nodes = self._create_card(grid_frame, 0, "📊 节点统计", [
            ("总数：", "lbl_nodes_total", "0"),
            ("已测：", "lbl_nodes_checked", "0"),
            ("通过：", "lbl_nodes_passed", "0")
        ])

        # 卡片 2: 带宽与延迟
        self.card_speed = self._create_card(grid_frame, 1, "⚡ 性能表现", [
            ("最快：", "lbl_speed_max", "0.00 Mbps"),
            ("均速：", "lbl_speed_avg", "0.00 Mbps"),
            ("最低延迟：", "lbl_latency_min", "0.0 ms")
        ])

        # 卡片 3: 时间统计
        self.card_time = self._create_card(grid_frame, 2, "⏱ 时间统计", [
            ("当前阶段：", "lbl_stage", "就绪"),
            ("已用时间：", "lbl_time_elapsed", "0s"),
            ("预估剩余：", "lbl_time_est", "--")
        ])

        # 图表卡片容器
        chart_outer = tk.Frame(
            self, bg=C["surface"],
            highlightthickness=1,
            highlightbackground=C["border"]
        )
        chart_outer.pack(fill=tk.BOTH, expand=True, padx=SP["xl"], pady=(SP["sm"], SP["lg"]))

        chart_title_frame = tk.Frame(chart_outer, bg=C["surface"])
        chart_title_frame.pack(fill=tk.X, padx=SP["lg"], pady=(SP["md"], 0))
        tk.Label(
            chart_title_frame, text="📈 测速实时曲线", font=FONT["h2"],
            bg=C["surface"], fg=C["text"]
        ).pack(side=tk.LEFT)
        self.lbl_chart_stats = tk.Label(
            chart_title_frame, text="暂无数据", font=FONT["small"],
            bg=C["surface"], fg=C["text_dim"]
        )
        self.lbl_chart_stats.pack(side=tk.RIGHT)

        # 绘图 Canvas
        self.canvas = tk.Canvas(
            chart_outer, bg=C["log_bg"],
            highlightthickness=0
        )
        self.canvas.pack(fill=tk.BOTH, expand=True, padx=SP["lg"], pady=SP["lg"])
        self.canvas.bind("<Configure>", self._on_resize)

    def _on_resize(self, evt):
        # 尺寸未变则跳过，避免窗口拖拽时每像素重绘导致卡顿
        if evt.width == self._last_w and evt.height == self._last_h:
            return
        self._last_w, self._last_h = evt.width, evt.height
        from cfnb.gui.styles import schedule_redraw
        schedule_redraw(self, self.draw_chart, delay_ms=80)

    def _create_card(self, parent, col, title, fields) -> tk.Frame:
        card = tk.Frame(
            parent, bg=C["surface"],
            highlightthickness=1,
            highlightbackground=C["border"],
            padx=SP["lg"], pady=SP["md"]
        )
        card.grid(row=0, column=col, padx=SP["sm"], sticky="nsew")

        tk.Label(
            card, text=title, font=FONT["h2"],
            bg=C["surface"], fg=C["primary"]
        ).pack(anchor="w", pady=(0, SP["sm"]))

        for label_text, var_name, default_val in fields:
            row = tk.Frame(card, bg=C["surface"])
            row.pack(fill=tk.X, pady=2)
            tk.Label(
                row, text=label_text, font=FONT["normal"],
                bg=C["surface"], fg=C["text_secondary"]
            ).pack(side=tk.LEFT)
            lbl_val = tk.Label(
                row, text=default_val, font=FONT["mono_lg"],
                bg=C["surface"], fg=C["text"]
            )
            lbl_val.pack(side=tk.RIGHT)
            setattr(self, var_name, lbl_val)

        return card

    def reset(self):
        """重置数据计数器"""
        self.speeds.clear()
        self.latencies.clear()
        self.all_speeds_count = 0
        self.all_speeds_sum = 0.0
        self.all_speeds_max = 0.0
        self.start_time = time.time()
        self.lbl_nodes_total.config(text="0")
        self.lbl_nodes_checked.config(text="0")
        self.lbl_nodes_passed.config(text="0")
        self.lbl_speed_max.config(text="0.00 Mbps")
        self.lbl_speed_avg.config(text="0.00 Mbps")
        self.lbl_latency_min.config(text="0.0 ms")
        self.lbl_time_elapsed.config(text="0s")
        self.lbl_time_est.config(text="--")
        self.lbl_chart_stats.config(text="等待数据...")
        self.canvas.delete("all")

    def update_nodes(self, checked: int, total: int, passed: int):
        self.lbl_nodes_total.config(text=str(total))
        self.lbl_nodes_checked.config(text=str(checked))
        self.lbl_nodes_passed.config(text=str(passed))

    def update_stage(self, stage_name: str):
        self.lbl_stage.config(text=stage_name)
        self.update_time()

    def update_time(self):
        if self.start_time is None:
            return
        elapsed = int(time.time() - self.start_time)
        self.lbl_time_elapsed.config(text=f"{elapsed}s")

    def add_latency(self, lat: float):
        self.latencies.append(lat)
        min_lat = min(self.latencies)
        self.lbl_latency_min.config(text=f"{min_lat:.1f} ms")

    def add_speed(self, speed: float):
        self.all_speeds_count += 1
        self.all_speeds_sum += speed
        if speed > self.all_speeds_max:
            self.all_speeds_max = speed

        self.speeds.append(speed)
        if len(self.speeds) > 100:
            self.speeds.pop(0)

        avg_speed = self.all_speeds_sum / self.all_speeds_count if self.all_speeds_count > 0 else 0.0
        self.lbl_speed_max.config(text=f"{self.all_speeds_max:.2f} Mbps")
        self.lbl_speed_avg.config(text=f"{avg_speed:.2f} Mbps")
        self.lbl_chart_stats.config(text=f"已收集 {self.all_speeds_count} 个测速点 (显示最近100个)")
        self.draw_chart()

    def draw_chart(self):
        """核心绘图逻辑：使用 Canvas 绘制渐变填充曲线"""
        canvas = self.canvas
        canvas.delete("all")
        w = canvas.winfo_width()
        h = canvas.winfo_height()
        if w < 10 or h < 10:
            return
        canvas.configure(bg=C["log_bg"])
        # 留白内边距
        pad_l, pad_r, pad_t, pad_b = 40, 15, 15, 20
        plot_w = w - pad_l - pad_r
        plot_h = h - pad_t - pad_b

        # 绘制背景网格线，纵向刻度基于速度阈值派生
        y_levels = [THRESHOLDS["speed_medium"], THRESHOLDS["speed_fast"], 100, 200]
        max_y = max(self.speeds) if self.speeds else 100
        # 向上取整一个合适的级别
        if max_y < 10: max_y = 10
        elif max_y < 50: max_y = 50
        elif max_y < 100: max_y = 100
        elif max_y < 200: max_y = 200
        else: max_y = math.ceil(max_y / 50) * 50

        # 绘制横向网格线
        grid_count = 4
        for i in range(grid_count + 1):
            val = (max_y / grid_count) * i
            y = pad_t + plot_h - (val / max_y) * plot_h
            canvas.create_line(pad_l, y, w - pad_r, y, fill=C["border"], dash=(4, 4))
            canvas.create_text(pad_l - 8, y, text=f"{val:.0f}", font=FONT["small"], fill=C["text_dim"], anchor="e")

        if not self.speeds:
            # 暂无数据提示
            canvas.create_text(
                w / 2, h / 2, text="等待精测轮速度数据数据点...",
                font=FONT["normal"], fill=C["text_dim"]
            )
            return

        # 映射折线坐标
        points = []
        n = len(self.speeds)
        x_step = plot_w / (n - 1) if n > 1 else plot_w

        for idx, val in enumerate(self.speeds):
            x = pad_l + idx * x_step
            y = pad_t + plot_h - (val / max_y) * plot_h
            points.append((x, y))

        # 绘制填充多边形 (浅蓝色面积图)
        if len(points) >= 2:
            poly_points = [points[0][0], pad_t + plot_h]
            for pt in points:
                poly_points.extend(pt)
            poly_points.extend([points[-1][0], pad_t + plot_h])
            canvas.create_polygon(poly_points, fill=C["primary_light"], outline="")

        # 绘制折线
        for idx in range(len(points) - 1):
            pt1, pt2 = points[idx], points[idx+1]
            canvas.create_line(pt1[0], pt1[1], pt2[0], pt2[1], fill=C["primary"], width=2.5)

        # 绘制圆点
        for x, y in points:
            canvas.create_oval(x - 3.5, y - 3.5, x + 3.5, y + 3.5, fill=C["accent"], outline=C["surface"], width=1)
