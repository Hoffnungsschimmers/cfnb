"""测试节点获取与解析模块"""

import pytest

from cfnb.fetcher import (
    _parse_json_nodes,
    extract_country_code,
    parse_adaptive,
)


class TestExtractCountryCode:
    """测试国家代码提取"""

    def test_direct_mapping(self):
        """测试直接映射"""
        assert extract_country_code("US") == "US"
        assert extract_country_code("CN") == "CN"
        assert extract_country_code("香港") == "HK"
        assert extract_country_code("日本") == "JP"
        assert extract_country_code("美国") == "US"

    def test_standard_format(self):
        """测试标准格式 IP:port#国家代码"""
        # 标准格式在 parse_adaptive 中处理，这里测试 label 解析
        assert extract_country_code("US") == "US"
        assert extract_country_code("JP-01") == "JP"
        assert extract_country_code("US-LAX") == "US"

    def test_chinese_names(self):
        """测试中文名称"""
        assert extract_country_code("新加坡") == "SG"
        assert extract_country_code("韩国") == "KR"
        assert extract_country_code("台湾") == "TW"
        assert extract_country_code("中国香港") == "HK"

    def test_alpha3_codes(self):
        """测试三位字母代码"""
        assert extract_country_code("USA") == "US"
        assert extract_country_code("JPN") == "JP"
        assert extract_country_code("KOR") == "KR"
        assert extract_country_code("SGP") == "SG"

    def test_emoji_flags(self):
        """测试 emoji 国旗"""
        # 🇺🇸 = US, 🇯🇵 = JP, 🇭🇰 = HK, 🇸🇬 = SG
        assert extract_country_code("🇺🇸") == "US"
        assert extract_country_code("🇯🇵") == "JP"
        assert extract_country_code("🇭🇰") == "HK"
        assert extract_country_code("🇸🇬") == "SG"

    def test_mixed_formats(self):
        """测试混合格式"""
        assert extract_country_code("CF 移动优选") == "CN"
        assert extract_country_code("CM-Default") == "CN"
        assert extract_country_code("联通-LAX-443") == "CN"
        assert extract_country_code("电信") == "CN"
        assert extract_country_code("泡菜欧巴") == "KR"
        assert extract_country_code("西贡咖啡") == "VN"

    def test_empty_and_invalid(self):
        """测试空值和无效值"""
        assert extract_country_code("") is None
        assert extract_country_code("   ") is None
        assert extract_country_code("INVALID") is None
        assert extract_country_code("XX") is None  # 无效国家代码


class TestParseAdaptive:
    """测试自适应解析"""

    def test_parse_standard_format(self):
        """测试标准格式解析"""
        text = """104.16.0.1:443#US
162.159.0.1:443#JP
172.64.0.1:443#HK"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 3
        assert "104.16.0.1:443#US" in nodes
        assert "162.159.0.1:443#JP" in nodes
        assert "172.64.0.1:443#HK" in nodes

    def test_parse_with_chinese_labels(self):
        """测试带中文标签的解析"""
        text = """104.16.0.1:443#美国
162.159.0.1:443#日本
172.64.0.1:443#香港"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 3
        assert "104.16.0.1:443#US" in nodes
        assert "162.159.0.1:443#JP" in nodes
        assert "172.64.0.1:443#HK" in nodes

    def test_parse_with_emoji(self):
        """测试带 emoji 的解析"""
        text = """104.16.0.1:443#🇺🇸
162.159.0.1:443#🇯🇵"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 2
        assert "104.16.0.1:443#US" in nodes
        assert "162.159.0.1:443#JP" in nodes

    def test_parse_json_array(self):
        """测试 JSON 数组解析"""
        text = """[
            {"ip": "104.16.0.1", "port": 443, "country": "US"},
            {"ip": "162.159.0.1", "port": 443, "country": "JP"}
        ]"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 2
        assert "104.16.0.1:443#US" in nodes
        assert "162.159.0.1:443#JP" in nodes

    def test_parse_json_with_nodes_key(self):
        """测试带 nodes 键的 JSON"""
        text = """{
            "nodes": [
                {"ip": "104.16.0.1", "port": 443, "country": "US"},
                {"ip": "162.159.0.1", "port": 443, "country": "JP"}
            ]
        }"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 2

    def test_parse_skip_comments(self):
        """测试跳过注释行"""
        text = """# 这是注释
// 这也是注释
104.16.0.1:443#US
162.159.0.1:443#JP"""
        nodes = parse_adaptive(text)
        assert len(nodes) == 2

    def test_parse_bare_ip(self):
        """测试裸 IP（无国家代码时不产生节点，避免错误标记）"""
        text = """104.16.0.1
162.159.0.1"""
        nodes = parse_adaptive(text)
        # 无法识别国家代码的裸 IP 不应加入节点列表
        assert len(nodes) == 0

    def test_parse_bare_domain(self):
        """测试裸域名（自动补 443 端口）"""
        text = "example.com"
        parse_adaptive(text)
        # 域名解析会失败，所以返回空
        # 这个测试主要确保不报错


class TestParseJsonNodes:
    """测试 JSON 节点解析"""

    def test_parse_list_of_objects(self):
        data = [{"ip": "1.1.1.1", "port": 443, "country": "US"}, {"ip": "2.2.2.2", "port": 443, "country": "JP"}]
        nodes = _parse_json_nodes(data)
        assert len(nodes) == 2
        assert "1.1.1.1:443#US" in nodes

    def test_parse_nested_nodes_key(self):
        data = {"nodes": [{"ip": "1.1.1.1", "port": 443, "country": "US"}]}
        nodes = _parse_json_nodes(data)
        assert len(nodes) == 1

    def test_parse_dict_with_different_keys(self):
        data = {"host": "1.1.1.1", "port": 443, "cc": "US"}
        nodes = _parse_json_nodes(data)
        assert len(nodes) == 1
        assert "1.1.1.1:443#US" in nodes


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
