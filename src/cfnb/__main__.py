#!/usr/bin/env python3
"""
Cloudflare IP 优选工具主程序
重构版：模块化架构，使用 Pydantic 配置验证
"""

import argparse
import atexit
import os
import pickle
import sys
from typing import Any
from collections import defaultdict
from pathlib import Path

from cfnb.config import Config, get_config, load_config
from cfnb.dns import filter_dns_candidates, update_cloudflare_dns
from cfnb.fetcher import load_all_sources
from cfnb.output import print_final_nodes, print_summary, write_ip_txt
from cfnb.push import push_to_github
from cfnb.speed import run_speed_test_with_retry
from cfnb.subscription import (
    convert_subscriptions,
    write_sub_output,
    write_source_map,
    load_source_map,
)
from cfnb.tester import run_availability_tests, run_tcp_tests
from cfnb.latency import latency_filter, save_latency_history
from cfnb.util.proxy import disable_proxy, restore_proxy


# ==================== 自定义异常（替代 sys.exit，支持 import 调用）====================
class NoNodesError(Exception):
    """所有节点被过滤，无法继续测试"""


class FatalError(Exception):
    """致命错误，程序无法继续"""


def setup_logging(config: Config) -> None:
    """设置日志输出"""
    if not config.ENABLE_LOGGING:
        return

    # GUI 模式下 stdout 是管道，不写 cfnb.log（gui.log 已记录所有输出）
    # 避免 _Tee 双重写入同一管道导致每行输出两次
    if hasattr(sys.stdout, "isatty") and not sys.stdout.isatty():
        return

    try:
        script_dir = Path(__file__).parent.parent.parent
        log_path = script_dir / config.LOG_FILE
        log_f = open(log_path, "w", encoding="utf-8")
        print(f"日志已启用，输出将保存到 {log_path}")

        class _Tee:
            def __init__(self, *files: Any) -> None:
                self.files = files

            def write(self, obj: str) -> None:
                for f in self.files:
                    f.write(obj)
                    f.flush()

            def flush(self) -> None:
                for f in self.files:
                    f.flush()

        # 检测是否为管道模式（GUI 调用子进程）
        # 管道模式下不重定向 stdout/stderr，避免 _Tee 双重写入同一管道导致重复输出
        is_pipe = not (hasattr(sys.__stdout__, "isatty") and sys.__stdout__.isatty())
        if not is_pipe:
            sys.stdout = _Tee(sys.stdout, log_f)
            sys.stderr = _Tee(sys.stderr, log_f)

        def _close_log() -> None:
            try:
                sys.stdout = sys.__stdout__
                sys.stderr = sys.__stderr__
                log_f.close()
            except Exception:
                pass

        atexit.register(_close_log)
    except Exception as e:
        print(f"无法打开日志文件: {e}")


