"""测试订阅转换模块"""

import base64
import json

from cfnb.config import Config
from cfnb.subscription import (
    _parse_uri_style,
    _parse_vmess,
    collect_subscription_tasks,
    decode_subscription,
    generator_fetch_urls,
    parse_generator,
    parse_subscription_links,
)


def _b64(s: str) -> str:
    return base64.b64encode(s.encode("utf-8")).decode("ascii")


class TestDecodeSubscription:
    """测试订阅内容解码"""

    def test_plaintext_passthrough(self):
        text = "vless://uuid@1.2.3.4:443#US"
        assert decode_subscription(text) == text

    def test_base64_decode(self):
        raw = "vless://uuid@1.2.3.4:443#US\ntrojan://pass@5.6.7.8:8443#JP"
        encoded = _b64(raw)
        assert decode_subscription(encoded) == raw

    def test_empty(self):
        assert decode_subscription("") == ""


class TestParseVmess:
    """测试 vmess 链接解析"""

    def test_basic(self):
        payload = json.dumps({"add": "1.2.3.4", "port": "443", "ps": "美国节点"})
        link = "vmess://" + _b64(payload)
        assert _parse_vmess(link) == ("1.2.3.4", 443, "美国节点")

    def test_invalid(self):
        assert _parse_vmess("vmess://not_base64_json") is None


class TestParseUriStyle:
    """测试 vless/trojan/ss 链接解析"""

    def test_vless(self):
        link = "vless://uuid@1.2.3.4:443?encryption=none&type=ws#🇺🇸美国"
        host, port, name = _parse_uri_style(link)
        assert host == "1.2.3.4"
        assert port == 443
        assert "美国" in name

    def test_trojan(self):
        link = "trojan://password@example.com:8443?sni=x#JP-Tokyo"
        host, port, name = _parse_uri_style(link)
        assert host == "example.com"
        assert port == 8443
        assert name == "JP-Tokyo"

    def test_missing_port(self):
        assert _parse_uri_style("vless://uuid@1.2.3.4#US") is None


class TestParseSubscriptionLinks:
    """测试整体订阅解析"""

    def test_mixed(self):
        vmess = "vmess://" + _b64(json.dumps({"add": "9.9.9.9", "port": 443, "ps": "HK"}))
        text = "\n".join(
            [
                "vless://uuid@1.2.3.4:443#US",
                "trojan://pass@5.6.7.8:8443#JP",
                vmess,
                "# comment line ignored",
                "ss://invalidscheme",
            ]
        )
        results = parse_subscription_links(text)
        hosts = {r[0] for r in results}
        assert "1.2.3.4" in hosts
        assert "5.6.7.8" in hosts
        assert "9.9.9.9" in hosts


class TestParseGenerator:
    """测试候选订阅器条目解析"""

    def test_name_and_host(self):
        assert parse_generator("CM|sub.cmliussss.net") == ("CM", "sub.cmliussss.net")

    def test_host_only(self):
        assert parse_generator("sub.us.ci") == ("sub.us.ci", "sub.us.ci")


class TestGeneratorFetchUrls:
    """测试为候选订阅器构造候选拉取 URL"""

    def test_order(self):
        cfg = Config(
            SUB_NODE_HOST="x.pages.dev",
            SUB_NODE_UUID="abc-123",
        )
        urls = generator_fetch_urls("sub.cmliussss.net", cfg)
        assert urls[0] == "https://sub.cmliussss.net/sub?host=x.pages.dev&uuid=abc-123"
        assert urls[1] == "https://sub.cmliussss.net/auto"
        assert urls[2] == "https://sub.cmliussss.net/sub?token=auto"

    def test_strips_scheme(self):
        cfg = Config()
        urls = generator_fetch_urls("https://sub.us.ci/", cfg)
        assert urls[0].startswith("https://sub.us.ci/sub?")

    def test_direct_url_mode(self):
        cfg = Config()
        # 含路径的完整订阅 URL -> 原样返回（不再拼 /sub、/auto）
        urls = generator_fetch_urls("https://sub.mia.xx.kg/abcdef", cfg)
        assert urls == ["https://sub.mia.xx.kg/abcdef"]
        # 无路径的域名 -> 仍按生成器处理（拼 /sub 等）
        urls2 = generator_fetch_urls("sub.us.ci", cfg)
        assert urls2[0].startswith("https://sub.us.ci/sub?")


