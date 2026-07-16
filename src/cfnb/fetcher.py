"""节点数据获取与解析模块"""

from __future__ import annotations

import json
import os
import re
import socket
import time
import ipaddress
from typing import Any

import asyncio
import httpx

from cfnb.config import Config

# 预编译正则
NODE_PATTERN = re.compile(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#(.+)$")
IP_PORT_PATTERN = re.compile(r"^(\d+\.\d+\.\d+\.\d+):(\d+)#")

# ==================== 国家代码映射表 ====================
import json
from pathlib import Path

CN_TO_CODE = {}
ALPHA3_TO_ALPHA2 = {}

try:
    _json_path = Path(__file__).parent / "country_codes.json"
    with open(_json_path, encoding="utf-8") as _f:
        _data = json.load(_f)
        CN_TO_CODE = _data["CN_TO_CODE"]
        ALPHA3_TO_ALPHA2 = _data["ALPHA3_TO_ALPHA2"]
except Exception as e:
    print(f"警告：无法加载国家代码映射文件 country_codes.json: {e}")

CODE_SET = set(CN_TO_CODE.values())


def extract_country_code(label: str) -> str | None:
    """从任意标签中提取标准两位国家代码"""
    label = label.strip()
    if not label:
        return None

    direct = CN_TO_CODE.get(label)
    if direct:
        return direct

    tokens = re.split(r"[\s,;|/\-]+", label)

    for token in tokens:
        token_cleaned = re.sub(r"[\U0001F1E6-\U0001F1FF]", "", token.strip())
        cn_match = re.match(r"^([\u4e00-\u9fff（）()]+)\d*$", token_cleaned)
        if cn_match:
            cn_name = cn_match.group(1).strip()
            code = CN_TO_CODE.get(cn_name)
            if code:
                return code

    for token in tokens:
        token_cleaned = re.sub(r"^[\d\s\-_.|#]+", "", token.strip())
        m3 = re.match(r"^([A-Z]{3})(?![A-Za-z])", token_cleaned)
        if m3 and m3.group(1) in ALPHA3_TO_ALPHA2:
            return ALPHA3_TO_ALPHA2[m3.group(1)]
        m2 = re.match(r"^([A-Z]{2})(?![A-Za-z])", token_cleaned)
        if m2 and m2.group(1) in CODE_SET:
            return m2.group(1)

    for token in tokens:
        token_cleaned = re.sub(r"^[\d\s\-_.|#]+", "", token)
        token_no_emoji = re.sub(r"[\U0001F1E6-\U0001F1FF]", "", token_cleaned).strip()
        cn_match = re.match(r"^([\u4e00-\u9fff（）()]+)\d*$", token_no_emoji)
        if cn_match:
            cn_name = cn_match.group(1).strip()
            code = CN_TO_CODE.get(cn_name)
            if code:
                return code

    emoji_chars = [c for c in label if "\U0001f1e6" <= c <= "\U0001f1ff"]
    if len(emoji_chars) >= 2 and len(emoji_chars) % 2 == 0:
        first = ord(emoji_chars[0]) - 0x1F1E6
        second = ord(emoji_chars[1]) - 0x1F1E6
        if 0 <= first <= 25 and 0 <= second <= 25:
            return chr(first + ord("A")) + chr(second + ord("A"))

    return None


def _parse_json_nodes(data: Any) -> list[str]:
    """从 JSON 结构中递归提取节点"""
    nodes = []
    if isinstance(data, list):
        for item in data:
            nodes.extend(_parse_json_nodes(item))
    elif isinstance(data, dict):
        for key in ("nodes", "data", "result", "list"):
            if key in data and isinstance(data[key], list):
                nodes.extend(_parse_json_nodes(data[key]))
                break
        ip = data.get("ip") or data.get("host")
        port = data.get("port")
        code = data.get("country") or data.get("cc")
        if ip and port and code:
            nodes.append(f"{ip}:{port}#{code.upper()}")
    elif isinstance(data, str):
        nodes.extend(_parse_text_nodes(data))
    return nodes


def _parse_text_nodes(text: str) -> list[str]:
    """从纯文本中提取标准节点"""
    nodes = []

    tokens = [line for line in text.splitlines() if line.strip()]
    for token in tokens:
        if token.startswith("#") or token.startswith("//"):
            continue

        ipport = ""
        label = ""

        if "#" in token:
            try:
                ipport, label = token.split("#", 1)
            except ValueError:
                continue
            ipport = ipport.strip()
            label = label.strip()
        else:
            ipport = token.strip()
            label = ""

        if ipport.startswith("["):
            continue

        if re.match(r"^\d+\.\d+\.\d+\.\d+$", ipport):
            ipport = f"{ipport}:443"

        if re.match(r"^[a-zA-Z0-9][-a-zA-Z0-9.]+\.[a-zA-Z]{2,}$", ipport):
            ipport = f"{ipport}:443"

        if re.match(r"^\d+\.\d+\.\d+\.\d+:\d+$", ipport):
            code = extract_country_code(label)
            if code:
                nodes.append(f"{ipport}#{code}")
            # 无法识别国家代码的节点不加入（避免错误标记）
            continue

        if re.match(r"^[a-zA-Z0-9][-a-zA-Z0-9.]+\.[a-zA-Z]{2,}:\d+$", ipport):
            domain = ipport.rsplit(":", 1)[0]
            port = ipport.rsplit(":", 1)[1]
            try:
                ip = socket.gethostbyname(domain)
                resolved = f"{ip}:{port}"
                code = extract_country_code(label)
                if code:
                    nodes.append(f"{resolved}#{code}")
                # 无法识别国家代码的域名节点不加入
            except Exception:
                pass
            continue

    return nodes


def parse_adaptive(text: str) -> list[str]:
    """自适应解析任意格式的节点列表文本"""
    text = text.strip()
    if not text:
        return []

    if text.startswith("{") or text.startswith("["):
        try:
            data = json.loads(text)
            return _parse_json_nodes(data)
        except (json.JSONDecodeError, Exception):
            pass

    return _parse_text_nodes(text)


# ==================== ASN 网段数据源（借鉴 RIPEstat announced-prefixes） ====================
RIPE_ANNOUNCED_PREFIXES_URL = "https://stat.ripe.net/data/announced-prefixes/data.json"


def _parse_ripe_prefixes(payload: Any, ipv6: bool) -> list[str]:
    """从 RIPE announced-prefixes 响应中提取前缀，按 IP 版本过滤"""
    prefixes = payload.get("data", {}).get("prefixes", []) if isinstance(payload, dict) else []
    want_v6 = bool(ipv6)
    result: list[str] = []
    for item in prefixes:
        prefix = item.get("prefix")
        if not prefix:
            continue
        is_v6 = ":" in prefix
        if is_v6 != want_v6:
            continue
        result.append(prefix)
    return result


async def fetch_asn_prefixes_async(
    asn: int, config: Config, client: httpx.AsyncClient, semaphore: asyncio.Semaphore
) -> list[str]:
    """异步拉取单个 ASN 通过 RIPE Stat 公告的全部前缀（CIDR），返回过滤后的前缀列表"""
    url = f"{RIPE_ANNOUNCED_PREFIXES_URL}?resource=AS{asn}"
    async with semaphore:
        for attempt in range(1, config.ASN_SOURCE_RETRY_MAX + 1):
            try:
                resp = await client.get(
                    url,
                    timeout=httpx.Timeout(config.ASN_SOURCE_TIMEOUT, connect=config.ASN_SOURCE_CONNECT_TIMEOUT),
                    follow_redirects=True,
                    params={"starttime": "1970-01-01T00:00"},
                )
                resp.raise_for_status()
                prefixes = _parse_ripe_prefixes(resp.json(), config.ASN_SOURCES_IPV6)
                print(f"[+] 成功获取 AS{asn} 的 {len(prefixes)} 个前缀")
                return prefixes
            except Exception as e:
                if attempt < config.ASN_SOURCE_RETRY_MAX:
                    await asyncio.sleep(config.ASN_SOURCE_RETRY_DELAY)
                else:
                    print(f"[-] 获取 AS{asn} 前缀失败（已重试 {config.ASN_SOURCE_RETRY_MAX} 次）: {e}")
                    return []
    return []


def expand_prefixes_to_nodes(prefixes: list[str], config: Config) -> list[str]:
    """将 CIDR 前缀展开为标准 ip:port#CC 节点，按配额均匀采样以控制规模

    采样策略：在全部网段间按「网段大小（主机数）」分配配额，与 ASN_SOURCE_MAX_IPS 对齐，
    再在每个网段内以等步长采样。相比「按顺序前 N 个」，本策略不会偏向排序靠前的小批网段，
    大网段（如 /13）能拿到与其规模相称的样本数。
    """
    target = config.ASN_SOURCE_MAX_IPS
    port = config.ASN_SOURCE_PORT
    country = config.ASN_SOURCE_COUNTRY

    networks: list[tuple[ipaddress.IPv4Network | ipaddress.IPv6Network, int]] = []
    total_hosts = 0
    for pfx in prefixes:
        try:
            net = ipaddress.ip_network(pfx, strict=False)
        except ValueError:
            continue
        host_count = max(1, net.num_addresses)
        networks.append((net, host_count))
        total_hosts += host_count

    if not networks or total_hosts == 0:
        return []

    nodes: list[str] = []
    for net, host_count in networks:
        # 按网段规模分配配额，至少给 1 个
        quota = max(1, round(target * (host_count / total_hosts)))

        if net.num_addresses >= 65536:
            # 超大网段（/14 及更大）直接迭代会爆，按等步长采样
            step = max(1, net.num_addresses // quota)
            sampled = min(quota, (net.num_addresses + step - 1) // step)
            for i in range(sampled):
                ip_int = int(net.network_address) + i * step
                if ip_int >= int(net.broadcast_address):
                    break
                ip = str(ipaddress.ip_address(ip_int))
                nodes.append(f"{ip}:{port}#{country}")
        else:
            # 小网段直接迭代全部主机（可能少于配额）
            for ip in net.hosts():
                nodes.append(f"{str(ip)}:{port}#{country}")
                quota -= 1
                if quota <= 0:
                    break

        # 全局上限兜底，防过度展开
        if len(nodes) >= target:
            break

    # 最终裁剪到全局上限
    return nodes[:target]


async def fetch_additional_source_async(
    url: str, config: Config, client: httpx.AsyncClient, semaphore: asyncio.Semaphore
) -> list[str]:
    """异步拉取单个数据源并返回标准节点列表（支持本地文件和 URL）"""
    if not url:
        return []

    if os.path.isfile(url):
        try:
            with open(url, encoding="utf-8") as f:
                text = f.read()
            nodes = parse_adaptive(text)
            print(f"[+] 本地文件 {url} 读取完成，解析出 {len(nodes)} 个节点。")
            return nodes
        except Exception as e:
            print(f"[-] 读取本地文件失败 ({url}): {e}")
            return []

    async with semaphore:
        for attempt in range(1, config.FETCH_MAX_RETRIES + 1):
            try:
                resp = await client.get(
                    url,
                    timeout=httpx.Timeout(config.FETCH_TIMEOUT, connect=config.FETCH_CONNECT_TIMEOUT),
                    follow_redirects=True,
                )
                resp.raise_for_status()
                nodes = parse_adaptive(resp.text)
                print(f"[+] 成功拉取 {url}，解析出 {len(nodes)} 个节点。")
                return nodes
            except Exception as e:
                if attempt < config.FETCH_MAX_RETRIES:
                    await asyncio.sleep(config.FETCH_RETRY_DELAY)
                else:
                    print(f"[-] 失败拉取 {url}（已重试 {config.FETCH_MAX_RETRIES} 次）: {e}")
                    return []
    return []


async def load_all_sources_async(
    config: Config, skip_fetch: bool = False, cached_file: str | None = None
) -> list[str]:
    """异步加载所有数据源，返回去重后的节点列表"""
    nodes: list[str] = []

    if skip_fetch and cached_file and os.path.exists(cached_file):
        print(f"跳过数据源拉取，读取缓存文件：{cached_file}")
        with open(cached_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    nodes.append(line)
        print(f"从缓存读取 {len(nodes)} 个节点。")
        return nodes

    enabled_sources = [s for s in config.ADDITIONAL_SOURCES if s.enabled and s.url]
    total_sources = len(enabled_sources)

    print(f"开始并发拉取 {total_sources} 个数据源...")
    
    workers = max(1, int(getattr(config, "MAX_WORKERS", 15) or 15))
    semaphore = asyncio.Semaphore(workers)  # 限制最大并发数，与 tester/subscription 一致
    limits = httpx.Limits(max_keepalive_connections=5, max_connections=workers + 5)
    
    async with httpx.AsyncClient(limits=limits) as client:
        tasks = [
            fetch_additional_source_async(source.url, config, client, semaphore)
            for source in enabled_sources
        ]
        
        results = await asyncio.gather(*tasks)
        
        seen = set()
        for v2_nodes in results:
            if v2_nodes:
                for n in v2_nodes:
                    key = n.split("#")[0]
                    if key not in seen:
                        seen.add(key)
                        nodes.append(n)

    print(f"合并后总计 {len(nodes)} 个节点。")
    return nodes


def load_all_sources(config: Config, skip_fetch: bool = False, cached_file: str | None = None) -> list[str]:
    """同步包装器，调用异步加载逻辑"""
    return asyncio.run(load_all_sources_async(config, skip_fetch, cached_file))
