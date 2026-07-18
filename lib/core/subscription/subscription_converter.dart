import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../config/app_config.dart';
import '../fetch/node_parser.dart';
import 'sub_parser.dart';

/// edgetunnel 系订阅器要求的 User-Agent（含项目特征串），用于触发
/// "优选订阅生成器(BEST_SUB)"模式并放行部分被 UA 拦截的实例。
const String edgetunnelUa = 'v2rayN/edgetunnel (https://github.com/cmliu/edgetunnel)';

const _supportedSchemes = [
  'vless://',
  'vmess://',
  'trojan://',
  'ss://',
  'hysteria2://',
  'hy2://',
  'tuic://',
];

/// 解码订阅内容：若已是明文链接则原样返回，否则尝试 base64 解码。
String decodeSubscription(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (t.contains('://')) return t;
  final decoded = SubParser.b64DecodeLoose(t);
  if (decoded != null && decoded.contains('://')) return decoded;
  return t;
}

/// 处理 sub://BASE64 形式的分享链接，解码出内部真实订阅地址。
/// 普通 http(s) 订阅地址原样返回。
String resolveSubUrl(String url) {
  final u = (url).trim();
  if (u.startsWith('sub://')) {
    final inner = SubParser.b64DecodeLoose(u.substring('sub://'.length).trim());
    if (inner != null) {
      final trimmed = inner.trim();
      if (trimmed.startsWith('http')) return trimmed;
    }
  }
  return u;
}

/// 把 "名称|域名" 或 "名称|域名|secret" 解析为 (name, host, secret)。
/// secret 为可选项：edgetunnel 部署的真实 uuid，或已算好的 token；
/// 提供后 [generatorFetchUrls] 会用它构造带鉴权的 /sub?token= 请求，
/// 以抓取"防范被抓取"的订阅器（如开启了 BEST_SUB 鉴权、未公开优选列表的实例）。
/// 仅写域名时 name=host，secret 为空。
(String, String, String) parseGenerator(String entry) {
  final e = (entry).trim();
  if (e.contains('|')) {
    final parts = e.split('|');
    final name = parts[0].trim();
    final host = parts[1].trim();
    final secret = parts.length > 2 ? parts[2].trim() : '';
    return (name, host, secret);
  }
  return (e, e, '');
}

/// edgetunnel /sub 的鉴权 token：md5(md5(host + userID))，host 与 userID 均小写。
/// 对应 worker 源码 `MD5MD5(host + userID)`（host 取请求域名，userID 为部署的 UUID）。
String edgetunnelToken(String host, String userID) {
  final s = '${host.trim().toLowerCase()}${userID.trim().toLowerCase()}';
  final inner = crypto.md5.convert(utf8.encode(s)).toString();
  return crypto.md5.convert(utf8.encode(inner)).toString();
}

bool _looksLikeUuid(String s) =>
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
        .hasMatch(s);

/// 为某个候选订阅器构造待尝试的拉取 URL（按优先级排列）。
/// 直连 URL（含路径）直接返回；否则依次尝试：
///   [secret 提供时] /sub?token=...  →
///   /sub?host=&uuid=（BEST_SUB 公开优选触发）→ /auto → /sub?token=auto。
/// [secret] 可选：edgetunnel 部署的真实 uuid 或已算好的 token。
/// 提供 uuid 时会按 worker 逻辑算 token = md5(md5(host + uuid))。
List<String> generatorFetchUrls(String host, AppConfig config, {String? secret}) {
  var h = host.trim();
  if (RegExp(r'^https?://[^/]+/.+').hasMatch(h)) return [h];
  if (h.startsWith('https://')) {
    h = h.substring('https://'.length);
  } else if (h.startsWith('http://')) {
    h = h.substring('http://'.length);
  }
  h = h.replaceAll(RegExp(r'/+\$'), '');
  if (h.isEmpty) return [];

  final fakeHost = (config.subNodeHost.isNotEmpty ? config.subNodeHost : 'example.com').trim();
  final fakeUuid = (config.subNodeUuid.isNotEmpty
          ? config.subNodeUuid
          : '00000000-0000-0000-0000-000000000000')
      .trim();
  final base = 'https://$h';
  final qHost = Uri.encodeQueryComponent(fakeHost);
  final qUuid = Uri.encodeQueryComponent(fakeUuid);
  final urls = <String>[];
  // 带鉴权的 edgetunnel 部署：用 secret 构造 /sub?token= 请求，用于抓取防范被抓取的实例。
  if (secret != null && secret.isNotEmpty) {
    final token = _looksLikeUuid(secret) ? edgetunnelToken(h, secret) : secret;
    urls.add('$base/sub?token=${Uri.encodeQueryComponent(token)}');
  }
  urls.addAll([
    '$base/sub?host=$qHost&uuid=$qUuid',
    '$base/auto',
    '$base/sub?token=auto',
  ]);
  return urls;
}