def run_main(args: argparse.Namespace) -> None:
    """主运行逻辑"""
    config = get_config()

    # 打印配置摘要
    mode_str = (
        f"全局最优{config.GLOBAL_TOP_N}个" if config.USE_GLOBAL_MODE else f"每个国家最优{config.PER_COUNTRY_TOP_N}个"
    )
    print(f"当前模式：{mode_str}，每个节点测试 {config.TCP_PROBES} 次 TCP 连接")
    print(f"最低成功率要求：{config.MIN_SUCCESS_RATE * 100:.0f}%")
    print(f"IP 可用性二次筛选：{'启用' if config.TEST_AVAILABILITY else '禁用'}（仅对候选节点）")
    print(f"IPv6 客户端 IP 过滤（仅作用于DNS更新环节）：{'启用' if config.FILTER_IPV6_AVAILABILITY else '禁用'}")
    print(
        f"DNS黑名单过滤：{'启用' if config.FILTER_BLOCKED_COUNTRIES_ENABLED else '禁用'}"
        f"，黑名单国家：{', '.join(config.BLOCKED_COUNTRIES)}"
    )
    print(
        f"IP 风险等级过滤：{'启用' if config.DNS_IP_RISK_FILTER_ENABLED else '禁用'}"
        f"（最高允许：{config.DNS_IP_RISK_MAX_LEVEL}）"
    )
    print(
        f"带宽测速候选数：{config.BANDWIDTH_CANDIDATES}，测速文件大小：{config.BANDWIDTH_SIZE_MB}"
        f" MB，超时：{config.BANDWIDTH_TIMEOUT}s"
    )
    if config.FILTER_COUNTRIES_ENABLED:
        print(f"前置白名单过滤：启用，仅保留：{', '.join(config.ALLOWED_COUNTRIES)}")

    # 检测命令行参数
    skip_fetch = args.skip_fetch
    fetch_only = args.fetch_only
    skip_tcp = args.skip_tcp
    skip_availability = args.skip_availability
    skip_bandwidth = args.skip_bandwidth
    skip_dns = args.skip_dns
    skip_push = args.skip_push

    script_dir = Path(__file__).parent.parent.parent
    cached_file = script_dir / "nodes_raw.txt"
    tcp_cache_file = script_dir / "tcp_cache.pkl"

    # 1. 加载数据源
    nodes = load_all_sources(config, skip_fetch, str(cached_file))

    # --fetch-only 模式：只获取节点，保存后退出
    if fetch_only:
        with open(cached_file, "w", encoding="utf-8") as f:
            for n in nodes:
                f.write(n + "\n")
        print(f"已保存 {len(nodes)} 个节点到 {cached_file}")
        return

    # 测速前禁用系统代理
    saved_proxy = disable_proxy()
    print("测速阶段：已禁用系统代理（直连测试）。")

    # 2. 前置过滤
    # 端口过滤
    if config.PRE_FILTER_PORT_ENABLED:
        before = len(nodes)
        allowed_ports = {str(p) for p in config.PRE_FILTER_PORTS}
        nodes = [n for n in nodes if n.split(":")[1].split("#")[0] in allowed_ports]
        after = len(nodes)
        print(f"前置端口过滤（仅保留端口 {', '.join(map(str, config.PRE_FILTER_PORTS))}）：{before} -> {after} 个节点")
        if not nodes:
            print("前置端口过滤后无任何节点，退出程序。")
            raise NoNodesError("前置端口过滤后无任何节点")

    # 黑名单过滤
    if config.PRE_FILTER_BLOCKED_ENABLED and config.PRE_FILTER_BLOCKED_COUNTRIES:
        before = len(nodes)
        blocked_set = {c.upper() for c in config.PRE_FILTER_BLOCKED_COUNTRIES}
        nodes = [n for n in nodes if n.split("#")[-1].upper() not in blocked_set]
        after = len(nodes)
        print(f"前置黑名单过滤：{before} -> {after} 个节点（已屏蔽：{', '.join(sorted(blocked_set))}）")
        if not nodes:
            print("前置黑名单过滤后无任何节点，退出程序。")
            raise NoNodesError("前置黑名单过滤后无任何节点")

    # 白名单过滤
    if config.FILTER_COUNTRIES_ENABLED and config.ALLOWED_COUNTRIES:
        before = len(nodes)
        allowed_set = {c.upper() for c in config.ALLOWED_COUNTRIES}
        nodes = [n for n in nodes if n.split("#")[-1].upper() in allowed_set]
        after = len(nodes)
        print(f"\n国家过滤（测试前）：{before} -> {after} 个节点（允许国家：{', '.join(allowed_set)}）")
        if not nodes:
            print("过滤后无任何节点，退出程序。")
            raise NoNodesError("白名单过滤后无任何节点")

    if not nodes:
        print("没有获取到任何有效节点，退出。")
        raise NoNodesError("没有获取到任何有效节点")

    # 3. TCP 测试
    if skip_tcp and tcp_cache_file.exists():
        try:
            with open(tcp_cache_file, "rb") as f:
                tcp_results, latency_map = pickle.load(f)
            print(f"\n加载 TCP 缓存：{len(tcp_results)} 个节点")
        except Exception as e:
            print(f"\n加载 TCP 缓存失败: {e}，重新进行 TCP 测试...")
            tcp_results = run_tcp_tests(nodes, config, skip_tcp)
            if not tcp_results:
                print("没有通过成功率筛选的节点，请检查网络或降低 MIN_SUCCESS_RATE。")
                raise NoNodesError("TCP 测试无通过节点")
            tcp_results.sort(key=lambda x: (-x.success_count, x.latency))
            latency_map = {r.node: r.latency for r in tcp_results}
    else:
        tcp_results = run_tcp_tests(nodes, config, skip_tcp)
        if not tcp_results:
            print("没有通过成功率筛选的节点，请检查网络或降低 MIN_SUCCESS_RATE。")
            raise NoNodesError("TCP 测试无通过节点")
        tcp_results.sort(key=lambda x: (-x.success_count, x.latency))
        latency_map = {r.node: r.latency for r in tcp_results}
        try:
            with open(tcp_cache_file, "wb") as f:
                pickle.dump((tcp_results, latency_map), f)
            print(f"TCP 结果已缓存到 {tcp_cache_file}")
        except Exception as e:
            print(f"保存 TCP 缓存失败: {e}")

    if args.tcp_only:
        print("\n--tcp-only 已启用，已保存 TCP 缓存，程序退出。")
        return

    # 4. 可用性检测候选：全部 TCP 通过的节点（不截取 3000）
    all_tcp_passed = [r.node for r in tcp_results]
    print(f"\nTCP 通过 {len(all_tcp_passed)} 个节点，全部进入可用性检测。")

    # 5. 可用性检测
    avail_cache_file = script_dir / "avail_cache.pkl"
    avail_ip_info: dict[str, str] = {}

    if skip_availability and avail_cache_file.exists():
        try:
            with open(avail_cache_file, "rb") as f:
                candidates_after_avail, latency_map, avail_ip_info = pickle.load(f)
            print(f"\n加载可用性缓存：{len(candidates_after_avail)} 个节点")
        except Exception as e:
            print(f"\n加载可用性缓存失败: {e}，重新进行可用性检测...")
            candidates_after_avail, avail_ip_info, _ = run_availability_tests(all_tcp_passed, config)
            try:
                with open(avail_cache_file, "wb") as f:
                    pickle.dump((candidates_after_avail, latency_map, avail_ip_info), f)
            except Exception:
                pass
    elif skip_availability and not avail_cache_file.exists():
        candidates_after_avail = list(all_tcp_passed)
        print(f"\n跳过可用性检测（无缓存），直接使用候选节点。")
    else:
        candidates_after_avail, avail_ip_info, _ = run_availability_tests(all_tcp_passed, config)
        try:
            with open(avail_cache_file, "wb") as f:
                pickle.dump((candidates_after_avail, latency_map, avail_ip_info), f)
            print(f"可用性检测结果已缓存到 {avail_cache_file}")
        except Exception as e:
            print(f"保存可用性缓存失败: {e}")

    # 如果跳过带宽测速（通常在仅执行可用性检测步骤时触发），则提前退出
    if skip_bandwidth:
        print("\n--skip-bandwidth 已启用，已保存可用性检测结果缓存，程序退出。")
        return

    # 6. 漏斗截取：对可用节点中延迟最优的前 BANDWIDTH_CANDIDATES 名进行测速
    candidates_after_avail.sort(key=lambda x: latency_map.get(x, 999.0))
    bw_candidate_count = min(config.BANDWIDTH_CANDIDATES, len(candidates_after_avail))
    speed_test_candidates = candidates_after_avail[:bw_candidate_count]
    print(f"\n可用节点 {len(candidates_after_avail)} 个，截取延迟最优的前 {bw_candidate_count} 名进入带宽测速。")

    # 7. 带宽测速（在精简后的可用节点中进行）
    bw_results_objects = run_speed_test_with_retry(speed_test_candidates, config)
    bw_results = [(r.node, r.speed_mbps) for r in bw_results_objects]
    speed_map = dict(bw_results)

    # 7. 最终节点选择
    country_nodes = defaultdict(list)
    for r in tcp_results:
        country_nodes[r.country].append(r)

    country_speed_nodes = defaultdict(list)
    for node, speed in bw_results:
        country = node.split("#")[-1] if "#" in node else ""
        if country:
            country_speed_nodes[country].append((node, speed))

    if config.PER_COUNTRY_QUOTA:
        final_selected = []
        seen = set()
        for country, quota in config.PER_COUNTRY_QUOTA.items():
            taken = 0
            for node, _speed in country_speed_nodes.get(country, []):
                if taken >= quota:
                    break
                if node not in seen:
                    final_selected.append(node)
                    seen.add(node)
                    taken += 1
            if taken < quota and country in country_nodes:
                tcp_sorted = sorted(country_nodes[country], key=lambda x: x.latency)
                for r in tcp_sorted:
                    if taken >= quota:
                        break
                    if r.node not in seen:
                        final_selected.append(r.node)
                        seen.add(r.node)
                        taken += 1
        if len(final_selected) < config.GLOBAL_TOP_N:
            fill = [n for n, s in bw_results if n not in seen][: config.GLOBAL_TOP_N - len(final_selected)]
            final_selected.extend(fill)
        elif len(final_selected) > config.GLOBAL_TOP_N:
            final_selected = final_selected[: config.GLOBAL_TOP_N]
    elif config.USE_GLOBAL_MODE:
        final_selected = [node for node, _ in bw_results[: config.GLOBAL_TOP_N]]
    else:
        final_selected = []
        for _country, nodes_list in country_speed_nodes.items():
            for node, _speed in nodes_list[: config.PER_COUNTRY_TOP_N]:
                final_selected.append(node)
        final_selected.sort(key=lambda x: speed_map.get(x, 0), reverse=True)

    # 综合质量评分排序（相对归一化加权算法）
    max_speed = 0.0
    min_latency = float("inf")
    
    for node in final_selected:
        speed_val = float(speed_map.get(node, 0.0))
        lat_val = float(latency_map.get(node, float("inf")))
        if speed_val > max_speed:
            max_speed = speed_val
        if lat_val < min_latency:
            min_latency = lat_val

    def quality_score(node: str) -> float:
        speed = float(speed_map.get(node, 0.0))
        lat = float(latency_map.get(node, float("inf")))
        
        # 1. 速度相对得分 (0.0 ~ 1.0)
        speed_score = speed / max_speed if max_speed > 0 else 0.0
        
        # 2. 延迟相对得分 (0.0 ~ 1.0)
        latency_score = min_latency / lat if (lat > 0 and min_latency != float("inf")) else 0.0
        
        # 3. 加权融合评分
        w_speed = config.QUALITY_SPEED_WEIGHT
        w_latency = config.QUALITY_LATENCY_WEIGHT
        
        total_w = w_speed + w_latency
        if total_w > 0:
            w_speed /= total_w
            w_latency /= total_w
        else:
            w_speed, w_latency = 0.60, 0.40
            
        return speed_score * w_speed + latency_score * w_latency

    final_selected.sort(key=quality_score, reverse=True)

    # 打印摘要
    print_summary(len(all_tcp_passed), len(tcp_results), len(candidates_after_avail), bw_results, final_selected, config)
    print_final_nodes(final_selected, speed_map, latency_map)

    # 7. 写入 ip.txt
    write_ip_txt(final_selected, config.OUTPUT_FILE, config, speed_map, latency_map)
    print(f"\n结果已保存到 {config.OUTPUT_FILE}（共 {len(final_selected)} 个节点）")

    # 保存历史记录（带时间戳的副本）
    _save_history(config.OUTPUT_FILE)

    # 8. Cloudflare DNS 更新
    if skip_dns:
        print("\n跳过 Cloudflare DNS 更新。")
    else:
        dns_content_list, dns_node_list, stats = filter_dns_candidates(bw_results, avail_ip_info, config)

        if (
            stats.filtered_by_port > 0
            or stats.filtered_by_ipv6 > 0
            or stats.filtered_by_country > 0
            or stats.filtered_by_risk > 0
        ):
            filter_parts = []
            if stats.filtered_by_port > 0:
                filter_parts.append(f"非443端口过滤({stats.filtered_by_port}个)")
            if config.FILTER_IPV6_AVAILABILITY:
                filter_parts.append(f"IPv6落地过滤({stats.filtered_by_ipv6}个)")
            if config.FILTER_BLOCKED_COUNTRIES_ENABLED:
                filter_parts.append(f"DNS黑名单过滤({stats.filtered_by_country}个)")
            if config.DNS_IP_RISK_FILTER_ENABLED and stats.filtered_by_risk > 0:
                filter_parts.append(f"风险等级过滤({stats.filtered_by_risk}个)")
            filter_str = " + ".join(filter_parts) if filter_parts else "无过滤"
            record_type = config.DNS_RECORD_TYPE.upper()
            type_label = "IP" if record_type == "A" else "IP:端口"
            print(
                f"从 {len(bw_results)} 个测速节点中筛选出 {len(dns_content_list)} 个"
                f"{type_label} 用于 DNS 更新（{filter_str}）。"
            )
            if stats.fallback_used:
                print("⚠️ 风险等级检测全部失败，已回退到无风险等级过滤的候选列表。")

        update_cloudflare_dns(dns_content_list, dns_node_list, config, speed_map, latency_map)

    # 10. 恢复系统代理
    restore_proxy(saved_proxy)

    # 11. 订阅转换（生成独立的 addressesapi.txt，与 ip.txt 分开存放）
    if config.SUB_CONVERT_ENABLED:
        try:
            run_subscription_convert(config)
        except Exception as e:
            print(f"订阅转换失败: {e}")

    # 12. GitHub 推送（git_sync 会同时推送 ip.txt 与订阅文件）
    if skip_push:
        print("\n跳过 GitHub 同步。")
    elif config.GITHUB_SYNC_MAX_RETRIES > 0:
        push_to_github(config)

    # 12. 消息通知
    try:
        from cfnb.notify import send_notification
        summary_lines = []
        if final_selected:
            summary_lines.append("### 优选节点列表 (Top 5)")
            for idx, node in enumerate(final_selected[:5], 1):
                speed = speed_map.get(node, 0)
                latency = latency_map.get(node, 0) * 1000  # 毫秒
                summary_lines.append(f"{idx}. `{node}` - 带宽: {speed:.2f} Mbps | 延迟: {latency:.1f} ms")
        
        content = "\n".join(summary_lines)
        send_notification(
            title="Cloudflare IP 优选完成",
            content=content,
            config=config,
        )
    except Exception as e:
        print(f"发送通知失败: {e}")

    print("\n测速完成！")


