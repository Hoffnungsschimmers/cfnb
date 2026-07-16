"""可复用滚动容器：鼠标滚轮穿透到所有子控件（含 ttk 控件）。"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk


class ScrollFrame(tk.Frame):
    """内容可滚动的 Frame。

    - 竖直滚动条始终跟随内容高度
    - 鼠标滚轮在容器及所有子控件（Entry/Spinbox/Combobox 等）上都能滚动
    - 仅在内容尺寸变化时更新 scrollregion，避免无谓重排
    """

    def __init__(self, parent, bg=None, **kw):
        super().__init__(parent, **kw)
        self._bg = bg
        self.canvas = tk.Canvas(self, bg=bg, highlightthickness=0, **kw)
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.vsb = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.vsb.pack(side=tk.RIGHT, fill=tk.Y)
        self.canvas.configure(yscrollcommand=self.vsb.set)

        self.inner = tk.Frame(self.canvas, bg=bg)
        self._win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")

        self.inner.bind("<Configure>", self._on_inner_configure)
        self.canvas.bind("<Configure>", self._on_canvas_configure)
        # 滚轮穿透：绑定到 canvas 与 inner，并递归绑定所有子控件
        self.canvas.bind("<MouseWheel>", self._on_mousewheel)
        self.inner.bind("<MouseWheel>", self._on_mousewheel)
        self._bind_descendants(self.inner)

    def _bind_descendants(self, widget):
        try:
            widget.bind("<MouseWheel>", self._on_mousewheel)
        except Exception:
            pass
        for child in widget.winfo_children():
            self._bind_descendants(child)

    def _on_mousewheel(self, event):
        if event.delta:
            units = -int(event.delta / 120)
        elif event.num == 4:
            units = -1
        elif event.num == 5:
            units = 1
        else:
            units = 0
        self.canvas.yview_scroll(units, "units")
        return "break"

    def _on_inner_configure(self, _evt):
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas_configure(self, evt):
        self.canvas.itemconfig(self._win, width=evt.width)

    def refresh_bindings(self):
        """布局变动后重新绑定子控件滚轮（新增控件时调用）。"""
        self._bind_descendants(self.inner)