/// 收集订阅转换任务：[(来源名, [待尝试URL...]), ...]。
/// node 模式：逐个候选订阅器；url 模式：每个订阅链接为一项；both：两者合并。
List<(String, List<String>)> collectSubscriptionTasks(AppConfig config) {
  final mode = config.subInputMode.trim().toLowerCase();
  final tasks = <(String, List<String>)>[];

  if (mode == 'node' || mode == 'both') {
    final disabled = config.subDisabledGenerators;
    final gens = config.subGenerators
        .where((e) => e.trim().isNotEmpty)
        .map(parseGenerator)
        .where((g) => !(disabled.contains(g.$1) || disabled.contains(g.$2)))
        .toList();
    if (gens.isNotEmpty) {
      tasks.addAll(gens.map((g) => (
            g.$1.isNotEmpty ? g.$1 : g.$2,
            generatorFetchUrls(g.$2, config, secret: g.$3.isNotEmpty ? g.$3 : null),
          )));
    }
  }

  if (mode == 'url' || mode == 'both') {
    final urls = config.subUrls.where((u) => u.trim().isNotEmpty).map((u) => u.trim()).toList();
    if (urls.isNotEmpty) tasks.add(('url', urls));
  }
  return tasks;
}

/// 单个 URL 的拉取函数签名：返回订阅原文（sub:// 已解码；节点链接原样返回）。
typedef SubFetcher = Future<String> Function(String url);

/// 拉取单个订阅链接/节点链接，返回其订阅原文。
/// - 支持的节点 scheme：直接返回（无需抓取）。
/// - sub:// 分享链接：先解码出内部地址再抓取。
/// - 其余 http(s)：正常抓取。
Future<String> fetchSingle(String url, SubFetcher fetch) async {
  if (_supportedSchemes.any((s) => url.startsWith(s))) return url;
  final real = resolveSubUrl(url);
  return fetch(real);
}

/// 并发尝试候选 URL，返回第一个能解码出节点链接的订阅原文。
/// 都没节点时返回首个非空兜底。
Future<String> fetchFirstWorking(List<String> urls, SubFetcher fetch) async {
  if (urls.isEmpty) return '';
  final results = await Future.wait(urls.map((u) async {
    try {
      return await fetchSingle(u, fetch);
    } on Object {
      return '';
    }
  }));
  String? fallback;
  for (final content in results) {
    if (content.isEmpty) continue;
    if (SubParser.parseSubscriptionLinks(decodeSubscription(content)).isNotEmpty) {
      return content;
    }
    fallback ??= content;
  }
  return fallback ?? '';
}