def _save_history(output_file: str) -> None:
    """保存带时间戳的历史记录副本"""
    import datetime
    script_dir = Path(__file__).parent.parent.parent
    history_dir = script_dir / "history"
    try:
        history_dir.mkdir(exist_ok=True)
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        src = script_dir / output_file
        if src.exists():
            dst = history_dir / f"{output_file.replace('.txt', '')}_{timestamp}.txt"
            import shutil
            shutil.copy2(src, dst)
            # 只保留最近 20 条历史
            history_files = sorted(history_dir.glob("*.txt"), key=os.path.getmtime, reverse=True)
            for old in history_files[20:]:
                old.unlink()
            print(f"历史记录已保存到 {dst}")
    except Exception as e:
        print(f"保存历史记录失败: {e}")


def run_subscription_convert(config: Config) -> list[str]:
    """执行订阅转换：拉取订阅 → 解析 → 写入独立的 IP 文件（与 ip.txt 分开）"""
    print(f"\n{'=' * 50}\n订阅转换：从订阅链接提取 IP 列表")
    nodes, node_source = convert_subscriptions(config)
    if not nodes:
        print("订阅转换未产出任何节点，跳过写入。")
        return []
    write_sub_output(nodes, config.SUB_OUTPUT_FILE)
    write_source_map(node_source, config.SUB_OUTPUT_FILE)
    print(f"订阅结果已保存到 {config.SUB_OUTPUT_FILE}（共 {len(nodes)} 个节点）")
    return nodes


