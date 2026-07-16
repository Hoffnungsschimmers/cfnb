import os
import sys

# Paths
# Since GUI constants are in src/cfnb/gui/constants.py, project root is 3 levels up
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CONFIG_FILE = os.path.join(PROJECT_ROOT, "config.json")
IP_FILE = os.path.join(PROJECT_ROOT, "ip.txt")
GUI_LOG_FILE = os.path.join(PROJECT_ROOT, "gui.log")

# 设计系统 —— "Edge Telemetry" 方向
# 单一签名色：Cloudflare 橙；深色优先的监控控制台美学。
# 不在蓝/靛之间摇摆，橙色是唯一彩色强调，使界面身份鲜明。
_EDGE_ORANGE = "#ff7a1a"      # 签名强调色（Cloudflare 橙）
_EDGE_ORANGE_DK = "#e0650c"   # 橙 hover/按压

# Color palette & design system
C = {
    "bg":            "#fbfaf8",     # 暖中性背景（非冷灰）
    "surface":       "#ffffff",     # 卡片
    "surface_hover": "#f3f1ec",     # 悬停
    "sidebar":       "#1a1714",     # 深色侧栏（始终深色，作为锚）
    "sidebar_hover": "#2a241e",
    "sidebar_active": _EDGE_ORANGE, # 激活态用橙，唯一彩色
    "primary":       _EDGE_ORANGE,  # 主操作 = 橙
    "primary_hover": _EDGE_ORANGE_DK,
    "primary_light": "#fff1e6",     # 浅橙徽章底
    "primary_lighter": "#ffe4cf",
    "text":          "#1c1917",     # 近黑暖墨
    "text_secondary":"#44403c",
    "text_dim":      "#78716c",     # 暖灰
    "text_inv":      "#fffaf5",     # 深底上的反白
    "text_inv_dim":  "#a8a29e",
    "border":        "#e7e3dc",     # 暖边框
    "border_light":  "#f0ede8",
    "success":       "#16a34a",     # 绿（状态，非强调）
    "success_light": "#ecfdf3",
    "warning":       "#d97706",     # 琥珀
    "warning_light": "#fef6e7",
    "danger":        "#dc2626",     # 红
    "danger_light":  "#fef2f2",
        "log_bg":        "#fbfaf8",
        "log_fg":        "#1c1917",
        "shadow":        "#1c19170f",
        "accent":        _EDGE_ORANGE,  # 单一强调 = 橙
        "radius":        10,
        "track":         "#efeae3",
    }

    # 主题调色板：明暗双主题共用同一套语义键，运行时切换
THEMES = {
        "light": {
            "bg":            "#fbfaf8",
            "surface":       "#ffffff",
            "surface_hover": "#f3f1ec",
            "sidebar":       "#1a1714",
            "sidebar_hover": "#2a241e",
            "sidebar_active": _EDGE_ORANGE,
            "primary":       _EDGE_ORANGE,
            "primary_hover": _EDGE_ORANGE_DK,
            "primary_light": "#fff1e6",
            "primary_lighter":"#ffe4cf",
            "text":          "#1c1917",
            "text_secondary":"#44403c",
            "text_dim":      "#78716c",
            "text_inv":      "#fffaf5",
            "text_inv_dim":  "#a8a29e",
            "border":        "#e7e3dc",
            "border_light":  "#f0ede8",
            "success":       "#16a34a",
            "success_light": "#ecfdf3",
            "warning":       "#d97706",
            "warning_light": "#fef6e7",
            "danger":        "#dc2626",
            "danger_light":  "#fef2f2",
            "log_bg":        "#fbfaf8",
            "log_fg":        "#1c1917",
            "shadow":        "#1c19170f",
            "accent":        _EDGE_ORANGE,
            "radius":        10,
            "track":         "#efeae3",
        },
    "dark": {
        "bg":            "#0c0a09",     # 近黑暖底（控制台）
        "surface":       "#171412",     # 卡片
        "surface_hover": "#221d19",
        "sidebar":       "#0a0807",     # 最深
        "sidebar_hover": "#1c1714",
        "sidebar_active": _EDGE_ORANGE,
        "primary":       _EDGE_ORANGE,
        "primary_hover": _EDGE_ORANGE_DK,
        "primary_light": "#3a2415",
        "primary_lighter":"#2a190e",
        "text":          "#f5f0ea",     # 暖白
        "text_secondary":"#d6cfc6",
        "text_dim":      "#9a9189",
        "text_inv":      "#0c0a09",
        "text_inv_dim":  "#d6cfc6",
        "border":        "#2a241e",
        "border_light":  "#221d19",
        "success":       "#34d399",
        "success_light": "#0c2e1f",
        "warning":       "#fbbf24",
        "warning_light": "#3a2a0c",
        "danger":        "#f87171",
        "danger_light":  "#3a1414",
        "log_bg":        "#0c0a09",
        "log_fg":        "#cbd5e1",
        "shadow":        "#00000040",
        "accent":        _EDGE_ORANGE,
        "radius":        10,
        "track":         "#221d19",
        },
}