/// 转换所有候选订阅器/订阅链接为标准 IP:port#CC 节点列表（去重）。
///
/// 返回 (节点列表, 节点->来源映射)。[fetch] 注入真实 HTTP 拉取；
/// [resolve] 注入域名解析（返回 IP 或 null）。[parser] 用于从节点名提取国家码。
Future<(List<String>, Map<String, String>)> convertSubscriptions(
  AppConfig config, {
  required SubFetcher fetch,
  required Future<String?> Function(String host) resolve,
  required NodeParser parser,
  void Function(String)? onLog,
}) async {
  final tasks = collectSubscriptionTasks(config);
  if (tasks.isEmpty) return (<String>[], <String, String>{});

  final rawNodes = <({String host, int port, String name, String source})>[];
  final state = <String, Map<String, dynamic>>{};
  final now = DateTime.now().millisecondsSinceEpoch / 1000;

    for (final (name, urls) in tasks) {
      final bodies = name == 'url'
          ? await Future.wait(urls.map((u) => fetchSingle(u, fetch)))
          : [await fetchFirstWorking(urls, fetch)];

      var got = 0;
      for (final content in bodies) {
        if (content.isEmpty) continue;
        final parsed = SubParser.parseSubscriptionLinks(decodeSubscription(content));
        if (parsed.isNotEmpty) {
          got += parsed.length;
          for (final p in parsed) {
            rawNodes.add((host: p.host, port: p.port, name: p.name, source: name));
          }
        }
      }
      if (got > 0) {
        onLog?.call('[+] $name 解析出 $got 个节点。');
      } else {
        onLog?.call('[-] $name：所有 URL 均拉取失败或未解析出节点。');
      }
      state[name] = {'ok': got > 0, 'nodes': got, 'ts': now};
    }

  if (rawNodes.isEmpty) return (<String>[], <String, String>{});

  final defaultCc = config.subDefaultCountry.toUpperCase();
  final hosts = <String>{for (final r in rawNodes) r.host};
  final resolved = <String, String?>{};
  if (config.subResolveDomain) {
    await Future.wait(hosts.map((h) async {
      resolved[h] = await resolve(h);
    }));
  } else {
    for (final h in hosts) {
      resolved[h] = _isIp(h) ? h : null;
    }
  }

  final nodes = <String>[];
  final seen = <String>{};
  final nodeSource = <String, String>{};
  for (final r in rawNodes) {
    final ip = resolved[r.host];
    if (ip == null || ip.isEmpty) {
      continue;
    }
    final cc = parser.extractCountryCode(r.name) ?? defaultCc;
    final node = cc.isEmpty ? '$ip:${r.port}' : '$ip:${r.port}#$cc';
    if (!seen.contains(ip)) {
      seen.add(ip);
      nodes.add(node);
      nodeSource[node] = r.source;
    }
  }

  onLog?.call(
      '订阅转换完成：共 ${rawNodes.length} 个节点 → 去重后 ${nodes.length} 个。');
  return (nodes, nodeSource);
}

bool _isIp(String host) {
  // 简易 IPv4/IPv6 判定（不依赖 dart:io 的 InternetAddress 以避免阻塞）
  if (host.contains(':')) {
    // IPv6（去掉可能的方括号）
    final h = host.replaceAll(RegExp(r'[\[\]]'), '');
    return h.contains(RegExp(r'^[0-9a-fA-F:]+$'));
  }
  final parts = host.split('.');
  if (parts.length != 4) return false;
  return parts.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255;
  });
}

/// 将订阅转换结果写入独立文件（LF 换行，便于 git 处理）。
Future<void> writeSubOutput(List<String> nodes, String outputFile) async {
  final f = File(outputFile);
  await f.create(recursive: true);
  final sink = f.openWrite(encoding: utf8, mode: FileMode.writeOnly);
  for (final node in nodes) {
    sink.write('$node\n');
  }
  await sink.flush();
  await sink.close();
}

String sourceMapPath(String outputFile) {
  final p = outputFile.replaceAll('\\', '/');
  final idx = p.lastIndexOf('/');
  final dir = idx >= 0 ? p.substring(0, idx + 1) : '';
  final stem = idx >= 0 ? p.substring(idx + 1) : p;
  final dot = stem.lastIndexOf('.');
  final base = dot > 0 ? stem.substring(0, dot) : stem;
  return '$dir${base}_src.json';
}

/// 将 节点->来源 映射写入独立 JSON 文件。
Future<void> writeSourceMap(Map<String, String> sourceMap, String outputFile) async {
  final path = sourceMapPath(outputFile);
  final f = File(path);
  await f.create(recursive: true);
  await f.writeAsString(jsonEncode(sourceMap), encoding: utf8, flush: true);
}

/// 读取 节点->来源 映射；文件不存在或损坏时返回空字典。
Future<Map<String, String>> loadSourceMap(String outputFile) async {
  final path = sourceMapPath(outputFile);
  final f = File(path);
  if (!f.existsSync()) return {};
  try {
    final data = jsonDecode(await f.readAsString(encoding: utf8));
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
  } catch (_) {}
  return {};
}
