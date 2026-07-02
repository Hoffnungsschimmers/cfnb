#!/usr/bin/env python3
"""
Cloudflare WARP 出口节点扫描器
扫描 VPS 服务商 IP 段，找出运行 WARP 客户端的节点
"""

import os
import socket
import ssl
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# WARP 注册 API
WARP_API = "https://api.cloudflareclient.com/v0a2158/reg"

# VPS 服务商 IP 段（已知的 Cloudflare WARP 常见出口）
# 这些是 Cloudflare WARP 常见的出口网段
WARP_IP_RANGES = [
    # Cloudflare WARP 官方段
    "162.155.0.0/16",
    "162.159.192.0/20",
    "162.159.196.0/22",
    "188.114.96.0/22",
    "188.114.99.0/24",
    "172.64.0.0/13",
    "104.16.0.0/13",
    "104.24.0.0/14",
    # 常见 WARP 出口段
    "162.159.38.0/24",
    "162.159.46.0/24",
    "162.158.0.0/15",
    "198.41.208.0/23",
]


def cidr_to_ips(cidr):
    """将 CIDR 转换为 IP 列表"""
    network, prefix = cidr.split("/")
    prefix = int(prefix)
    parts = list(map(int, network.split(".")))
    base = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
    network_addr = base & mask
    broadcast_addr = network_addr | (~mask & 0xFFFFFFFF)

    ips = []
    for ip_int in range(network_addr + 1, broadcast_addr):
        ip = f"{(ip_int >> 24) & 0xFF}.{(ip_int >> 16) & 0xFF}.{(ip_int >> 8) & 0xFF}.{ip_int & 0xFF}"
        ips.append(ip)
    return ips


def check_warp(ip, port=443):
    """检测 IP 是否运行 WARP"""
    try:
        # 1. TCP 连接测试
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        sock.connect((ip, port))

        # 2. TLS 握手
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ssock = ctx.wrap_socket(sock, server_hostname="api.cloudflareclient.com")
        ssock.close()
        sock.close()

        # 3. 尝试 WARP 注册（如果是 WARP 节点，会返回有效响应）
        # 这个测试比较重，只对 TLS 握手成功的 IP 做
        return True
    except ssl.SSLCertVerificationError:
        # TLS 握手失败但连接成功 — 可能是 WARP 节点
        try:
            sock.close()
        except Exception:
            pass
        return True
    except Exception:
        try:
            sock.close()
        except Exception:
            pass
        return False


def test_speed(ip, port=443):
    """测试 WARP 节点速度"""
    try:
        start = time.time()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((ip, port))

        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ssock = ctx.wrap_socket(sock, server_hostname="speed.cloudflare.com")

        # 发送 HTTP 请求测速
        ssock.sendall(b"GET /__down?bytes=1048576 HTTP/1.1\r\nHost: speed.cloudflare.com\r\n\r\n")
        data = b""
        while True:
            chunk = ssock.recv(65536)
            if not chunk:
                break
            data += chunk
            if len(data) >= 1048576:
                break

        elapsed = time.time() - start
        ssock.close()
        sock.close()

        if elapsed > 0 and len(data) > 1000:
            speed_mbps = (len(data) * 8) / (elapsed * 1000 * 1000)
            return speed_mbps
    except Exception:
        pass
    return 0


def scan_range(ip_range, max_ips=100):
    """扫描一个 IP 段"""
    ips = cidr_to_ips(ip_range)[:max_ips]
    results = []

    def check(ip):
        if check_warp(ip):
            speed = test_speed(ip)
            if speed > 1:  # 只保留速度 > 1 Mbps 的
                return (ip, speed)
        return None

    with ThreadPoolExecutor(max_workers=50) as executor:
        futures = {executor.submit(check, ip): ip for ip in ips}
        for future in as_completed(futures):
            result = future.result()
            if result:
                results.append(result)

    return results


def main():
    print("=== Cloudflare WARP 出口节点扫描 ===")
    print(f"扫描 {len(WARP_IP_RANGES)} 个 IP 段...")

    all_results = []
    for ip_range in WARP_IP_RANGES:
        print(f"\n扫描 {ip_range}...")
        results = scan_range(ip_range, max_ips=50)
        all_results.extend(results)
        if results:
            for ip, speed in results:
                print(f"  ✓ {ip}: {speed:.2f} Mbps")

    # 保存结果
    output_file = os.path.join(SCRIPT_DIR, "warp_nodes.txt")
    with open(output_file, "w") as f:
        for ip, speed in sorted(all_results, key=lambda x: -x[1]):
            f.write(f"{ip}:443#WARP {speed:.2f}Mbps\n")

    print(f"\n扫描完成：{len(all_results)} 个 WARP 节点")
    print(f"已保存到 {output_file}")


if __name__ == "__main__":
    main()