SP = {
    "xs": 4, "sm": 8, "md": 12,
    "lg": 16, "xl": 24, "xxl": 32,
}

_FF = "微软雅黑" if sys.platform == "win32" else "Segoe UI"
_MONO = "Consolas" if sys.platform == "win32" else "JetBrains Mono"
FONT = {
    "title":   (_FF, 19, "bold"),
    "h1":      (_FF, 14, "bold"),
    "h2":      (_FF, 12, "bold"),
    "h3":      (_FF, 11, "bold"),
    "normal":  (_FF, 10),
    "small":   (_FF, 9),
    "mono":    (_MONO, 9),
    "mono_lg": (_MONO, 11, "bold"),
    "btn":     (_FF, 10, "bold"),
    "btn_lg":  (_FF, 11, "bold"),
    "status":  (_FF, 9),
}

# 速度/延迟着色阈值（Mbps / ms），集中管理，供结果表与仪表盘共用
THRESHOLDS = {
    "speed_fast": 50.0,    # 大于该值视为"快"
    "speed_medium": 20.0,  # 介于 medium~fast 视为"中"，以下视为"慢"
    "latency_good": 100.0, # 延迟小于该值(ms)视为优
}

STAGES = [
    ("cfdata", "CFData",   "扫描网段",   "🔍"),
    ("fetch",  "获取IP",   "拉取节点",   "📥"),
    ("tcp",    "TCP检测",  "TCP测试",    "🔗"),
    ("avail",  "可用检测", "安全可用性", "🌐"),
    ("bw",     "带宽测速", "测速",       "⚡"),
    ("push",   "推送",     "GitHub",     "🚀"),
]

