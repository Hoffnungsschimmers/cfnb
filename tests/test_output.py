"""测试输出模块"""

import os
import tempfile

from cfnb.output import write_ip_txt


def test_write_ip_txt_basic():
    """测试基本写入"""
    nodes = ["104.16.0.1:443#US", "162.159.0.1:443#JP"]
    config = type(
        "Config",
        (),
        {
            "AD_HEADER_ENABLED": False,
            "AD_FOOTER_ENABLED": False,
            "AD_PERLINE_ENABLED": False,
            "AD_PERLINE_TEXT": "",
            "IP_TXT_SHOW_BANDWIDTH": False,
            "IP_TXT_SHOW_LATENCY": False,
        },
    )()

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt", encoding="utf-8") as f:
        temp_path = f.name

    try:
        write_ip_txt(nodes, temp_path, config)
        with open(temp_path, encoding="utf-8") as f:
            content = f.read()
        assert "104.16.0.1:443#US" in content
        assert "162.159.0.1:443#JP" in content
        assert content.count("\n") == 2  # 两行
    finally:
        os.unlink(temp_path)


def test_write_ip_txt_with_header_footer():
    """测试带头部尾部广告"""
    nodes = ["104.16.0.1:443#US"]
    config = type(
        "Config",
        (),
        {
            "AD_HEADER_ENABLED": True,
            "AD_HEADER_LINES": ["# Header Ad"],
            "AD_FOOTER_ENABLED": True,
            "AD_FOOTER_LINES": ["# Footer Ad"],
            "AD_PERLINE_ENABLED": False,
            "AD_PERLINE_TEXT": "",
            "IP_TXT_SHOW_BANDWIDTH": False,
            "IP_TXT_SHOW_LATENCY": False,
        },
    )()

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt", encoding="utf-8") as f:
        temp_path = f.name

    try:
        write_ip_txt(nodes, temp_path, config)
        with open(temp_path, encoding="utf-8") as f:
            content = f.read()
        assert "# Header Ad" in content
        assert "# Footer Ad" in content
        assert content.strip().startswith("# Header Ad")
        assert content.strip().endswith("# Footer Ad")
    finally:
        os.unlink(temp_path)


def test_write_ip_txt_with_perline():
    """测试每行追加文本"""
    nodes = ["104.16.0.1:443#US", "162.159.0.1:443#JP"]
    config = type(
        "Config",
        (),
        {
            "AD_HEADER_ENABLED": False,
            "AD_FOOTER_ENABLED": False,
            "AD_PERLINE_ENABLED": True,
            "AD_PERLINE_TEXT": " # AD",
            "IP_TXT_SHOW_BANDWIDTH": False,
            "IP_TXT_SHOW_LATENCY": False,
        },
    )()

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt", encoding="utf-8") as f:
        temp_path = f.name

    try:
        write_ip_txt(nodes, temp_path, config)
        with open(temp_path, encoding="utf-8") as f:
            content = f.read()
        for line in content.strip().split("\n"):
            assert line.endswith(" # AD")
    finally:
        os.unlink(temp_path)


def test_write_ip_txt_with_bandwidth_latency():
    """测试显示带宽和延迟"""
    nodes = ["104.16.0.1:443#US", "162.159.0.1:443#JP"]
    config = type(
        "Config",
        (),
        {
            "AD_HEADER_ENABLED": False,
            "AD_FOOTER_ENABLED": False,
            "AD_PERLINE_ENABLED": False,
            "AD_PERLINE_TEXT": "",
            "IP_TXT_SHOW_BANDWIDTH": True,
            "IP_TXT_SHOW_LATENCY": True,
        },
    )()

    speed_map = {"104.16.0.1:443#US": 10.5, "162.159.0.1:443#JP": 20.3}
    latency_map = {"104.16.0.1:443#US": 0.05, "162.159.0.1:443#JP": 0.08}

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt", encoding="utf-8") as f:
        temp_path = f.name

    try:
        write_ip_txt(nodes, temp_path, config, speed_map, latency_map)
        with open(temp_path, encoding="utf-8") as f:
            content = f.read()
        assert "10.50 Mbps" in content
        assert "20.30 Mbps" in content
        assert "50.00 ms" in content  # 0.05 * 1000
        assert "80.00 ms" in content  # 0.08 * 1000
    finally:
        os.unlink(temp_path)


if __name__ == "__main__":
    import pytest

    pytest.main([__file__, "-v"])
