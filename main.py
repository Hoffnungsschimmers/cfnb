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

from config import Config, get_config, load_config
from dns import filter_dns_candidates, update_cloudflare_dns
from fetcher import load_all_sources
from output import print_final_nodes, print_summary, write_ip_txt
from push import push_to_github
from speed import run_speed_test_with_retry
from tester import run_availability_tests, run_tcp_tests


# ==================== 自定义异常（替代 sys.exit，支持 import 调用）====================
class NoNodesError(Exception):
    """所有节点被过滤，无法继续测试"""


class FatalError(Exception):
    """致命错误，程序无法继续"""


def setup_logging(config: Config) -> None:
    """设置日志输出"""
    if not config.ENABLE_LOGGING:
        return

    try:
        script_dir = Path(__file__).parent
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
                if not is_pipe:
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

    script_dir = Path(__file__).parent
    cached_file = script_dir / "nodes_raw.txt"
    avail_cache_file = script_dir / "avail_cache.pkl"

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
    saved_proxy = {}
    for var in ["http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy"]:
        saved_proxy[var] = os.environ.pop(var, None)
    os.environ["NO_PROXY"] = "*"
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
    tcp_results = run_tcp_tests(nodes, config, skip_tcp)
    if not tcp_results:
        print("没有通过成功率筛选的节点，请检查网络或降低 MIN_SUCCESS_RATE。")
        raise NoNodesError("TCP 测试无通过节点")

    # 排序：成功数降序，延迟升序
    tcp_results.sort(key=lambda x: (-x.success_count, x.latency))
    latency_map = {r.node: r.latency for r in tcp_results}

    # 4. 候选池（全部 TCP 通过的节点）
    candidates = [r.node for r in tcp_results]
    print(f"\nTCP 通过的 {len(candidates)} 个节点全部进入候选池。")

    # 5. 可用性检测
    if skip_availability and avail_cache_file.exists():
        with open(avail_cache_file, "rb") as f:  # type: ignore[assignment]
            candidates_after_avail, latency_map = pickle.load(f)  # type: ignore[arg-type]
        avail_ip_info: dict[str, str] = {}
        print(f"\n加载可用性缓存：{len(candidates_after_avail)} 个节点")
    elif skip_availability and not avail_cache_file.exists():
        # --skip-availability 且无缓存：将所有候选视为可用
        candidates_after_avail = list(candidates)
        avail_ip_info = {}
        latency_map = {r.node: r.latency for r in tcp_results}
        print(f"\n跳过可用性检测（无缓存），{len(candidates_after_avail)} 个节点全部进入带宽测速。")
    else:
        candidates_after_avail, avail_ip_info, avail_exit_details = run_availability_tests(candidates, config)
        with open(avail_cache_file, "wb") as f:  # type: ignore[assignment]
            pickle.dump((candidates_after_avail, latency_map), f)  # type: ignore[arg-type]
        print(f"可用性结果已缓存到 {avail_cache_file}")

    # 6. 带宽测速
    if skip_bandwidth:
        print(f"\n跳过带宽测速，直接使用可用性检测结果（{len(candidates_after_avail)} 个节点）。")
        bw_results = [(n, 0.0) for n in candidates_after_avail]
    else:
        bw_results_objects = run_speed_test_with_retry(candidates_after_avail, config)
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

    # 综合质量评分排序
    def quality_score(node: str) -> float:
        speed = speed_map.get(node, 0)
        lat = latency_map.get(node, float("inf"))
        if speed > 0 and lat != float("inf"):
            return float(speed) / (lat * 1000 + 1)
        elif speed > 0:
            return float(speed)
        elif lat != float("inf"):
            return 1.0 / (lat * 1000 + 1)
        return 0.0

    final_selected.sort(key=quality_score, reverse=True)

    # 打印摘要
    print_summary(len(candidates), len(tcp_results), len(candidates_after_avail), bw_results, final_selected, config)
    print_final_nodes(final_selected, speed_map, latency_map)

    # 8. 写入 ip.txt
    write_ip_txt(final_selected, config.OUTPUT_FILE, config, speed_map, latency_map)
    print(f"\n结果已保存到 {config.OUTPUT_FILE}（共 {len(final_selected)} 个节点）")

    # 保存历史记录（带时间戳的副本）
    _save_history(config.OUTPUT_FILE)

    # 9. Cloudflare DNS 更新
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
    for var, val in saved_proxy.items():
        if val is not None:
            os.environ[var] = val
        elif var in os.environ:
            del os.environ[var]
    os.environ.pop("NO_PROXY", None)

    # 11. GitHub 推送
    if config.GITHUB_SYNC_MAX_RETRIES > 0:
        push_to_github(config)

    print("\n测速完成！")


def _save_history(output_file: str) -> None:
    """保存带时间戳的历史记录副本"""
    import datetime
    script_dir = Path(__file__).parent
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
    return parser.parse_args()


def main() -> None:
    """入口点"""
    try:
        args = parse_args()
        load_config()  # 早期加载配置，验证配置完整性
        setup_logging(get_config())
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
