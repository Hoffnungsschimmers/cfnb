"""配置管理模块 - 使用 Pydantic 进行验证和类型提示"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class SourceConfig(BaseModel):
    """单个数据源配置"""

    url: str
    enabled: bool = True


class Config(BaseSettings):
    """主配置模型 - 所有参数定义在 config.json 中"""

    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).parent.parent.parent / "scripts" / ".env.local"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ==================== 筛选模式与数量控制 ====================
    USE_GLOBAL_MODE: bool = True
    GLOBAL_TOP_N: int = Field(default=15, ge=1, le=200)
    PER_COUNTRY_TOP_N: int = Field(default=1, ge=1, le=50)
    PER_COUNTRY_QUOTA: dict[str, int] = Field(default_factory=dict)
    BANDWIDTH_CANDIDATES: int = Field(default=5000, ge=1, le=10000)
    DNS_UPDATE_TARGET_COUNT: int = Field(default=15, ge=1, le=200)
    QUALITY_SPEED_WEIGHT: float = Field(default=0.60, ge=0.0, le=1.0)
    QUALITY_LATENCY_WEIGHT: float = Field(default=0.40, ge=0.0, le=1.0)

    # ==================== TCP 连接测试参数 ====================
    TCP_PROBES: int = Field(default=1, ge=1, le=10)
    MIN_SUCCESS_RATE: float = Field(default=1.0, ge=0.0, le=1.0)
    TIMEOUT: float = Field(default=2.0, gt=0, le=30)
    SOCKET_DEFAULT_TIMEOUT: int = Field(default=3, ge=1, le=60)
    PROGRESS_PRINT_INTERVAL: float = Field(default=1.0, gt=0, le=60)

    # ==================== 前置过滤参数 ====================
    PRE_FILTER_PORT_ENABLED: bool = True
    PRE_FILTER_PORTS: list[int] = Field(default_factory=lambda: [443])
    PRE_FILTER_BLOCKED_ENABLED: bool = True
    PRE_FILTER_BLOCKED_COUNTRIES: list[str] = Field(default_factory=lambda: ["CN"])
    FILTER_COUNTRIES_ENABLED: bool = False
    ALLOWED_COUNTRIES: list[str] = Field(default_factory=list)

    # ==================== DNS 过滤参数（仅作用于 DNS 更新） ====================
    FILTER_BLOCKED_COUNTRIES_ENABLED: bool = True
    BLOCKED_COUNTRIES: list[str] = Field(
        default_factory=lambda: [
            "BD",
            "BI",
            "BY",
            "CD",
            "CF",
            "CN",
            "CU",
            "DE",
            "ET",
            "HK",
            "IR",
            "KP",
            "LY",
            "MO",
            "NG",
            "NL",
            "PK",
            "RU",
            "SD",
            "SO",
            "SY",
            "TH",
            "TW",
            "UA",
            "VE",
            "VN",
            "YE",
            "ZW",
        ]
    )
    DNS_IP_RISK_FILTER_ENABLED: bool = False
    DNS_IP_RISK_MAX_LEVEL: str = "高风险"
    FILTER_IPV6_AVAILABILITY: bool = True

    # ==================== 微信通知 (WxPusher) ====================
    ENABLE_WXPUSHER: bool = True
    WXPUSHER_APP_TOKEN: str = "your_app_token_here"
    WXPUSHER_UIDS: list[str] = Field(default_factory=lambda: ["your_uid_here"])
    WXPUSHER_API_URL: str = "https://wxpusher.zjiecode.com/api/send/message"
    NOTIFY_TIMEOUT: int = Field(default=3, ge=1, le=30)
    NOTIFY_CONNECT_TIMEOUT: int = Field(default=3, ge=1, le=30)

    # ==================== GUI 外观 ====================
    GUI_THEME: str = Field(default="light", pattern="^(light|dark)$")

    # ==================== Cloudflare DNS 批量更新 ====================
    CF_ENABLED: bool = True
    CF_API_TOKEN: str = "your_CF_API_TOKEN"
    CF_ZONE_ID: str = "your_CF_ZONE_ID"
    CF_DNS_RECORD_NAME: str = "your_CF_DNS_RECORD_NAME"
    CF_TTL: int = Field(default=60, ge=60, le=86400)
    CF_PROXIED: bool = False
    CF_DNS_CONNECT_TIMEOUT: int = Field(default=3, ge=1, le=30)
    CF_DNS_READ_TIMEOUT: int = Field(default=3, ge=1, le=30)
    DNS_RECORD_TYPE: str = "TXT"

    # ==================== 节点数据源 ====================
    ADDITIONAL_SOURCES: list[SourceConfig] = Field(default_factory=list)
    FETCH_MAX_RETRIES: int = Field(default=3, ge=0, le=10)
    FETCH_RETRY_DELAY: int = Field(default=3, ge=0, le=60)
    FETCH_TIMEOUT: int = Field(default=20, ge=5, le=120)
    FETCH_CONNECT_TIMEOUT: int = Field(default=10, ge=1, le=60)
    OUTPUT_FILE: str = "ip.txt"
    ENABLE_LOGGING: bool = False
    LOG_FILE: str = "cfnb.log"

    # ==================== ASN 网段数据源（借鉴 RIPEstat announced-prefixes） ====================
    ASN_SOURCES_ENABLED: bool = False
    ASN_SOURCES: list[int] = Field(default_factory=lambda: [13335])
    ASN_SOURCES_IPV6: bool = False
    ASN_SOURCE_PORT: int = Field(default=443, ge=1, le=65535)
    ASN_SOURCE_COUNTRY: str = "US"
    ASN_SOURCE_MAX_IPS: int = Field(default=5000, ge=1, le=200000)
    ASN_SOURCE_TIMEOUT: int = Field(default=20, ge=5, le=120)
    ASN_SOURCE_CONNECT_TIMEOUT: int = Field(default=10, ge=1, le=60)
    ASN_SOURCE_RETRY_MAX: int = Field(default=2, ge=0, le=5)
    ASN_SOURCE_RETRY_DELAY: int = Field(default=3, ge=0, le=60)

    # ==================== 订阅转换 (Subscription -> IP 列表) ====================
    SUB_CONVERT_ENABLED: bool = False
    # 输入模式：node=仅用候选订阅器定位器；url=仅用现成订阅链接；
    #           both=两者同时跑并合并（默认，定位器+现成订阅都要）
    SUB_INPUT_MODE: str = "both"
    SUB_URLS: list[str] = Field(default_factory=list)
    # 节点模式：你的 vless 节点信息（host 一般为 Cloudflare Pages/Worker 域名）
    # 注意：订阅器返回的 IP 来自其内置优选列表，与下面的值无关；
    # 这里放任意有效值即可触发订阅器返回节点，因此预设了占位值，用户无需修改。
    SUB_NODE_HOST: str = "example.com"
    # 魔法 UUID：edgetunnel 系订阅器的"优选订阅生成器(BEST_SUB)"模式触发值
    # （需配合 host=example.com）。用它能拿到完整优选节点列表，而非单个兜底节点。
    SUB_NODE_UUID: str = "00000000-0000-4000-8000-000000000000"
    # 候选订阅器列表（workerVless2sub 部署实例）。
    # 每项格式为 "名称|域名"，例如 "CM|sub.cmliussss.net"；
    # 仅写域名也可（如 "sub.us.ci"）。工具会逐个拉取并合并去重 IP。
    SUB_GENERATORS: list[str] = Field(default_factory=list)
    # 被用户手动禁用的订阅器名称集合（与 SUB_GENERATORS 的 "名称" 对应）
    SUB_DISABLED_GENERATORS: set[str] = Field(default_factory=set)
    SUB_OUTPUT_FILE: str = "addressesapi.txt"
    SUB_DEFAULT_COUNTRY: str = "UN"
    SUB_RESOLVE_DOMAIN: bool = True
    SUB_FETCH_TIMEOUT: int = Field(default=20, ge=5, le=120)
    SUB_FETCH_CONNECT_TIMEOUT: int = Field(default=10, ge=1, le=60)
    SUB_FETCH_MAX_RETRIES: int = Field(default=3, ge=0, le=10)
    SUB_FETCH_RETRY_DELAY: int = Field(default=3, ge=0, le=60)
    SUB_RESOLVE_WORKERS: int = Field(default=32, ge=1, le=500)
    # 延迟优选：对已获取并去重后的节点做 TCP 连接延迟测试，保留前 N 名写入新文件
    SUB_LATENCY_TOPN: int = Field(default=100, ge=1, le=100000)
    SUB_LATENCY_OUTPUT_FILE: str = "addressesapi_top.txt"
    SUB_LATENCY_TIMEOUT: float = Field(default=2.0, ge=0.1, le=30.0)
    SUB_LATENCY_WORKERS: int = Field(default=50, ge=1, le=1000)

    # ==================== 自动调度 ====================
    # 是否启用定时自动执行（一键全部执行）
    AUTO_SCHEDULE_ENABLED: bool = False
    # 调度间隔（小时），最小 0.5
    AUTO_SCHEDULE_INTERVAL_HOURS: float = Field(default=6.0, ge=0.5, le=720.0)

    # ==================== 可用性检测 ====================
    TEST_AVAILABILITY: bool = True
    AVAILABILITY_CHECK_API: str = "https://api.090227.xyz/check"
    AVAILABILITY_TIMEOUT: int = Field(default=3, ge=1, le=30)
    AVAILABILITY_CONNECT_TIMEOUT: int = Field(default=3, ge=1, le=30)
    AVAILABILITY_RETRY_MAX: int = Field(default=2, ge=0, le=5)
    AVAILABILITY_RETRY_DELAY: int = Field(default=3, ge=0, le=60)

    # ==================== 带宽测速 ====================
    BANDWIDTH_SIZE_MB: float = Field(default=0.5, gt=0, le=100)
    BANDWIDTH_TIMEOUT: int = Field(default=30, ge=5, le=300)
    BANDWIDTH_RETRY_MAX: int = Field(default=2, ge=0, le=5)
    BANDWIDTH_RETRY_DELAY: int = Field(default=3, ge=0, le=60)
    BANDWIDTH_URL_TEMPLATE: str = "https://speed.cloudflare.com/__down?bytes={bytes}"
    BANDWIDTH_PROCESS_BUFFER: int = Field(default=5, ge=1, le=60)
    BANDWIDTH_CONNECT_TIMEOUT: int = Field(default=3, ge=1, le=30)

    # ==================== 并发控制 ====================
    MAX_WORKERS: int = Field(default=200, ge=1, le=3000)
    AVAILABILITY_WORKERS: int = Field(default=500, ge=1, le=3000)
    FALLBACK_WORKERS: int = Field(default=32, ge=1, le=500)
    BANDWIDTH_WORKERS: int = Field(default=10, ge=1, le=200)

    # ==================== 重试策略 ====================
    DNS_UPDATE_MAX_RETRIES: int = Field(default=3, ge=0, le=10)
    DNS_UPDATE_RETRY_DELAY: int = Field(default=3, ge=0, le=60)
    GITHUB_SYNC_MAX_RETRIES: int = Field(default=3, ge=0, le=10)
    GITHUB_SYNC_RETRY_DELAY: int = Field(default=3, ge=0, le=60)
    GIT_SYNC_PROCESS_TIMEOUT: int = Field(default=180, ge=30, le=600)

    # ==================== 广告植入 ====================
    AD_HEADER_ENABLED: bool = False
    AD_HEADER_LINES: list[str] = Field(
        default_factory=lambda: ["0.0.0.0:443#格式 或纯文本1", "0.0.0.0:443#格式 或纯文本2"]
    )
    AD_FOOTER_ENABLED: bool = False
    AD_FOOTER_LINES: list[str] = Field(
        default_factory=lambda: ["0.0.0.0:443#格式 或纯文本3", "0.0.0.0:443#格式 或纯文本4"]
    )
    AD_PERLINE_ENABLED: bool = False
    AD_PERLINE_TEXT: str = " 纯文本"

    # ==================== ip.txt 输出控制 ====================
    IP_TXT_SHOW_BANDWIDTH: bool = True
    IP_TXT_SHOW_LATENCY: bool = True

    @field_validator("DNS_RECORD_TYPE")
    @classmethod
    def validate_dns_record_type(cls, v: str) -> str:
        v = v.upper()
        if v not in ("A", "TXT"):
            raise ValueError("DNS_RECORD_TYPE 必须是 A 或 TXT")
        return v

    @field_validator("DNS_IP_RISK_MAX_LEVEL")
    @classmethod
    def validate_risk_level(cls, v: str) -> str:
        valid_levels = ["极度纯净", "纯净", "轻微风险", "高风险", "极度危险"]
        if v not in valid_levels:
            raise ValueError(f"DNS_IP_RISK_MAX_LEVEL 必须是: {', '.join(valid_levels)}")
        return v

    @field_validator("PRE_FILTER_PORTS", mode="before")
    @classmethod
    def parse_ports(cls, v: Any) -> list[int]:
        if isinstance(v, str):
            return [int(x.strip()) for x in v.split(",")]
        if isinstance(v, list):
            return [int(x) for x in v]
        return []

    @field_validator("ASN_SOURCES", mode="before")
    @classmethod
    def parse_asn(cls, v: Any) -> list[int]:
        if isinstance(v, str):
            return [int(x.strip()) for x in v.split(",") if x.strip()]
        if isinstance(v, list):
            return [int(x) for x in v]
        return []

    @field_validator("ASN_SOURCE_COUNTRY")
    @classmethod
    def validate_asn_country(cls, v: str) -> str:
        v = v.strip().upper()
        if len(v) != 2 or not v.isalpha():
            raise ValueError("ASN_SOURCE_COUNTRY 必须是两位国家码 (例如 US、JP)")
        return v

    @field_validator("SUB_DEFAULT_COUNTRY")
    @classmethod
    def validate_sub_default_country(cls, v: str) -> str:
        v = v.strip().upper()
        if len(v) != 2 or not v.isalpha():
            raise ValueError("SUB_DEFAULT_COUNTRY 必须是两位国家码 (例如 UN、US)")
        return v

    @field_validator("SUB_INPUT_MODE")
    @classmethod
    def validate_sub_input_mode(cls, v: str) -> str:
        v = v.strip().lower()
        if v not in ("node", "url", "both"):
            raise ValueError("SUB_INPUT_MODE 必须是 'node'、'url' 或 'both'")
        return v

    @model_validator(mode="after")
    def validate_quotas(self) -> Config:
        if self.PER_COUNTRY_QUOTA:
            for country, quota in self.PER_COUNTRY_QUOTA.items():
                if quota < 0:
                    raise ValueError(f"PER_COUNTRY_QUOTA[{country}] 不能为负数")
        return self


def load_config(config_path: str | Path | None = None) -> Config:
    """加载配置文件，支持环境变量覆盖"""
    if config_path is None:
        # Resolve config.json from CWD, fallback to project root
        c_cwd = Path.cwd() / "config.json"
        if c_cwd.exists():
            config_path = c_cwd
        else:
            config_path = Path(__file__).parent.parent.parent / "config.json"

    config_path = Path(config_path)
    if not config_path.exists():
        raise FileNotFoundError(f"配置文件不存在: {config_path}")

    with open(config_path, encoding="utf-8") as f:
        data = json.load(f)

    # 过滤掉注释字段（以 _comment 开头的键）
    filtered_data = {k: v for k, v in data.items() if not k.startswith("_comment")}

    return Config(**filtered_data)


# 全局配置实例（延迟加载）
_config: Config | None = None


def get_config() -> Config:
    """获取全局配置实例（单例模式）"""
    global _config
    if _config is None:
        _config = load_config()
    return _config


def reload_config(config_path: str | Path | None = None) -> Config:
    """重新加载配置"""
    global _config
    _config = load_config(config_path)
    return _config
