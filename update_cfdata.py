#!/usr/bin/env python3
"""CFData 更新脚本：扫描 Cloudflare 官方网段，转换格式，合并去重"""

import json
import os
import re
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CFDATA_EXE = os.path.join(SCRIPT_DIR, "cfdata.exe")
CFDATA_IPS = os.path.join(SCRIPT_DIR, "cfdata_ips.txt")
TEMP_FILE = os.path.join(SCRIPT_DIR, "cfdata_temp.txt")

# 加载完整的 DC→国家映射（来自 locations.json）
DC_MAP_FILE = os.path.join(SCRIPT_DIR, "dc_country_map.json")


def load_dc_map():
    if os.path.exists(DC_MAP_FILE):
        with open(DC_MAP_FILE) as f:
            return json.load(f)
    # 备用映射
    return {
        "NRT": "JP",
        "HND": "JP",
        "ICN": "KR",
        "HKG": "HK",
        "SIN": "SG",
        "TPE": "TW",
        "LAX": "US",
        "SJC": "US",
        "ORD": "US",
        "IAD": "US",
        "FRA": "DE",
        "LHR": "GB",
        "AMS": "NL",
        "CDG": "FR",
        "SYD": "AU",
    }


def convert_dc_to_country(lines):
    """将 DC 代码转换为国家代码（使用完整映射表）"""
    dc_map = load_dc_map()
    result = []
    for line in lines:
        newline = line
        for dc, country in dc_map.items():
            newline = newline.replace(f"#{dc}", f"#{country}")
        result.append(newline)
    return result


def _parse_progress(line, dc, last_print):
    """解析进度行并显示，返回是否已打印"""
    if "[" not in line:
        return False, last_print

    # 格式0: [DC代码] : X/Y (Z%) - cfdata.exe 输出格式，如 [NRT] : 737/967 (76.22%)
    m = re.search(r"\[(\w+)\]\s*[：:]\s*(\d+)/(\d+)\s*\(([\d.]+)%\)", line)
    if m:
        dc_code, current, total, pct = m.groups()
        print(f"  [{dc}] 进度: {current}/{total} ({pct}%)", flush=True)
        return True, last_print

    # 格式1: [X/Y Z%] - 带百分比的进度
    m = re.search(r"\[(\d+)/(\d+)\s+([\d.]+)%\]", line)
    if m:
        current, total, pct = m.groups()
        print(f"  [{dc}] 进度: {current}/{total} ({pct}%)", flush=True)
        return True, last_print

    # 格式2: [X/Y] 描述文字 - 不带百分比的进度
    m = re.search(r"\[(\d+)/(\d+)\]\s*([^\d%]*)", line)
    if m:
        current, total, desc = m.groups()
        pct = float(current) / float(total) * 100 if float(total) > 0 else 0
        print(f"  [{dc}] 进度: {current}/{total} ({pct:.0f}%) {desc.strip()}", flush=True)
        return True, last_print

    return False, last_print


def _is_key_message(line):
    """检查是否为关键信息（完成、错误等）"""
    lower = line.lower()
    # 排除帮助信息和说明文字
    if any(kw in lower for kw in ["说明", "默认", "用法", "参数", "选项", "help", "usage"]):
        return False
    return any(kw in lower for kw in [
        "complete", "done", "finish", "error", "fail", "found",
        "完成", "错误", "失败", "成功", "结果",
    ])


def scan_datacenter(dc, dc_index, dc_total):
    """扫描单个数据中心，返回节点列表"""
    print(f"\n[{dc_index}/{dc_total}] 扫描数据中心 {dc}...")
    temp_out = os.path.join(SCRIPT_DIR, f"cfdata_{dc}.txt")

    try:
        # Windows 下隐藏黑框
        startupinfo = None
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = 0  # SW_HIDE

        proc = subprocess.Popen(
            [CFDATA_EXE, "-cli", f"-dc={dc}", f"-out={temp_out}", "-format=txt", "-nocolor", "-speedlimit=0"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            encoding="utf-8",
            errors="ignore",
            startupinfo=startupinfo,
        )
        proc.stdin.write("y\n")
        proc.stdin.flush()

        # 实时读取输出并显示进度
        last_print = time.time()
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            printed, last_print = _parse_progress(line, dc, last_print)
            if not printed and _is_key_message(line):
                print(f"\n  [{dc}] {line}")

        proc.wait(timeout=600)
        print()  # 换行

        # 读取结果文件
        if os.path.exists(temp_out):
            with open(temp_out, encoding="utf-8") as f:
                lines = [line.strip() for line in f if re.match(r"\d+\.\d+\.\d+\.\d+:\d+", line.strip())]
            print(f"  [OK] {dc}: {len(lines)} 个节点")
            os.remove(temp_out)
            return lines
        else:
            print(f"  [FAIL] {dc}: 无输出")
            return []
    except Exception as e:
        print(f"  [ERROR] {dc}: 失败 - {e}")
        return []


def main():
    if not os.path.exists(CFDATA_EXE):
        print(f"错误：找不到 {CFDATA_EXE}")
        sys.exit(1)

    # 扫描主要数据中心（覆盖全球主要区域）
    dcs = ["NRT", "HND", "ICN", "HKG", "SIN", "TPE", "LAX", "SJC", "ORD", "IAD", "FRA", "LHR", "AMS", "CDG", "SYD"]
    all_lines = []

    for i, dc in enumerate(dcs, 1):
        lines = scan_datacenter(dc, i, len(dcs))
        all_lines.extend(lines)

    if not all_lines:
        print("扫描无结果")
        sys.exit(1)

    # 转换 DC 代码为国家代码
    converted = convert_dc_to_country(all_lines)

    # 合并旧数据
    old_nodes = set()
    if os.path.exists(CFDATA_IPS):
        with open(CFDATA_IPS, encoding="utf-8") as f:
            old_nodes = {line.strip() for line in f if line.strip()}

    new_nodes = set(converted)
    all_nodes = old_nodes | new_nodes
    added = len(new_nodes - old_nodes)

    # 保存
    with open(CFDATA_IPS, "w", encoding="utf-8") as f:
        for n in sorted(all_nodes):
            f.write(n + "\n")

    print("\n更新完成：")
    print(f"  旧数据：{len(old_nodes)} 个")
    print(f"  新扫描：{len(new_nodes)} 个")
    print(f"  新增：{added} 个")
    print(f"  合计：{len(all_nodes)} 个")
    print(f"  已保存到 {CFDATA_IPS}")


if __name__ == "__main__":
    main()
