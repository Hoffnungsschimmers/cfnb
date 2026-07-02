"""GitHub 推送模块"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

from config import Config


def push_to_github(config: Config) -> bool:
    """推送 ip.txt 到 GitHub"""
    script_dir = Path(__file__).parent

    if sys.platform == "win32":
        script_name = "git_sync.ps1"
        interpreter = ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]
        creationflags = subprocess.CREATE_NO_WINDOW
    else:
        script_name = "git_sync.sh"
        interpreter = ["bash"]
        creationflags = 0

    script_path = script_dir / "scripts" / script_name
    if not script_path.exists():
        print(f"未找到 {script_name}，跳过 GitHub 同步。")
        return False

    if sys.platform != "win32":
        try:
            os.chmod(script_path, 0o755)
        except Exception:
            pass

    for attempt in range(1, config.GITHUB_SYNC_MAX_RETRIES + 1):
        print(f"\n正在同步到 GitHub (尝试 {attempt}/{config.GITHUB_SYNC_MAX_RETRIES})...")
        try:
            cmd = interpreter + [str(script_path)]
            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, creationflags=creationflags
            )

            try:
                stdout, stderr = process.communicate(timeout=config.GIT_SYNC_PROCESS_TIMEOUT)
                if stdout:
                    print(stdout.strip())
                if process.returncode == 0:
                    print("已自动推送到 GitHub。")
                    return True
                else:
                    print(f"推送失败 (退出码 {process.returncode})")
                    if stderr:
                        print(f"错误信息: {stderr.strip()}")
            except subprocess.TimeoutExpired:
                process.kill()
                print(f"推送超时（超过 {config.GIT_SYNC_PROCESS_TIMEOUT} 秒）")
        except Exception as e:
            print(f"推送过程异常: {e}")

        if attempt < config.GITHUB_SYNC_MAX_RETRIES:
            print(f"等待 {config.GITHUB_SYNC_RETRY_DELAY} 秒后重试...")
            time.sleep(config.GITHUB_SYNC_RETRY_DELAY)

    print(f"已尝试 {config.GITHUB_SYNC_MAX_RETRIES} 次推送，均失败，请检查网络或 GitHub 仓库状态。")
    return False
