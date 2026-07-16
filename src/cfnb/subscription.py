"""订阅转换模块 - 从机场/订阅链接中提取节点 IP 列表

流程：拉取订阅 → base64 解码 → 解析 vless/vmess/trojan 等链接 →
提取 address:port + 国家 → 域名解析为 IP（失败丢弃）→ 输出 IP:port#CC 兼容格式。
"""

from __future__ import annotations

import base64
import ipaddress
import json
import re
import socket
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

import httpx

from cfnb.config import Config
from cfnb.fetcher import extract_country_code


def _gen_state_path() -> Path:
    """订阅器最近一次运行状态落盘文件（与 config.json 同目录）。"""
    return Path(__file__).parent.parent.parent / "state" / "generators_state.json"


def load_generators_state() -> dict:
    """返回 {订阅器名称: {"ok": bool, "nodes": int, "ts": float}}。"""
    p = _gen_state_path()
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_generators_state(state: dict) -> None:
    p = _gen_state_path()
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass

# 支持的代理协议前缀
SUPPORTED_SCHEMES = ("vless://", "vmess://", "trojan://", "ss://", "hysteria2://", "hy2://", "tuic://")

# edgetunnel 系订阅器要求的 User-Agent（含项目特征串），用于触发
# "优选订阅生成器(BEST_SUB)"模式并放行部分被 UA 拦截的实例。
EDGETUNNEL_UA = "v2rayN/edgetunnel (https://github.com/cmliu/edgetunnel)"


def _b64decode_loose(text: str) -> str | None:
    """宽松 base64 解码，兼容标准/URL-safe 及缺失填充"""
    s = "".join(text.split())
    if not s:
        return None
    padded = s + "=" * (-len(s) % 4)
    for decoder in (base64.b64decode, base64.urlsafe_b64decode):
        try:
            return decoder(padded).decode("utf-8", errors="ignore")
        except Exception:
            continue
    return None


def decode_subscription(text: str) -> str:
    """解码订阅内容：若已是明文链接则原样返回，否则尝试 base64 解码"""
    text = text.strip()
    if not text:
        return ""
    if "://" in text:
        return text
    decoded = _b64decode_loose(text)
    if decoded and "://" in decoded:
        return decoded
    return text


def _is_ip(host: str) -> bool:
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


def _parse_vmess(link: str) -> tuple[str, int, str] | None:
    """解析 vmess://<base64 json>，返回 (host, port, name)"""
    payload = link[len("vmess://") :].strip()
    decoded = _b64decode_loose(payload)
    if not decoded:
        return None
    try:
        data = json.loads(decoded)
    except (json.JSONDecodeError, ValueError):
        return None
    host = str(data.get("add", "")).strip()
    port = data.get("port")
    name = str(data.get("ps", "")).strip()
    if not host or port is None:
        return None
    try:
        port_int = int(str(port).strip())
    except (ValueError, TypeError):
        return None
    return host, port_int, name


def _parse_uri_style(link: str) -> tuple[str, int, str] | None:
    """解析 vless/trojan/ss/... 形如 scheme://user@host:port?params#name"""
    try:
        parsed = urlparse(link)
    except ValueError:
        return None

    host = parsed.hostname
    port = parsed.port

    # ss:// 可能是 ss://base64(method:pass@host:port)#name 形式
    if host is None and link.startswith("ss://"):
        body = link[len("ss://") :]
        frag = ""
        if "#" in body:
            body, frag = body.split("#", 1)
        decoded = _b64decode_loose(body.split("?")[0])
        if decoded and "@" in decoded:
            hostport = decoded.rsplit("@", 1)[-1]
            if ":" in hostport:
                h, _, p = hostport.rpartition(":")
                host = h.strip("[]")
                try:
                    port = int(p)
                except ValueError:
                    return None
        name = unquote(frag).strip()
        if host and port:
            return host, port, name
        return None

    if not host or not port:
        return None

    name = unquote(parsed.fragment).strip()
    # 部分协议把国家信息放在 query 的 remarks/sni 等字段，name 为空时兜底尝试
    if not name:
        qs = parse_qs(parsed.query)
        for key in ("remarks", "remark", "name"):
            if key in qs and qs[key]:
                name = unquote(qs[key][0]).strip()
                break
    return host, port, name


