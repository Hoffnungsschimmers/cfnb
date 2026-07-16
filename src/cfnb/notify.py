"""通知模块"""

from __future__ import annotations

import httpx
from cfnb.config import Config


def send_notification(title: str, content: str, config: Config) -> None:
    """发送消息通知到已启用的渠道"""
    if config.ENABLE_WXPUSHER:
        send_wxpusher_notification(title, content, config)


def send_wxpusher_notification(title: str, content: str, config: Config) -> None:
    """通过 WxPusher 发送消息"""
    if not config.WXPUSHER_APP_TOKEN or config.WXPUSHER_APP_TOKEN == "your_app_token_here":
        print("[通知] WxPusher 凭证未配置，跳过发送。")
        return

    payload = {
        "appToken": config.WXPUSHER_APP_TOKEN,
        "content": f"### {title}\n\n{content}",
        "summary": title,
        "contentType": 3,  # Markdown 格式
        "uids": config.WXPUSHER_UIDS,
    }

    try:
        resp = httpx.post(config.WXPUSHER_API_URL, json=payload, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") == 1000:
            print("[通知] WxPusher 消息发送成功！")
        else:
            print(f"[通知] WxPusher 发送失败: {data.get('msg')}")
    except Exception as e:
        print(f"[通知] WxPusher 发送异常: {e}")
