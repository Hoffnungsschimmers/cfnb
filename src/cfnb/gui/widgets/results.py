import os
import re
import tkinter as tk
from tkinter import ttk, messagebox
from cfnb.gui.constants import C, SP, FONT, IP_FILE, THRESHOLDS

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
        self._data = []
        self._sort_col = None
        self._sort_rev = False
        self._build_ui()

    def _create_metric_card(self, parent, col, title, value) -> tk.Label:
        card = tk.Frame(
            parent, bg=C["surface"],
            highlightthickness=1,
            highlightbackground=C["border"],
            padx=SP["md"], pady=SP["sm"]
        )
        card.grid(row=0, column=col, padx=SP["xs"], sticky="nsew")
        tk.Label(
            card, text=title, font=FONT["small"],
            bg=C["surface"], fg=C["text_dim"]
        ).pack(anchor="w")
        lbl_val = tk.Label(
            card, text=value, font=FONT["h2"],
            bg=C["surface"], fg=C["text"]
        )
        lbl_val.pack(anchor="w", pady=(SP["xs"], 0))
        return lbl_val

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

        # 统计指标行 (Metrics Card Row)
        self.metrics_frame = tk.Frame(self, bg=C["bg"])
        self.metrics_frame.pack(fill=tk.X, padx=SP["xl"], pady=(0, SP["sm"]))
        self.metrics_frame.columnconfigure(0, weight=1)
        self.metrics_frame.columnconfigure(1, weight=1)
        self.metrics_frame.columnconfigure(2, weight=1)

        self.m1 = self._create_metric_card(self.metrics_frame, 0, "⚡ 最佳带宽", "-- Mbps")
        self.m2 = self._create_metric_card(self.metrics_frame, 1, "🔗 最低延迟", "-- ms")
        self.m3 = self._create_metric_card(self.metrics_frame, 2, "🌍 地理分布", "--")

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

        sty = ttk.Style()
        sty.configure(
            "Treeview",
            background=C["surface"],
            foreground=C["text"],
            fieldbackground=C["surface"],
            bordercolor=C["border"],
            borderwidth=0,
            rowheight=24,
        )
        sty.configure(
            "Treeview.Heading",
            background=C["border_light"],
            foreground=C["text"],
            bordercolor=C["border"],
            borderwidth=1,
            font=FONT["h3"]
        )
        sty.map(
            "Treeview",
            background=[("selected", C["primary"])],
            foreground=[("selected", "white")]
        )

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

        # 1. 提取 IP:端口 (第一段非空字符，去掉后面的速度或延迟)
        ip_match = re.match(r"^([a-zA-Z0-9.:\[\]]+)", s)
        if not ip_match:
            return None
        ip = ip_match.group(1)

        # 2. 提取国家 (井号后面的大写字母)
        country = ""
        if "#" in s:
            parts = s.split("#", 1)
            rest = parts[1].strip()
            tkns = rest.split()
            if tkns and len(tkns[0]) == 2 and tkns[0].isupper():
                country = tkns[0]

        # 3. 提取速度 (Mbps)
        spd = ""
        spd_match = re.search(r"([\d.]+)\s*Mbps", s)
        if spd_match:
            spd = f"{float(spd_match.group(1)):.2f}"

        # 4. 提取延迟 (ms)
        lat = ""
        lat_match = re.search(r"([\d.]+)\s*ms", s)
        if lat_match:
            lat = f"{float(lat_match.group(1)):.2f}"

        return {"ip_port": ip, "country": country, "speed": spd, "latency": lat} if ip else None

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
                "fast" if spd_val > THRESHOLDS["speed_fast"]
                else ("medium" if spd_val > THRESHOLDS["speed_medium"]
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
            self.m1.config(text="-- Mbps")
            self.m2.config(text="-- ms")
            self.m3.config(text="--")
            return
        speeds = [float(d["speed"]) for d in self._data if d["speed"]]
        latencies = [float(d["latency"]) for d in self._data if d["latency"]]
        countries = [d["country"] for d in self._data if d["country"]]
        
        cnt = len(self._data)
        self._stats_lbl.config(text=f"共 {cnt} 个节点")
        if speeds:
            max_spd = max(speeds)
            min_lat = min(latencies) if latencies else 0
            
            from collections import Counter
            top_country = Counter(countries).most_common(1)[0][0] if countries else "--"
            
            self.m1.config(text=f"{max_spd:.2f} Mbps")
            self.m2.config(text=f"{min_lat:.1f} ms" if min_lat > 0 else "-- ms")
            self.m3.config(text=str(top_country))
            
            self._info_lbl.config(
                text=(
                    f"平均 {sum(speeds) / len(speeds):.1f} Mbps"
                    f"  |  最快 {max_spd:.1f}"
                    f"  |  最慢 {min(speeds):.1f}"
                ),
            )
        else:
            self.m1.config(text="-- Mbps")
            self.m2.config(text="-- ms")
            self.m3.config(text="--")
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