def run_sub_only(args: argparse.Namespace) -> None:
    """--sub-only 模式：仅执行订阅转换，写入 addressesapi.txt（不推送）"""
    config = get_config()
    run_subscription_convert(config)
    print("\n订阅转换完成（仅写入本地，未推送）。")


def run_latency_only(args: argparse.Namespace) -> None:
    """--latency-only 模式：对 addressesapi.txt 做延迟优选，保留前 N 名并推送新文件"""
    config = get_config()
    script_dir = Path(__file__).parent.parent.parent
    input_file = script_dir / config.SUB_OUTPUT_FILE
    output_file = script_dir / config.SUB_LATENCY_OUTPUT_FILE

    if not input_file.exists():
        print(f"错误：未找到 {config.SUB_OUTPUT_FILE}，请先运行「订阅IP」获取并去重节点。")
        return

    print(f"\n{'=' * 50}\n延迟优选：读取 {config.SUB_OUTPUT_FILE} → TCP 延迟测试 → 保留前 {config.SUB_LATENCY_TOPN} 名")
    node_source = load_source_map(config.SUB_OUTPUT_FILE)
    kept, tested, ok = latency_filter(
        str(input_file),
        str(output_file),
        config.SUB_LATENCY_TOPN,
        config.SUB_LATENCY_TIMEOUT,
        config.SUB_LATENCY_WORKERS,
        node_source,
    )
    print(f"参与测试 {tested} 个，连通 {ok} 个，保留 {len(kept)} 个 → 写入 {config.SUB_LATENCY_OUTPUT_FILE}")
    save_latency_history(str(output_file), len(kept), tested, ok)
    if not kept:
        print("延迟优选未产出任何节点，跳过推送。")
        return

    if args.skip_push:
        print("\n跳过 GitHub 同步。")
    elif config.GITHUB_SYNC_MAX_RETRIES > 0:
        push_to_github(config)
    print(f"\n延迟优选完成！推荐推送文件：{config.SUB_LATENCY_OUTPUT_FILE}")


