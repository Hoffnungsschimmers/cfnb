"""时间线指示器组件"""

from __future__ import annotations

import tkinter as tk
from cfnb.gui.constants import C, FONT


class StepperWidget(tk.Frame):
    """现代化圆角卡片式步骤指示器，带发光脉冲动画和状态标记"""

    def __init__(self, parent, stages, height=70, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._stages = stages
        self._status = {k: "idle" for k, _, _, _ in stages}
        self._pulse_phase = 0
        self._animating = False
        self._canvas = tk.Canvas(
            self, bg=self.cget("bg"), height=max(height, 70), highlightthickness=0,
        )
        self._canvas.pack(fill=tk.BOTH, expand=True)
        self._last_w = 0
        self._last_h = 0
        self._canvas.bind("<Configure>", self._on_resize)

    def _on_resize(self, evt):
        if evt.width == self._last_w and evt.height == self._last_h:
            return
        self._last_w, self._last_h = evt.width, evt.height
        from cfnb.gui.styles import schedule_redraw
        schedule_redraw(self, self._draw, delay_ms=80)

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
        self.after(60, self._animate)

    def _draw_round_rect(self, canvas, x1, y1, x2, y2, r, **kwargs):
        """画布自绘圆角矩形辅助函数"""
        points = [
            x1 + r, y1,
            x1 + r, y1,
            x2 - r, y1,
            x2 - r, y1,
            x2, y1,
            x2, y1 + r,
            x2, y1 + r,
            x2, y2 - r,
            x2, y2 - r,
            x2, y2,
            x2 - r, y2,
            x2 - r, y2,
            x1 + r, y2,
            x1 + r, y2,
            x1, y2,
            x1, y2 - r,
            x1, y2 - r,
            x1, y1 + r,
            x1, y1 + r,
            x1, y1
        ]
        return canvas.create_polygon(points, **kwargs, smooth=True)

    def _draw(self, _evt=None):
        c = self._canvas
        c.delete("all")
        w = max(c.winfo_width(), 300)
        h = c.winfo_height()
        n = len(self._stages)

        margin = max(30, int(w * 0.05))
        sp = (w - 2 * margin) / max(n - 1, 1)
        cy = h / 2
        card_w = 120
        card_h = 44
        r = 6

        # 色值配置
        colors = {
            "idle": {
                "bg": C["surface"],
                "border": C["border"],
                "text": C["text_dim"]
            },
            "running": {
                "bg": C["primary_light"],
                "border": C["primary"],
                "text": C["primary"]
            },
            "done": {
                "bg": C["success_light"],
                "border": C["success"],
                "text": C["success"]
            },
            "fail": {
                "bg": C["danger_light"],
                "border": C["danger"],
                "text": C["danger"]
            }
        }

        # 1. 绘制连接线 (先画线防遮挡)
        for i in range(1, n):
            x0 = margin + (i - 1) * sp
            x1 = margin + i * sp
            prev_done = self._status[self._stages[i - 1][0]] == "done"
            lc = C["success"] if prev_done else C["border"]
            c.create_line(
                x0 + card_w/2 + 2, cy, x1 - card_w/2 - 2, cy,
                fill=lc, width=2.0, dash=(3, 3)
            )

        # 2. 绘制卡片
        for i, (key, short, desc, icon) in enumerate(self._stages):
            x = margin + i * sp
            st = self._status.get(key, "idle")
            cfg = colors.get(st, colors["idle"])

            # 卡片边界
            x1, y1 = x - card_w/2, cy - card_h/2
            x2, y2 = x + card_w/2, cy + card_h/2

            # 呼吸发光边框动画 (running)
            if st == "running":
                pulse = r + 4 + (self._pulse_phase % 10) * 0.5
                self._draw_round_rect(
                    c, x1 - pulse + 6, y1 - pulse + 4, x2 + pulse - 6, y2 + pulse - 4,
                    r + 4, fill="", outline=C["primary"], width=1.5
                )

            # 绘制主卡片底框
            self._draw_round_rect(
                c, x1, y1, x2, y2, r,
                fill=cfg["bg"], outline=cfg["border"], width=1.5
            )

            # 绘制 Icon
            c.create_text(
                x - card_w/2 + 20, cy, text=icon,
                font=("", 13), fill=cfg["text"]
            )

            # 绘制阶段标题与小副标题
            c.create_text(
                x - card_w/2 + 42, cy - 8, text=short,
                font=FONT["h3"], fill=C["text"] if st != "idle" else C["text_dim"],
                anchor="w"
            )

            # 副标题依据状态定制
            sub_text = desc
            sub_color = C["text_dim"]
            if st == "done":
                sub_text = "✓ 已完成"
                sub_color = C["success"]
            elif st == "running":
                sub_text = "● 运行中"
                sub_color = C["primary"]
            elif st == "fail":
                sub_text = "✗ 失败"
                sub_color = C["danger"]

            c.create_text(
                x - card_w/2 + 42, cy + 8, text=sub_text,
                font=FONT["small"], fill=sub_color,
                anchor="w"
            )