SETTINGS_FIELDS = [
    # 阶段 1：数据源与预过滤 (CFData & 获取IP)
    ("1. 数据源与预过滤", "端口过滤",     "PRE_FILTER_PORT_ENABLED",     "bool",     None),
    ("1. 数据源与预过滤", "允许端口",     "PRE_FILTER_PORTS",            "list_int", None),
    ("1. 数据源与预过滤", "国家白名单",   "FILTER_COUNTRIES_ENABLED",    "bool",     None),
    ("1. 数据源与预过滤", "允许国家",     "ALLOWED_COUNTRIES",           "list_str", None),
    ("1. 数据源与预过滤", "国家黑名单",   "PRE_FILTER_BLOCKED_ENABLED",  "bool",     None),
    ("1. 数据源与预过滤", "屏蔽国家",     "PRE_FILTER_BLOCKED_COUNTRIES","list_str", None),

    # 阶段 2：TCP 延迟测试
    ("2. TCP 延迟测试", "TCP 探测数",   "TCP_PROBES",                  "int",      (1, 10, 1)),
    ("2. TCP 延迟测试", "TCP 超时(秒)", "TIMEOUT",                     "int",      (1, 15, 1)),
    ("2. TCP 延迟测试", "TCP最大并发",   "MAX_WORKERS",                 "int",      (10, 3000, 50)),
    ("2. TCP 延迟测试", "最低成功率",   "MIN_SUCCESS_RATE",            "float",    (0.0, 1.0, 0.05)),

    # 阶段 3：可用性安全检测
    ("3. 可用性安全检测", "开启检测",     "TEST_AVAILABILITY",           "bool",     None),
    ("3. 可用性安全检测", "检测并发数",   "AVAILABILITY_WORKERS",        "int",      (10, 3000, 50)),
    ("3. 可用性安全检测", "检测超时(秒)", "AVAILABILITY_CONNECT_TIMEOUT","int",      (1, 30, 1)),

    # 阶段 4：带宽测速
    ("4. 带宽测速", "测速候选数",   "BANDWIDTH_CANDIDATES",        "int",      (100, 10000, 100)),
    ("4. 带宽测速", "测速下载(MB)", "BANDWIDTH_SIZE_MB",           "float",    (0.1, 100.0, 0.5)),
    ("4. 带宽测速", "测速超时(秒)", "BANDWIDTH_TIMEOUT",           "int",      (5, 300, 10)),
    ("4. 带宽测速", "测速并发",     "BANDWIDTH_WORKERS",           "int",      (1, 200, 5)),

    # 阶段 5：输出与 DNS 部署
    ("5. 输出与 DNS 部署", "全局模式",     "USE_GLOBAL_MODE",             "bool",     None),
    ("5. 输出与 DNS 部署", "保留节点数",   "GLOBAL_TOP_N",                "int",      (1, 200, 10)),
    ("5. 输出与 DNS 部署", "评分带宽权重", "QUALITY_SPEED_WEIGHT",        "float",    (0.0, 1.0, 0.05)),
    ("5. 输出与 DNS 部署", "评分延迟权重", "QUALITY_LATENCY_WEIGHT",      "float",    (0.0, 1.0, 0.05)),
    ("5. 输出与 DNS 部署", "显示带宽(IP.txt)","IP_TXT_SHOW_BANDWIDTH",    "bool",     None),
    ("5. 输出与 DNS 部署", "显示延迟(IP.txt)","IP_TXT_SHOW_LATENCY",      "bool",     None),
    ("5. 输出与 DNS 部署", "CF DNS更新",    "CF_ENABLED",                  "bool",     None),
    ("5. 输出与 DNS 部署", "API Token",     "CF_API_TOKEN",                "string",   None),
    ("5. 输出与 DNS 部署", "Zone ID",       "CF_ZONE_ID",                  "string",   None),
    ("5. 输出与 DNS 部署", "DNS 记录名",    "CF_DNS_RECORD_NAME",          "string",   None),
    ("5. 输出与 DNS 部署", "记录类型",      "DNS_RECORD_TYPE",             "choice",   ("A", "TXT")),
    ("5. 输出与 DNS 部署", "TTL",           "CF_TTL",                      "int",      (60, 86400, 60)),
    ("5. 输出与 DNS 部署", "CF 代理",       "CF_PROXIED",                  "bool",     None),

    # 阶段 6：订阅转换（获取订阅器里的 IP）
    ("6. 订阅转换", "主流程自动",   "SUB_CONVERT_ENABLED",         "bool",     None),
    ("6. 订阅转换", "输入模式",     "SUB_INPUT_MODE",              "choice",   ["both", "node", "url"]),
    ("6. 订阅转换", "候选订阅器",   "SUB_GENERATORS",              "list_str", None),
    ("6. 订阅转换", "节点域名",     "SUB_NODE_HOST",               "string",   None),
    ("6. 订阅转换", "节点UUID",     "SUB_NODE_UUID",               "string",   None),
    ("6. 订阅转换", "订阅链接",     "SUB_URLS",                    "list_str", None),
    ("6. 订阅转换", "输出文件",     "SUB_OUTPUT_FILE",             "string",   None),
    ("6. 订阅转换", "默认国家",     "SUB_DEFAULT_COUNTRY",         "string",   None),
    ("6. 订阅转换", "域名解析IP",   "SUB_RESOLVE_DOMAIN",          "bool",     None),

    # 阶段 7：延迟优选（对去重后的订阅 IP 做延迟测试，保留前 N 名推送）
    ("7. 延迟优选", "保留前N名",      "SUB_LATENCY_TOPN",            "int",      (1, 100000, 1)),
    ("7. 延迟优选", "输出文件",       "SUB_LATENCY_OUTPUT_FILE",     "string",   None),
    ("7. 延迟优选", "连接超时(秒)",   "SUB_LATENCY_TIMEOUT",         "float",    (0.1, 30.0, 0.1)),
    ("7. 延迟优选", "并发数",         "SUB_LATENCY_WORKERS",         "int",      (1, 1000, 1)),

    # 阶段 8：外观
    ("8. 外观", "主题", "GUI_THEME", "choice", ["light", "dark"]),

    # 阶段 9：定时执行
    ("9. 定时执行", "启用自动调度", "AUTO_SCHEDULE_ENABLED", "bool", None),
    ("9. 定时执行", "间隔(小时)", "AUTO_SCHEDULE_INTERVAL_HOURS", "float", (0.5, 720.0, 0.5)),
]