def run_push_only(args: argparse.Namespace) -> None:
    """--push-only 模式：仅把 ip.txt 与延迟优选输出文件推送到 GitHub"""
    config = get_config()
    if config.GITHUB_SYNC_MAX_RETRIES > 0:
        push_to_github(config)
    else:
        print("GitHub 同步已禁用（GITHUB_SYNC_MAX_RETRIES=0）。")


def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description="Cloudflare IP 优选工具 - 自动发现最优 Cloudflare CDN 节点",
    )
    parser.add_argument(
        "--version", action="version", version="cfnb 2.0.0",
    )
    parser.add_argument(
        "--skip-fetch", action="store_true",
        help="跳过数据源拉取，直接使用缓存的 nodes_raw.txt",
    )
    parser.add_argument(
        "--fetch-only", action="store_true",
        help="只拉取数据源并保存到 nodes_raw.txt，然后退出",
    )
    parser.add_argument(
        "--skip-tcp", action="store_true",
        help="跳过 TCP 延迟测试（用于带宽测速阶段）",
    )
    parser.add_argument(
        "--skip-availability", action="store_true",
        help="跳过可用性检测（用于带宽测速阶段，优先使用缓存）",
    )
    parser.add_argument(
        "--skip-bandwidth", action="store_true",
        help="跳过带宽测速",
    )
    parser.add_argument(
        "--skip-dns", action="store_true",
        help="跳过 Cloudflare DNS 更新",
    )
    parser.add_argument(
        "--skip-push", action="store_true",
        help="跳过 GitHub 同步",
    )
    parser.add_argument(
        "--tcp-only", action="store_true",
        help="只进行 TCP 延迟测试并保存缓存，然后退出",
    )
    parser.add_argument(
        "--sub-only", action="store_true",
        help="只执行订阅转换（拉取订阅→提取 IP→写入独立文件，不推送），然后退出",
    )
    parser.add_argument(
        "--latency-only", action="store_true",
        help="只对已获取的订阅 IP 做延迟优选（保留前 N 名写入新文件并推送），然后退出",
    )
    parser.add_argument(
        "--push-only", action="store_true",
        help="只执行 GitHub 同步推送（ip.txt 及延迟优选输出文件），然后退出",
    )
    return parser.parse_args()


def main() -> None:
    """入口点"""
    try:
        args = parse_args()
        load_config()  # 早期加载配置，验证配置完整性
        setup_logging(get_config())
        if args.sub_only:
            run_sub_only(args)
        elif args.latency_only:
            run_latency_only(args)
        elif args.push_only:
            run_push_only(args)
        else:
            run_main(args)
    except KeyboardInterrupt:
        print("\n用户中断，退出。")
        sys.exit(1)
    except NoNodesError as e:
        print(f"\n筛选结束：{e}")
        sys.exit(0)
    except FatalError as e:
        print(f"\n程序异常退出: {e}")
        sys.exit(1)
    except SystemExit:
        raise
    except Exception as e:
        print(f"\n程序异常退出: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
