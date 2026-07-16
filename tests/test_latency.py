"""测试延迟优选模块"""

from cfnb import latency as lat
from cfnb.config import Config


def test_parse_endpoint_ipv4():
    assert lat.parse_endpoint("1.2.3.4:443#JP") == ("1.2.3.4", 443)
    assert lat.parse_endpoint("1.2.3.4:443") == ("1.2.3.4", 443)


def test_parse_endpoint_ipv6():
    assert lat.parse_endpoint("[::1]:443#UN") == ("::1", 443)


def test_parse_endpoint_invalid():
    assert lat.parse_endpoint("not-a-node") is None
    assert lat.parse_endpoint("1.2.3.4:abc#JP") is None
    assert lat.parse_endpoint("") is None


def test_latency_filter_keeps_topn(tmp_path, monkeypatch):
    # 用确定性的延迟值替换真实 TCP 测量
    def fake(ip, port, timeout):
        return {
            ("1.1.1.1", 443): 0.05,
            ("2.2.2.2", 443): 0.20,
            ("3.3.3.3", 443): 0.10,
            ("4.4.4.4", 9999): None,  # 不可达
        }.get((ip, port), 0.5)

    monkeypatch.setattr(lat, "measure_latency", fake)

    inp = tmp_path / "in.txt"
    inp.write_text(
        "1.1.1.1:443#US\n2.2.2.2:443#US\n3.3.3.3:443#US\n4.4.4.4:9999#US\n",
        encoding="utf-8",
    )
    out = tmp_path / "out.txt"

    kept, tested, ok = lat.latency_filter(str(inp), str(out), 4, 1.0, 4)
    # 按延迟升序，不可达排最后
    assert tested == 4
    assert ok == 3
    assert kept == [
        "1.1.1.1:443#US",
        "3.3.3.3:443#US",
        "2.2.2.2:443#US",
        "4.4.4.4:9999#US",
    ]
    assert len(kept) == 4

    lines = out.read_text(encoding="utf-8").splitlines()
    # 第 0 行为生成时间注释头，之后为数据行（附带延迟 ms / 超时）
    assert lines[0].startswith("# 延迟优选结果 @")
    assert lines[1] == "1.1.1.1:443#US 50.00 ms"
    assert lines[2] == "3.3.3.3:443#US 100.00 ms"
    assert lines[3] == "2.2.2.2:443#US 200.00 ms"
    assert lines[4] == "4.4.4.4:9999#US 超时"

    # 同时生成结构化 JSON（含来源统计）
    import json
    j = json.loads((tmp_path / "out.json").read_text(encoding="utf-8"))
    assert j["tested"] == 4 and j["connected"] == 3 and j["kept"] == 4
    assert j["nodes"][0]["latency_ms"] == 50.0
    assert j["nodes"][3]["latency_ms"] is None


def test_latency_filter_topn_exceeds_available(tmp_path, monkeypatch):
    monkeypatch.setattr(lat, "measure_latency", lambda ip, port, t: 0.1)
    inp = tmp_path / "in.txt"
    inp.write_text("1.1.1.1:443#US\n2.2.2.2:443#US\n", encoding="utf-8")
    out = tmp_path / "out.txt"

    kept, tested, ok = lat.latency_filter(str(inp), str(out), 100, 1.0, 4)
    assert kept == ["1.1.1.1:443#US", "2.2.2.2:443#US"]


def test_config_latency_defaults():
    cfg = Config()
    assert cfg.SUB_LATENCY_TOPN == 100
    assert cfg.SUB_LATENCY_OUTPUT_FILE == "addressesapi_top.txt"
    assert cfg.SUB_LATENCY_TIMEOUT == 2.0
    assert cfg.SUB_LATENCY_WORKERS == 50


def test_latency_filter_adds_source(tmp_path, monkeypatch):
    monkeypatch.setattr(lat, "measure_latency", lambda ip, port, t: 0.05)
    inp = tmp_path / "in.txt"
    inp.write_text("1.1.1.1:443#US\n2.2.2.2:443#US\n", encoding="utf-8")
    out = tmp_path / "out.txt"
    src = {"1.1.1.1:443#US": "CM", "2.2.2.2:443#US": "IDK"}

    kept, tested, ok = lat.latency_filter(str(inp), str(out), 10, 1.0, 4, src)

    assert tested == 2
    assert ok == 2
    lines = out.read_text(encoding="utf-8").splitlines()
    # 输出行在注释中标注来源（#CC@来源），首行为时间注释头
    assert lines[0].startswith("# 延迟优选结果 @")
    assert lines[1] == "1.1.1.1:443#US@CM 50.00 ms"
    assert lines[2] == "2.2.2.2:443#US@IDK 50.00 ms"
    # 返回列表仍为原始节点（不含来源后缀）
    assert kept == ["1.1.1.1:443#US", "2.2.2.2:443#US"]


def test_latency_filter_source_missing_is_omitted(tmp_path, monkeypatch):
    monkeypatch.setattr(lat, "measure_latency", lambda ip, port, t: 0.05)
    inp = tmp_path / "in.txt"
    inp.write_text("1.1.1.1:443#US\n", encoding="utf-8")
    out = tmp_path / "out.txt"

    lat.latency_filter(str(inp), str(out), 10, 1.0, 4, None)

    # 无来源映射时不追加 @来源；首行为时间注释头
    lines = out.read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("# 延迟优选结果 @")
    assert lines[1] == "1.1.1.1:443#US 50.00 ms"


def test_save_latency_history_appends(tmp_path):
    out = tmp_path / "out.txt"
    hist = lat.save_latency_history(str(out), topn_kept=100, tested=200, connected=180)
    assert hist and hist.endswith("latency_history.csv")
    text = (tmp_path / "history" / "latency_history.csv").read_text(encoding="utf-8")
    assert text.startswith("time,tested,connected,kept\n")
    assert "200,180,100" in text

    # 第二次调用应追加而非覆盖
    lat.save_latency_history(str(out), topn_kept=90, tested=200, connected=175)
    lines = (tmp_path / "history" / "latency_history.csv").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3  # header + 2 rows