def parse_subscription_links(text: str) -> list[tuple[str, int, str]]:
    """从订阅明文中解析出所有节点，返回 (host, port, name) 列表"""
    results: list[tuple[str, int, str]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or not line.startswith(SUPPORTED_SCHEMES):
            continue
        parsed: tuple[str, int, str] | None
        if line.startswith("vmess://"):
            parsed = _parse_vmess(line)
        else:
            parsed = _parse_uri_style(line)
        if parsed:
            results.append(parsed)
    return results


def _resolve_sub_url(url: str) -> str:
    """处理 sub://BASE64 形式的分享链接，解码出内部真实的订阅地址

    普通的 https:// 订阅地址原样返回。
    """
    url = (url or "").strip()
    if url.startswith("sub://"):
        inner = _b64decode_loose(url[len("sub://") :].strip())
        if inner:
            inner = inner.strip()
            if inner.startswith("http"):
                return inner
    return url


def fetch_subscription(url: str, config: Config) -> str:
    """拉取单个订阅链接的原始内容（带重试）

    支持 sub://BASE64 分享链接（解码出内部真实地址后再抓取）。
    """
    url = _resolve_sub_url(url)
    for attempt in range(1, config.SUB_FETCH_MAX_RETRIES + 1):
        try:
            resp = httpx.get(
                url,
                timeout=httpx.Timeout(config.SUB_FETCH_TIMEOUT, connect=config.SUB_FETCH_CONNECT_TIMEOUT),
                follow_redirects=True,
                headers={"User-Agent": EDGETUNNEL_UA},
            )
            resp.raise_for_status()
            return resp.text
        except Exception as e:
            if attempt < config.SUB_FETCH_MAX_RETRIES:
                time.sleep(config.SUB_FETCH_RETRY_DELAY)
            else:
                print(f"[-] 拉取订阅失败 {url}（已重试 {config.SUB_FETCH_MAX_RETRIES} 次）: {e}")
    return ""


def _resolve_host(host: str) -> str | None:
    """将主机名解析为 IP；若本身就是 IP 则原样返回，解析失败返回 None"""
    if _is_ip(host):
        return host
    try:
        return socket.gethostbyname(host)
    except Exception:
        return None


def parse_generator(entry: str) -> tuple[str, str]:
    """把 "名称|域名" 解析为 (name, host)；仅写域名时 name=host

    若 host 本身是完整 URL（含 http(s)://），则按"直连 URL"处理，
    例如 "Mia真|https://sub.xxx/abcdef" 会原样抓取该地址。
    """
    entry = (entry or "").strip()
    if "|" in entry:
        name, host = entry.split("|", 1)
        return name.strip(), host.strip()
    return entry, entry


def generator_fetch_urls(host: str, config: Config) -> list[str]:
    """为某个候选订阅器构造待尝试的拉取 URL（按优先级排列）

    - 若 host 是完整 URL（含 http(s)://），直接返回该 URL（直连模式）。
    - 否则按以下顺序尝试：
      1) /sub?host=<fake>&uuid=<fake>  —— sub.us.ci 等需要显式节点的实例
      2) /auto                          —— 多数公益订阅器默认 token 返回内置节点
      3) /sub?token=auto                —— 另一种默认 token 写法
    convert 时取第一个能解析出节点的。
    """
    host = host.strip()
    # 直连 URL 模式：本身是完整订阅地址（含路径），例如
    # https://sub.xxx/abcdef 或 https://sub.xxx/sub?token=xxx
    if re.match(r"^https?://[^/]+/.+", host):
        return [host]
    if host.startswith("https://"):
        host = host[len("https://"):]
    elif host.startswith("http://"):
        host = host[len("http://"):]
    host = host.rstrip("/")
    if not host:
        return []
    fake_host = (config.SUB_NODE_HOST or "example.com").strip()
    fake_uuid = (config.SUB_NODE_UUID or "00000000-0000-0000-0000-000000000000").strip()
    base = f"https://{host}"
    return [
        f"{base}/sub?host={quote(fake_host)}&uuid={quote(fake_uuid)}",
        f"{base}/auto",
        f"{base}/sub?token=auto",
    ]


def collect_subscription_tasks(config: Config) -> list[tuple[str, list[str]]]:
    """返回 [(来源名, [待尝试URL...]), ...]

    node 模式：逐个候选订阅器，每个构造多个候选 URL；
    url  模式：每个订阅链接作为一个任务；
    both 模式：以上两者都收集并合并（默认）。
    """
    mode = (config.SUB_INPUT_MODE or "both").strip().lower()

    gen_tasks: list[tuple[str, list[str]]] = []
    if mode in ("node", "both"):
        disabled = set(getattr(config, "SUB_DISABLED_GENERATORS", set()) or set())
        gens = [parse_generator(e) for e in config.SUB_GENERATORS if e and e.strip()]
        if gens:
            gen_tasks = [
                (name or host, generator_fetch_urls(host, config))
                for name, host in gens
                if (name or host) not in disabled
            ]
        elif mode == "node":
            print("订阅转换（节点模式）未配置任何候选订阅器（SUB_GENERATORS 为空）。")

    url_tasks: list[tuple[str, list[str]]] = []
    if mode in ("url", "both"):
        urls = [u.strip() for u in config.SUB_URLS if u and u.strip()]
        if urls:
            url_tasks = [("url", urls)]
        elif mode == "url":
            print("未配置任何订阅链接（SUB_URLS 为空）。")

    return gen_tasks + url_tasks


def fetch_single(url: str, config: Config) -> str:
    """拉取单个订阅链接/节点链接，返回其订阅原文

    - http(s) 订阅地址：正常抓取；
    - sub:// 分享链接：先解码出内部地址再抓取；
    - 直接的 vless:// / vmess:// / trojan:// ... 节点链接：无需抓取，
      直接作为订阅原文返回（用于"现成节点"直接取 IP 的场景）。
    """
    if url.startswith(SUPPORTED_SCHEMES):
        return url
    real = _resolve_sub_url(url)
    return fetch_subscription(real, config)


def fetch_first_working(urls: list[str], config: Config) -> str:
    """依次尝试候选 URL，返回第一个能解码出节点链接的订阅原文

    用于候选订阅器场景：多个 URL 是同一来源的回退地址，取第一个可用的即可。
    """
    best = ""
    for url in urls:
        content = fetch_single(url, config)
        if not content:
            continue
        decoded = decode_subscription(content)
        if parse_subscription_links(decoded):
            return content
        # 没解析到节点也先留着，作为兜底
        if not best:
            best = content
    return best


def convert_subscriptions(config: Config) -> list[str]:
    """转换所有候选订阅器 / 订阅链接为标准 IP:port#CC 节点列表（去重）"""
    tasks = collect_subscription_tasks(config)
    if not tasks:
        return []

    print(f"开始从 {len(tasks)} 个来源提取节点...")

    raw_nodes: list[tuple[str, int, str, str]] = []
    state: dict = {}
    now = time.time()
    for name, urls in tasks:
        # 候选订阅器(name 非 'url')：多个 URL 是同一来源的回退，取第一个可用；
        # 现成订阅链接(name == 'url')：每个 URL 都是独立订阅，必须全部抓取并合并。
        # name 即节点来源名（如 CM / IDK / url），用于延迟优选结果中标注来源。
        if name == "url":
            bodies = [fetch_single(u, config) for u in urls]
        else:
            bodies = [fetch_first_working(urls, config)]
        got = 0
        for content in bodies:
            if not content:
                continue
            parsed = parse_subscription_links(decode_subscription(content))
            if parsed:
                got += len(parsed)
                raw_nodes.extend((h, p, n, name) for (h, p, n) in parsed)
        if got == 0:
            print(f"[-] {name}：所有 URL 均拉取失败或未解析出节点。")
        else:
            print(f"[+] {name} 解析出 {got} 个节点。")
        # 记录单个订阅器最近一次运行状态（供管理面板展示）
        state[name] = {"ok": got > 0, "nodes": got, "ts": now}

    if not raw_nodes:
        print("订阅中未解析出任何节点。")
        return []

    default_cc = config.SUB_DEFAULT_COUNTRY.upper()

    # 唯一化 host，避免同名域名重复解析
    hosts = {host for host, _port, _name, _src in raw_nodes}
    resolved: dict[str, str | None] = {}

    if config.SUB_RESOLVE_DOMAIN:
        with ThreadPoolExecutor(max_workers=config.SUB_RESOLVE_WORKERS) as executor:
            futures = {executor.submit(_resolve_host, h): h for h in hosts}
            for future in as_completed(futures):
                h = futures[future]
                try:
                    resolved[h] = future.result()
                except Exception:
                    resolved[h] = None
    else:
        for h in hosts:
            resolved[h] = h if _is_ip(h) else None

    nodes: list[str] = []
    seen: set[str] = set()
    dropped = 0
    node_source: dict[str, str] = {}
    for host, port, name, source in raw_nodes:
        ip = resolved.get(host)
        if not ip:
            dropped += 1
            continue
        cc = extract_country_code(name) or default_cc
        node = f"{ip}:{port}#{cc}"
        # 按 IP 去重：同一 IP 出现在不同端口/不同来源时只保留第一条
        if ip not in seen:
            seen.add(ip)
            nodes.append(node)
            node_source[node] = source

    print(f"订阅转换完成：共 {len(raw_nodes)} 个节点 → 去重后 {len(nodes)} 个（丢弃无法解析 {dropped} 个）。")
    # 合并并落盘订阅器运行状态（保留历史记录中本次未出现的来源）
    prev = load_generators_state()
    prev.update(state)
    save_generators_state(prev)
    return nodes, node_source


def write_sub_output(nodes: list[str], output_file: str) -> None:
    """将订阅转换结果写入独立文件（与 ip.txt 分开存放）

    显式使用 newline="\n" 写入 LF 换行，避免 Windows 下写成 CRLF 导致
    git add 报 "CRLF would be replaced by LF" 而未能暂存/推送。
    """
    with open(output_file, "w", encoding="utf-8", newline="\n") as f:
        for node in nodes:
            f.write(node + "\n")


def _source_map_path(output_file: str) -> str:
    """根据订阅输出文件名推导出配套的 节点->来源 映射文件路径。

    例如 addressesapi.txt → addressesapi_src.json（与输出文件同目录）。
    """
    p = Path(output_file)
    return str(p.parent / (p.stem + "_src.json"))


def write_source_map(source_map: dict[str, str], output_file: str) -> None:
    """将 节点->来源 映射写入独立 JSON 文件，供延迟优选步骤在结果中标注来源。"""
    path = _source_map_path(output_file)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(source_map, f, ensure_ascii=False, indent=2)


def load_source_map(output_file: str) -> dict[str, str]:
    """读取 节点->来源 映射；文件不存在或损坏时返回空字典。"""
    path = _source_map_path(output_file)
    if not Path(path).exists():
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}
