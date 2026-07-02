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
        env_file=str(Path(__file__).parent / "scripts" / ".env.local"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ==================== 筛选模式与数量控制 ====================
    USE_GLOBAL_MODE: bool = True
    GLOBAL_TOP_N: int = Field(default=15, ge=1, le=200)
    PER_COUNTRY_TOP_N: int = Field(default=1, ge=1, le=50)
    PER_COUNTRY_QUOTA: dict[str, int] = Field(default_factory=dict)
    BANDWIDTH_CANDIDATES: int = Field(default=1000, ge=1, le=10000)
    DNS_UPDATE_TARGET_COUNT: int = Field(default=15, ge=1, le=200)

    # ==================== TCP 连接测试参数 ====================
    TCP_PROBES: int = Field(default=3, ge=1, le=10)
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
    MAX_WORKERS: int = Field(default=200, ge=1, le=1000)
    AVAILABILITY_WORKERS: int = Field(default=32, ge=1, le=500)
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
    IP_TXT_SHOW_BANDWIDTH: bool = False
    IP_TXT_SHOW_LATENCY: bool = False

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
        config_path = Path(__file__).parent / "config.json"

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