class TestCollectSubscriptionTasks:
    """测试根据输入模式收集任务"""

    def test_node_mode(self):
        cfg = Config(
            SUB_INPUT_MODE="node",
            SUB_GENERATORS=["CM|sub.cmliussss.net", "sub.us.ci"],
            SUB_NODE_HOST="x.pages.dev",
            SUB_NODE_UUID="abc",
        )
        tasks = collect_subscription_tasks(cfg)
        assert len(tasks) == 2
        assert tasks[0][0] == "CM"
        assert tasks[0][1][0].startswith("https://sub.cmliussss.net/sub?host=x.pages.dev&uuid=abc")

    def test_node_mode_empty(self):
        cfg = Config(SUB_INPUT_MODE="node", SUB_GENERATORS=[])
        assert collect_subscription_tasks(cfg) == []

    def test_url_mode(self):
        cfg = Config(
            SUB_INPUT_MODE="url",
            SUB_URLS=["https://a.com/sub", "https://b.com/sub"],
        )
        tasks = collect_subscription_tasks(cfg)
        assert tasks == [("url", ["https://a.com/sub", "https://b.com/sub"])]

    def test_both_mode(self):
        cfg = Config(
            SUB_INPUT_MODE="both",
            SUB_GENERATORS=["CM|sub.cmliussss.net"],
            SUB_URLS=["https://a.com/sub", "vless://abc@1.2.3.4:443#x"],
            SUB_NODE_HOST="x.pages.dev",
            SUB_NODE_UUID="abc",
        )
        tasks = collect_subscription_tasks(cfg)
        # 定位器 + 现成订阅(含直接节点链接) 都应被收集
        names = [t[0] for t in tasks]
        assert "CM" in names
        assert "url" in names
        # 直接节点链接也进入了 url 任务
        assert "vless://abc@1.2.3.4:443#x" in tasks[-1][1]

    def test_disabled_generators_skipped(self):
        cfg = Config(
            SUB_INPUT_MODE="both",
            SUB_GENERATORS=["CM|sub.cmliussss.net", "IDK|sub.pjq.cc"],
            SUB_DISABLED_GENERATORS={"IDK"},
        )
        tasks = collect_subscription_tasks(cfg)
        names = [t[0] for t in tasks]
        assert "CM" in names
        assert "IDK" not in names

    def test_generators_state_roundtrip(self, tmp_path, monkeypatch):
        import cfnb.subscription as sub
        monkeypatch.setattr(sub, "_gen_state_path", lambda: tmp_path / "gen_state.json")
        sub.save_generators_state({"CM": {"ok": True, "nodes": 10, "ts": 1.0}})
        loaded = sub.load_generators_state()
        assert loaded["CM"]["ok"] is True
        assert loaded["CM"]["nodes"] == 10


