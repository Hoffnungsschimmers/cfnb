"""结果输出模块"""

from __future__ import annotations

from config import Config


def write_ip_txt(
    final_nodes: list[str],
    output_file: str,
    config: Config,
    speed_map: dict[str, float] | None = None,
    latency_map: dict[str, float] | None = None,
) -> None:
    """生成包含广告/带宽/延迟信息的 ip.txt"""
    with open(output_file, "w", encoding="utf-8") as f:
        if config.AD_HEADER_ENABLED:
            for line in config.AD_HEADER_LINES:
                f.write(line + "\n")

        for node in final_nodes:
            line = node
            if config.IP_TXT_SHOW_BANDWIDTH and speed_map and node in speed_map:
                line += f" {speed_map[node]:.2f} Mbps"
            if config.IP_TXT_SHOW_LATENCY and latency_map and node in latency_map:
                line += f" {latency_map[node] * 1000:.2f} ms"
            if config.AD_PERLINE_ENABLED and config.AD_PERLINE_TEXT:
                line += config.AD_PERLINE_TEXT
            f.write(line + "\n")

        if config.AD_FOOTER_ENABLED:
            for line in config.AD_FOOTER_LINES:
                f.write(line + "\n")


def print_summary(
    candidates_count: int,
    tcp_passed: int,
    availability_passed: int,
    speed_results: list[tuple[str, float]],
    final_selected: list[str],
    config: Config,
) -> None:
    """打印运行摘要"""
    speed_count = sum(1 for _, s in speed_results if s > 0)
    print(f"\n{'=' * 50}")
    print("运行摘要：")
    print(f"  端口过滤后：{candidates_count} 个节点")
    print(f"  TCP 测试：{tcp_passed} 个通过")
    print(f"  可用性检测：{availability_passed} 个可用")
    print(f"  带宽测速：{speed_count} 个有速度 / {len(speed_results)} 个总计")
    print(f"  最终选择：{len(final_selected)} 个节点")
    print(f"{'=' * 50}")


def print_final_nodes(final_selected: list[str], speed_map: dict[str, float], latency_map: dict[str, float]) -> None:
    """打印最终优选节点"""
    print("\n================ 最终优选节点 ================")
    for i, node in enumerate(final_selected, 1):
        speed = speed_map.get(node, 0)
        lat_sec = latency_map.get(node, float("inf"))
        if lat_sec != float("inf"):
            print(f"{i}. {node} 速度 {speed:.2f} Mbps 延迟 {lat_sec * 1000:.2f} ms")
        else:
            print(f"{i}. {node} 速度 {speed:.2f} Mbps")
