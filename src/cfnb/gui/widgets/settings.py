"""设置面板组件（可滚动，鼠标滚轮穿透所有子控件）。"""

from __future__ import annotations

import json
import tkinter as tk
from tkinter import ttk, messagebox

from cfnb.gui.constants import C, SP, FONT, SETTINGS_FIELDS, CONFIG_FILE
from cfnb.gui.widgets.scrollframe import ScrollFrame


class ToggleSwitch(tk.Canvas):
    """自绘滑块开关，契合主题配色。"""

    def __init__(self, parent, variable, **kw):
        bg_col = kw.get("bg", C["surface"])
        super().__init__(parent, width=44, height=24, bg=bg_col,
                         highlightthickness=0, cursor="hand2")
        self.var = variable
        self.var.trace_add("write", lambda *args: self.draw())
        self.bind("<Button-1>", self.toggle)
        self.draw()

    def toggle(self, _evt):
        self.var.set(not self.var.get())

    def draw(self):
        self.delete("all")
        val = self.var.get()
        bg_color = C["primary"] if val else C["border"]
        self.create_oval(2, 2, 22, 22, fill=bg_color, outline="")
        self.create_oval(22, 2, 42, 22, fill=bg_color, outline="")
        self.create_rectangle(12, 2, 32, 22, fill=bg_color, outline="")
        circle_color = C["text_inv"] if val else C["text_dim"]
        if val:
            self.create_oval(24, 4, 40, 20, fill=circle_color, outline="")
        else:
            self.create_oval(4, 4, 20, 20, fill=circle_color, outline="")


class SettingsPanel(tk.Frame):
    """分类卡片式设置面板，支持滚动与鼠标滚轮。"""

    def __init__(self, parent, on_save=None, **kw):
        super().__init__(parent, bg=kw.get("bg", C["bg"]))
        self._on_save = on_save
        self._orig = {}
        self._vars = {}
        self._types = {}
        self._opts = {}
        self._build_ui()

    def _build_ui(self):
        header = tk.Frame(self, bg=C["bg"])
        header.pack(fill=tk.X, padx=SP["xl"], pady=(SP["lg"], SP["sm"]))
        tk.Label(header, text="设置", font=FONT["h1"],
                 bg=C["bg"], fg=C["text"]).pack(side=tk.LEFT)
        tk.Label(header, text="修改后点击「保存」生效",
                 font=FONT["small"], bg=C["bg"], fg=C["text_dim"]
                 ).pack(side=tk.LEFT, padx=(SP["md"], 0))

        self._scroll = ScrollFrame(self, bg=C["bg"])
        self._scroll.pack(fill=tk.BOTH, expand=True, padx=SP["md"], pady=(0, SP["sm"]))

        container = self._scroll.inner
        cur_cat = None
        for cat, label, key, wtype, opts in SETTINGS_FIELDS:
            if cat != cur_cat:
                cur_cat = cat
                cat_header = tk.Frame(container, bg=C["bg"])
                cat_header.pack(fill=tk.X, padx=SP["md"], pady=(SP["lg"], SP["xs"]))
                tk.Label(cat_header, text=cat, font=FONT["h2"],
                         bg=C["bg"], fg=C["primary"], anchor="w"
                         ).pack(fill=tk.X)

                cat_card = tk.Frame(
                    container, bg=C["surface"],
                    highlightthickness=1, highlightbackground=C["border"],
                )
                cat_card.pack(fill=tk.X, padx=SP["md"], pady=(0, SP["sm"]))

            row = tk.Frame(cat_card, bg=C["surface"],
                           padx=SP["lg"], pady=SP["sm"])
            row.pack(fill=tk.X)

            tk.Label(row, text=label, font=FONT["normal"],
                     bg=C["surface"], fg=C["text"],
                     width=14, anchor="w").pack(side=tk.LEFT)

            widget = self._create_widget(row, key, wtype, opts)
            widget.pack(side=tk.RIGHT, padx=(SP["sm"], 0))

            sep = tk.Frame(cat_card, bg=C["border"], height=1)
            sep.pack(fill=tk.X, padx=SP["md"])

        bf = tk.Frame(self, bg=C["bg"])
        bf.pack(fill=tk.X, padx=SP["xl"], pady=SP["md"])

        make_btn = _lazy_make_button()
        make_btn(bf, "保存配置", self.save, variant="primary").pack(
            side=tk.RIGHT, padx=(SP["xs"], 0))
        make_btn(bf, "重置", self.reload, variant="ghost").pack(side=tk.RIGHT)

        self._scroll.refresh_bindings()

    def _create_widget(self, parent, key, wtype, opts):
        var = None
        if wtype == "bool":
            var = tk.BooleanVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ToggleSwitch(parent, var)

        if wtype == "int":
            var = tk.IntVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Spinbox(parent, from_=opts[0], to=opts[1],
                               increment=opts[2], textvariable=var, width=16)

        if wtype == "float":
            var = tk.DoubleVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Spinbox(parent, from_=opts[0], to=opts[1],
                               increment=opts[2], textvariable=var, width=16,
                               format="%.2f")

        if wtype == "string":
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Entry(parent, textvariable=var, width=26)

        if wtype in ("list_int", "list_str"):
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = opts
            return ttk.Entry(parent, textvariable=var, width=26)

        if wtype == "choice":
            var = tk.StringVar()
            self._vars[key] = var
            self._types[key] = wtype
            self._opts[key] = tuple(opts) if opts else ()
            return ttk.Combobox(parent, textvariable=var,
                                values=list(opts or []),
                                state="readonly", width=24)

        var = tk.StringVar()
        self._vars[key] = var
        self._types[key] = "string"
        self._opts[key] = opts
        return ttk.Entry(parent, textvariable=var, width=26)

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

            out = {k: v for k, v in raw.items() if str(k).startswith("_comment")}
            out.update(clean)
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(out, f, indent=4, ensure_ascii=False)

            self._orig = clean
            try:
                from cfnb.config import reload_config
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


def _lazy_make_button():
    from cfnb.gui.styles import make_button
    return make_button
