"""GUI 主题与组件工厂。

设计原则：
- 单一可信主题源：apply_theme 更新模块级 C，所有控件一律从 C 取色，
  杜绝"背景与字体同色"。
- ttk 样式只配置一次基础项，不重复互相覆盖的选择器。
- 提供 schedule_redraw 节流工具，避免窗口缩放时高频重绘导致卡顿。
"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from cfnb.gui.constants import C, FONT, SP, THEMES


def theme_palette(name: str = "light") -> dict:
    return THEMES.get(name, THEMES["light"])


def apply_theme(root: tk.Tk, name: str = "light") -> dict:
    """应用主题：配置 ttk 样式并返回当前调色板。"""
    palette = theme_palette(name)
    C.clear()
    C.update(palette)

    try:
        style = ttk.Style()
        style.theme_use("clam")
    except Exception:
        style = ttk.Style()

    bg = palette["bg"]
    surface = palette["surface"]
    border = palette["border"]
    primary = palette["primary"]
    primary_hover = palette["primary_hover"]
    text = palette["text"]
    text_dim = palette["text_dim"]
    text_inv = palette["text_inv"]

    # 基础容器/文本
    style.configure("TFrame", background=bg)
    style.configure("TLabel", background=bg, foreground=text)
    style.configure("Surface.TLabel", background=surface, foreground=text)
    style.configure("Dim.TLabel", background=bg, foreground=text_dim)

    # 按钮：plain 风格，颜色由 tk.Button(make_button) 控制，ttk 仅兜底
    style.configure("TButton", background=surface, foreground=text,
                    bordercolor=border, relief="flat", padding=(10, 6),
                    font=FONT["btn"])
    style.map("TButton",
              background=[("active", surface), ("pressed", surface)],
              foreground=[("active", primary)])

    style.configure("TEntry", fieldbackground=surface, foreground=text,
                    bordercolor=border, relief="solid", padding=4)
    style.configure("TSpinbox", fieldbackground=surface, foreground=text,
                    bordercolor=border, relief="solid", arrowsize=10)
    style.configure("TCombobox", fieldbackground=surface, foreground=text,
                    bordercolor=border, relief="solid", arrowsize=10)
    style.map("TCombobox",
              fieldbackground=[("readonly", surface)],
              selectbackground=[("readonly", surface)])

    style.configure("TScrollbar", background=surface, troughcolor=bg,
                    bordercolor=border, relief="flat")
    style.configure("TSeparator", background=border)

    style.configure("Treeview", background=surface, foreground=text,
                    fieldbackground=surface, bordercolor=border,
                    rowheight=26, font=FONT["normal"])
    style.configure("Treeview.Heading", background=border, foreground=text,
                    font=FONT["h3"], relief="flat")
    style.map("Treeview", background=[("selected", primary)],
              foreground=[("selected", text_inv)])

    # 运行页进度条（统一用主色，圆角通过厚度表现）
    style.configure("Run.Horizontal.TProgressbar",
                    troughcolor=palette["track"], background=primary,
                    bordercolor=border, lightcolor=primary, darkcolor=primary_hover)

    return palette


def schedule_redraw(widget, draw_fn, delay_ms: int = 60):
    """节流重绘：窗口缩放期间只保留最后一次调用，避免每像素重绘卡顿。"""
    attr = "_redraw_timer"

    def _cancel():
        old = getattr(widget, attr, None)
        if old is not None:
            try:
                widget.after_cancel(old)
            except Exception:
                pass

    _cancel()
    timer = widget.after(delay_ms, draw_fn)
    setattr(widget, attr, timer)


def make_button(parent, text: str, command, variant: str = "ghost",
                font_key: str = "btn", padx: int = 14, pady: int = 7,
                **kw) -> tk.Button:
    """统一按钮工厂。

    variant: primary(橙实心主操作) / accent(橙实心，兼容旧调用)
             danger(红实心) / ghost(浅边框次要)
    """
    if variant == "accent":
        variant = "primary"
    variant_map = {
        "primary": (C["primary"], C["text_inv"], C["primary_hover"]),
        "danger":  (C["danger"], C["text_inv"], C["danger_light"]),
        "ghost":   (C["surface"], C["text"], C["surface_hover"]),
    }
    bg, fg, hover = variant_map.get(variant, variant_map["ghost"])
    return tk.Button(
        parent, text=text, command=command,
        bg=bg, fg=fg, activebackground=hover, activeforeground=fg,
        relief=tk.FLAT, bd=0, cursor="hand2",
        font=FONT[font_key], padx=padx, pady=pady, **kw,
    )


class NavButton(tk.Button):
    """侧边栏导航按钮，统一管理选中态与悬停态。"""

    def __init__(self, parent, text, command, palette=None, **kw):
        super().__init__(parent, text=text, command=command, **kw)
        self._palette = palette or C
        self._active = False
        self.configure(
            relief=tk.FLAT, bd=0, cursor="hand2",
            anchor="w", padx=14, pady=10,
            font=FONT["btn"],
            bg=self._palette["sidebar"], fg=self._palette["text_inv"],
            activebackground=self._palette["sidebar_hover"],
            activeforeground=self._palette["text_inv"],
        )
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)

    def set_active(self, active: bool):
        self._active = active
        self._paint()

    def _paint(self):
        if self._active:
            self.configure(bg=self._palette["sidebar_active"],
                           fg=self._palette["text_inv"],
                           activebackground=self._palette["sidebar_active"])
        else:
            self.configure(bg=self._palette["sidebar"],
                           fg=self._palette["text_inv"],
                           activebackground=self._palette["sidebar_hover"])

    def _on_enter(self, _e):
        if not self._active:
            self.configure(bg=self._palette["sidebar_hover"])

    def _on_leave(self, _e):
        self._paint()


def card(parent, **kw):
    """统一卡片容器：surface 背景 + 细边框 + 圆角（用高亮边框模拟圆角）。"""
    bg = kw.pop("bg", C["surface"])
    bd = kw.pop("highlightbackground", C["border"])
    return tk.Frame(parent, bg=bg, highlightthickness=1,
                    highlightbackground=bd, **kw)


def section_title(parent, text, **kw):
    """分区标题：橙色小标签式，左对齐。"""
    fg = kw.pop("fg", C["primary"])
    return tk.Label(parent, text=text, font=FONT["h2"],
                    bg=kw.get("bg", C["bg"]), fg=fg, anchor="w", **kw)


def pill(parent, text, bg, fg, **kw):
    """状态药丸标签。"""
    return tk.Label(parent, text=text, font=FONT["small"],
                    bg=bg, fg=fg, padx=SP["sm"], pady=2,
                    relief=tk.FLAT, **kw)
