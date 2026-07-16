"""Cloudflare DNS 批量更新模块"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass
from typing import Any

import httpx

from cfnb.config import Config

RISK_LEVEL_ORDER = {
    "极度纯净": 0,
    "纯净": 1,
    "轻微风险": 2,
    "高风险": 3,
    "极度危险": 4,
}


@dataclass
class DnsFilterStats:
    """DNS 过滤统计"""

    filtered_by_port: int = 0
    filtered_by_ipv6: int = 0
    filtered_by_country: int = 0
    filtered_by_risk: int = 0
    fallback_used: bool = False


# IP 风险等级查询缓存持久化与 TTL 机制
import json
from pathlib import Path

_RISK_CACHE_FILE = Path.cwd() / "risk_cache.json"
_RISK_CACHE: dict[str, dict] = {}

def load_risk_cache() -> None:
    global _RISK_CACHE
    if _RISK_CACHE_FILE.exists():
        try:
            with open(_RISK_CACHE_FILE, encoding="utf-8") as f:
                _RISK_CACHE = json.load(f)
        except Exception:
            _RISK_CACHE = {}

def save_risk_cache() -> None:
    try:
        with open(_RISK_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(_RISK_CACHE, f, indent=4, ensure_ascii=False)
    except Exception:
        pass


def get_ip_risk_level(ip: str) -> str:
    """查询单个 IP 的风险等级字符串（带缓存，缓存持久化且 TTL 24 小时）"""
    global _RISK_CACHE

    if not _RISK_CACHE and _RISK_CACHE_FILE.exists():
        load_risk_cache()

    now = time.time()
    if ip in _RISK_CACHE:
        cached = _RISK_CACHE[ip]
        if now - cached.get("timestamp", 0) < 86400:
            return cached.get("result", "未知")

    url = f"https://api.ipapi.is/?q={ip}"
    try:
        resp = httpx.get(url, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except Exception:
        # 针对请求失败，仅在内存中记录“未知”，不写入磁盘持久化，保证下次有机会重试
        if ip not in _RISK_CACHE:
            _RISK_CACHE[ip] = {"result": "未知", "timestamp": now}
        return "未知"

    company_score = data.get("company", {}).get("abuser_score")
    asn_score = data.get("asn", {}).get("abuser_score")
    security_flags = {
        "is_crawler": data.get("is_crawler", False),
        "is_proxy": data.get("is_proxy", False),
        "is_vpn": data.get("is_vpn", False),
        "is_tor": data.get("is_tor", False),
        "is_abuser": data.get("is_abuser", False),
        "is_bogon": data.get("is_bogon", False),
    }

    def extract_score(score_str: Any) -> float:
        if not score_str:
            return 0.0

        match = re.match(r"([\d.]+)\s*\(([^)]+)\)", str(score_str).strip())
        if match:
            return float(match.group(1))
        try:
            return float(score_str)
        except (ValueError, TypeError):
            return 0.0

    company = extract_score(company_score)
    asn = extract_score(asn_score)
    base_score = ((company + asn) / 2) * 5

    risk_count = sum(
        1 for key in ["is_crawler", "is_proxy", "is_vpn", "is_tor", "is_abuser"] if security_flags.get(key, False)
    )
    final_score = base_score + risk_count * 0.15
    if security_flags.get("is_bogon", False):
        final_score += 1.0

    percentage = final_score * 100
    if percentage >= 100:
        result = "极度危险"
    elif percentage >= 20:
        result = "高风险"
    elif percentage >= 5:
        result = "轻微风险"
    elif percentage >= 0.25:
        result = "纯净"
    else:
        result = "极度纯净"

    _RISK_CACHE[ip] = {
        "result": result,
        "timestamp": now
    }
    save_risk_cache()
    return result


def filter_dns_candidates(
    bw_results: list[tuple[str, float]], ip_info: dict[str, str], config: Config, target_count: int | None = None
) -> tuple[list[str], list[str], DnsFilterStats]:
    """
    从带宽测速结果中筛选 DNS 更新候选节点
    返回: (content_list, node_list, stats)
    """
    if target_count is None:
        target_count = config.DNS_UPDATE_TARGET_COUNT

    record_type = config.DNS_RECORD_TYPE.upper()
    if record_type not in ("A", "TXT"):
        print(f"不支持的 DNS_RECORD_TYPE: {record_type}，已跳过 DNS 更新。")
        return [], [], DnsFilterStats()

    dns_content_list: list[str] = []
    dns_node_list: list[str] = []
    stats = DnsFilterStats()

    blocked_set = set()
    if config.FILTER_BLOCKED_COUNTRIES_ENABLED:
        blocked_set = {c.upper() for c in config.BLOCKED_COUNTRIES}

    risk_fallback_content: list[str] = []
    risk_fallback_nodes: list[str] = []

    for node_str, _speed in bw_results:
        if ":" not in node_str:
            continue
        parts = node_str.split(":")
        if len(parts) < 2:
            continue
        pure_ip = parts[0]
        port = parts[1].split("#")[0]

        # 端口过滤：统一强制要求 443
        if port != "443":
            stats.filtered_by_port += 1
            continue

        # IPv6 落地过滤
        if config.FILTER_IPV6_AVAILABILITY:
            stack = ip_info.get(node_str, "unknown")
            if stack == "ipv6_only":
                stats.filtered_by_ipv6 += 1
                continue

        # 国家黑名单过滤
        if blocked_set and "#" in node_str:
            country = node_str.split("#")[-1].upper()
            if country in blocked_set:
                stats.filtered_by_country += 1
                continue

        # IP 风险等级过滤
        if config.DNS_IP_RISK_FILTER_ENABLED:
            risk_level = get_ip_risk_level(pure_ip)
            max_level = config.DNS_IP_RISK_MAX_LEVEL
            if risk_level == "未知" or RISK_LEVEL_ORDER.get(risk_level, 99) > RISK_LEVEL_ORDER.get(max_level, 2):
                stats.filtered_by_risk += 1
                # 只把被风险过滤淘汰的节点加入回退列表
                risk_fallback_content.append(pure_ip if record_type == "A" else f"{pure_ip}:{port}")
                risk_fallback_nodes.append(node_str)
                continue

        # 根据记录类型构建内容
        if record_type == "A":
            dns_content_list.append(pure_ip)
        else:
            dns_content_list.append(f"{pure_ip}:{port}")
        dns_node_list.append(node_str)

        if len(dns_content_list) >= target_count:
            break

    # 风险等级检测全部失败时的回退处理
    if config.DNS_IP_RISK_FILTER_ENABLED and not dns_content_list and stats.filtered_by_risk > 0:
        stats.fallback_used = True
        fallback_content = risk_fallback_content[:target_count]
        fallback_nodes = risk_fallback_nodes[:target_count]
        dns_content_list = fallback_content
        dns_node_list = fallback_nodes

    # 去重
    seen = set()
    unique_content = []
    unique_nodes = []
    for content, node in zip(dns_content_list, dns_node_list, strict=False):
        if content not in seen:
            seen.add(content)
            unique_content.append(content)
            unique_nodes.append(node)

    return unique_content, unique_nodes, stats


def update_cloudflare_dns(
    content_list: list[str],
    node_list: list[str],
    config: Config,
    speed_map: dict[str, float] | None = None,
    latency_map: dict[str, float] | None = None,
) -> bool:
    """
    批量更新 Cloudflare DNS 记录
    返回: 是否成功
    """
    if not config.CF_ENABLED:
        print("Cloudflare DNS 批量更新未启用。")
        return False

    if not content_list:
        print("没有可用的 IP 用于 DNS 更新，跳过。")
        return False

    record_type = config.DNS_RECORD_TYPE.upper()
    headers = {"Authorization": f"Bearer {config.CF_API_TOKEN}", "Content-Type": "application/json"}

    label = "IP" if record_type == "A" else "IP:端口"
    print(f"\n准备将以下 {len(content_list)} 个{label} 更新到 Cloudflare DNS（记录类型 {record_type}）：")
    for i, (content, node) in enumerate(zip(content_list, node_list, strict=False), 1):
        speed = speed_map.get(node, 0) if speed_map else 0
        lat_ms = float("inf")
        if latency_map and node in latency_map:
            lat_ms = latency_map[node] * 1000
        if lat_ms != float("inf"):
            print(f"{i}. {content} 速度 {speed:.2f} Mbps 延迟 {lat_ms:.2f} ms")
        else:
            print(f"{i}. {content} 速度 {speed:.2f} Mbps")

    for attempt in range(1, config.DNS_UPDATE_MAX_RETRIES + 1):
        print(f"\n[DNS 更新] 尝试 {attempt}/{config.DNS_UPDATE_MAX_RETRIES}...")
        try:
            list_url = f"https://api.cloudflare.com/client/v4/zones/{config.CF_ZONE_ID}/dns_records?type={record_type}&name={config.CF_DNS_RECORD_NAME}"
            response = httpx.get(
                list_url, headers=headers, timeout=(config.CF_DNS_CONNECT_TIMEOUT, config.CF_DNS_READ_TIMEOUT)
            )
            response.raise_for_status()
            result = response.json()
            if not result.get("success"):
                raise Exception(f"查询 DNS 记录失败: {result.get('errors')}")

            existing_records = result.get("result", [])
            deletes = [{"id": rec["id"]} for rec in existing_records]

            if record_type == "A":
                posts = [
                    {
                        "name": config.CF_DNS_RECORD_NAME,
                        "type": "A",
                        "content": ip,
                        "ttl": config.CF_TTL,
                        "proxied": config.CF_PROXIED,
                    }
                    for ip in content_list
                ]
            else:
                posts = [
                    {"name": config.CF_DNS_RECORD_NAME, "type": "TXT", "content": content, "ttl": config.CF_TTL}
                    for content in content_list
                ]

            batch_url = f"https://api.cloudflare.com/client/v4/zones/{config.CF_ZONE_ID}/dns_records/batch"
            payload = {"deletes": deletes, "posts": posts}
            response = httpx.post(
                batch_url,
                headers=headers,
                json=payload,
                timeout=(config.CF_DNS_CONNECT_TIMEOUT, config.CF_DNS_READ_TIMEOUT),
            )
            response.raise_for_status()
            result = response.json()
            if not result.get("success"):
                raise Exception(f"批量更新失败: {result.get('errors')}")

            print(
                f"Cloudflare DNS 批量更新成功！已将 {config.CF_DNS_RECORD_NAME} 指向 {len(content_list)} 个 {label}。"
            )
            if record_type == "A":
                print("注意：DNS 解析将随机返回这些 IP 中的一个，实现负载均衡。")
            return True

        except Exception as e:
            error_msg = f"[尝试 {attempt}/{config.DNS_UPDATE_MAX_RETRIES}] DNS 更新出错: {e}"
            print(error_msg)
            if attempt < config.DNS_UPDATE_MAX_RETRIES:
                print(f"等待 {config.DNS_UPDATE_RETRY_DELAY} 秒后重试...")
                time.sleep(config.DNS_UPDATE_RETRY_DELAY)
            else:
                final_error = f"Cloudflare DNS 更新失败，已重试 {config.DNS_UPDATE_MAX_RETRIES} 次，错误：{e}"
                print(final_error)
                return False

    return False
