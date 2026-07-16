"""测试配置加载和验证"""

import os
import tempfile

import pytest

from cfnb.config import Config, load_config


def test_config_defaults():
    """测试默认配置值"""
    data = {}
    cfg = Config(**data)

    assert cfg.USE_GLOBAL_MODE is True
    assert cfg.GLOBAL_TOP_N == 15
    assert cfg.TCP_PROBES == 1
    assert cfg.MIN_SUCCESS_RATE == 1.0
    assert cfg.TIMEOUT == 2.0


def test_config_validation_global_top_n():
    """测试 GLOBAL_TOP_N 验证"""
    with pytest.raises(ValueError):
        Config(GLOBAL_TOP_N=0)
    with pytest.raises(ValueError):
        Config(GLOBAL_TOP_N=201)
    # 合法值
    cfg = Config(GLOBAL_TOP_N=50)
    assert cfg.GLOBAL_TOP_N == 50


def test_config_validation_min_success_rate():
    """测试 MIN_SUCCESS_RATE 验证"""
    with pytest.raises(ValueError):
        Config(MIN_SUCCESS_RATE=-0.1)
    with pytest.raises(ValueError):
        Config(MIN_SUCCESS_RATE=1.1)
    cfg = Config(MIN_SUCCESS_RATE=0.5)
    assert cfg.MIN_SUCCESS_RATE == 0.5


def test_config_validation_dns_record_type():
    """测试 DNS_RECORD_TYPE 验证"""
    with pytest.raises(ValueError):
        Config(DNS_RECORD_TYPE="CNAME")
    cfg = Config(DNS_RECORD_TYPE="A")
    assert cfg.DNS_RECORD_TYPE == "A"
    cfg = Config(DNS_RECORD_TYPE="TXT")
    assert cfg.DNS_RECORD_TYPE == "TXT"
    # 大小写不敏感
    cfg = Config(DNS_RECORD_TYPE="a")
    assert cfg.DNS_RECORD_TYPE == "A"


def test_config_validation_risk_level():
    """测试 DNS_IP_RISK_MAX_LEVEL 验证"""
    with pytest.raises(ValueError):
        Config(DNS_IP_RISK_MAX_LEVEL="未知等级")
    cfg = Config(DNS_IP_RISK_MAX_LEVEL="纯净")
    assert cfg.DNS_IP_RISK_MAX_LEVEL == "纯净"


def test_config_pre_filter_ports_parsing():
    """测试端口解析"""
    cfg = Config(PRE_FILTER_PORTS="443,80,8080")
    assert cfg.PRE_FILTER_PORTS == [443, 80, 8080]
    cfg = Config(PRE_FILTER_PORTS=[443, 80])
    assert cfg.PRE_FILTER_PORTS == [443, 80]


def test_config_quota_validation():
    """测试配额验证"""
    with pytest.raises(ValueError):
        Config(PER_COUNTRY_QUOTA={"US": -1})
    cfg = Config(PER_COUNTRY_QUOTA={"US": 5, "JP": 3})
    assert cfg.PER_COUNTRY_QUOTA == {"US": 5, "JP": 3}


def test_config_gui_and_schedule_fields():
    """新增的外观主题 / 自动调度字段有合理默认值与校验"""
    cfg = Config()
    assert cfg.GUI_THEME in ("light", "dark")
    assert cfg.AUTO_SCHEDULE_ENABLED is False
    assert cfg.AUTO_SCHEDULE_INTERVAL_HOURS >= 0.5
    with pytest.raises(ValueError):
        Config(GUI_THEME="neon")
    with pytest.raises(ValueError):
        Config(AUTO_SCHEDULE_INTERVAL_HOURS=0.1)
    assert cfg.SUB_DISABLED_GENERATORS == set()


def test_load_config_from_file():
    """测试从文件加载配置"""
    config_content = {
        "USE_GLOBAL_MODE": False,
        "GLOBAL_TOP_N": 20,
        "TCP_PROBES": 5,
        "MIN_SUCCESS_RATE": 0.8,
        "TIMEOUT": 3.0,
        "ADDITIONAL_SOURCES": [{"url": "https://example.com/ips.txt", "enabled": True}],
        # 必填字段使用占位符
        "WXPUSHER_APP_TOKEN": "test_token",
        "WXPUSHER_UIDS": ["test_uid"],
        "CF_API_TOKEN": "test_cf_token",
        "CF_ZONE_ID": "test_zone",
        "CF_DNS_RECORD_NAME": "test.example.com",
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        import json

        json.dump(config_content, f)
        temp_path = f.name

    try:
        cfg = load_config(temp_path)
        assert cfg.USE_GLOBAL_MODE is False
        assert cfg.GLOBAL_TOP_N == 20
        assert cfg.TCP_PROBES == 5
        assert cfg.MIN_SUCCESS_RATE == 0.8
        assert cfg.TIMEOUT == 3.0
        assert len(cfg.ADDITIONAL_SOURCES) == 1
        assert cfg.ADDITIONAL_SOURCES[0].url == "https://example.com/ips.txt"
    finally:
        os.unlink(temp_path)


def test_load_config_ignores_comments():
    """测试忽略注释字段"""
    config_content = {
        "USE_GLOBAL_MODE": True,
        "_comment_USE_GLOBAL_MODE": "这是注释",
        "_comment": "这是另一个注释",
        "GLOBAL_TOP_N": 10,
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        import json

        json.dump(config_content, f)
        temp_path = f.name

    try:
        cfg = load_config(temp_path)
        assert cfg.USE_GLOBAL_MODE is True
        assert cfg.GLOBAL_TOP_N == 10
    finally:
        os.unlink(temp_path)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