class TestConvertDedup:
    """测试 convert_subscriptions 的去重（按 IP 去重，同 IP 只保留第一条）"""

    def test_dedup_same_ip_different_port(self, monkeypatch):
        from cfnb import subscription as sub
        cfg = Config(SUB_RESOLVE_DOMAIN=False, SUB_DEFAULT_COUNTRY="UN")
        subs = {
            "g1": base64.b64encode(
                "vless://abc@1.2.3.4:443#JP-1\nvless://abc@1.2.3.4:8443#JP-2".encode()
            ).decode(),
            "g2": base64.b64encode("vless://abc@1.2.3.4:2083#US-3".encode()).decode(),
        }
        monkeypatch.setattr(sub, "fetch_first_working", lambda urls, c: subs[urls[0]])
        # collect 返回的 task = (name, urls)，这里用 URL 串作为内容键
        monkeypatch.setattr(
            sub, "collect_subscription_tasks", lambda c: [("g1", ["g1"]), ("g2", ["g2"])]
        )

        nodes, _ = sub.convert_subscriptions(cfg)
        # 三个节点同 IP 不同端口 -> 只留第一条
        assert len(nodes) == 1
        assert nodes[0].startswith("1.2.3.4:443#")

    def test_dedup_exact_duplicate(self, monkeypatch):
        from cfnb import subscription as sub
        cfg = Config(SUB_RESOLVE_DOMAIN=False, SUB_DEFAULT_COUNTRY="UN")
        subs = {
            "g1": base64.b64encode(
                "vless://abc@1.2.3.4:443#JP-1\nvless://abc@1.2.3.4:443#JP-2".encode()
            ).decode(),
        }
        monkeypatch.setattr(sub, "fetch_first_working", lambda urls, c: subs[urls[0]])
        monkeypatch.setattr(sub, "collect_subscription_tasks", lambda c: [("g1", ["g1"])])
        nodes, _ = sub.convert_subscriptions(cfg)
        assert len(nodes) == 1


    def test_source_mapping(self, monkeypatch):
        from cfnb import subscription as sub

        cfg = Config(SUB_RESOLVE_DOMAIN=False, SUB_DEFAULT_COUNTRY="UN")
        links = "vless://abc@1.2.3.4:443#JP\nvless://abc@5.6.7.8:8443#US"
        monkeypatch.setattr(sub, "fetch_first_working", lambda urls, c: links)
        monkeypatch.setattr(
            sub, "collect_subscription_tasks", lambda c: [("IDK", ["x"])]
        )
        nodes, node_source = sub.convert_subscriptions(cfg)
        assert set(nodes) == {"1.2.3.4:443#JP", "5.6.7.8:8443#US"}
        # 每个节点都标注了来源名
        assert all(node_source[n] == "IDK" for n in nodes)


class TestResolveSubUrl:
    """测试 sub://BASE64 分享链接的解码"""

    def test_sub_scheme(self):
        from cfnb import subscription as sub
        inner = "https://sub.example.com/abcdef"
        link = "sub://" + base64.b64encode(inner.encode()).decode()
        assert sub._resolve_sub_url(link) == inner

    def test_https_passthrough(self):
        from cfnb import subscription as sub
        assert sub._resolve_sub_url("https://a.com/sub") == "https://a.com/sub"


class TestFetchFirstWorking:
    """测试 fetch_first_working 对多种输入的处理"""

    def test_raw_vless_link_used_directly(self, monkeypatch):
        from cfnb import subscription as sub
        cfg = Config(SUB_RESOLVE_DOMAIN=False, SUB_DEFAULT_COUNTRY="UN")
        link = "vless://abc@1.2.3.4:443#JP"
        # 直接节点链接不应触发网络抓取，应原样作为订阅原文解析
        captured = {}
        monkeypatch.setattr(
            sub, "fetch_subscription", lambda u, c: captured.setdefault("called", u)
        )
        content = sub.fetch_first_working([link], cfg)
        assert "called" not in captured  # 未发起网络请求
        assert content == link

    def test_raw_link_in_convert(self, monkeypatch):
        from cfnb import subscription as sub
        cfg = Config(SUB_RESOLVE_DOMAIN=False, SUB_DEFAULT_COUNTRY="UN")
        link = "vless://abc@1.2.3.4:443#JP"
        monkeypatch.setattr(sub, "fetch_first_working", lambda urls, c: link)
        monkeypatch.setattr(
            sub, "collect_subscription_tasks", lambda c: [("url", [link])]
        )
        nodes, _ = sub.convert_subscriptions(cfg)
        assert nodes == ["1.2.3.4:443#JP"]
