import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// 节点解析工具（对应旧版 fetcher 的解析函数）。
///
/// 解析结果统一为 `ip:port#CC` 格式字符串，与旧版保持一致，便于后续探测/测速复用。
class NodeParser {
  final Map<String, String> cnToCode;
  final Map<String, String> alpha3ToAlpha2;
  final Set<String> codeSet;

  NodeParser({
    required this.cnToCode,
    required this.alpha3ToAlpha2,
  }) : codeSet = {...cnToCode.values};

  /// 从任意标签提取标准两位国家代码。
  String? extractCountryCode(String label) {
    label = label.trim();
    if (label.isEmpty) return null;

    final direct = cnToCode[label];
    if (direct != null) return direct;

    final tokens = label.split(RegExp(r'[\s,;|/\-]+'));

    for (final token in tokens) {
      final cleaned = token.replaceAllMapped(
          RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), (m) => '');
      final cn = RegExp(r'^([\u4e00-\u9fff（）()]+)\d*$').firstMatch(cleaned);
      if (cn != null) {
        final code = cnToCode[cn.group(1)!.trim()];
        if (code != null) return code;
      }
    }

    for (final token in tokens) {
      final cleaned = token.replaceAll(RegExp(r'^[\d\s\-_.|#]+'), '').trim();
      final m3 = RegExp(r'^([A-Z]{3})(?![A-Za-z])').firstMatch(cleaned);
      if (m3 != null && alpha3ToAlpha2.containsKey(m3.group(1))) {
        return alpha3ToAlpha2[m3.group(1)];
      }
      final m2 = RegExp(r'^([A-Z]{2})(?![A-Za-z])').firstMatch(cleaned);
      if (m2 != null && codeSet.contains(m2.group(1))) {
        return m2.group(1);
      }
    }

    for (final token in tokens) {
      final noEmoji = token.replaceAllMapped(
          RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), (m) => '').trim();
      final cn = RegExp(r'^([\u4e00-\u9fff（）()]+)\d*$').firstMatch(noEmoji);
      if (cn != null) {
        final code = cnToCode[cn.group(1)!.trim()];
        if (code != null) return code;
      }
    }

    final emojiChars = <int>[];
    for (final r in label.runes) {
      if (r >= 0x1F1E6 && r <= 0x1F1FF) emojiChars.add(r);
    }
    if (emojiChars.length >= 2 && emojiChars.length.isEven) {
      final first = emojiChars[0] - 0x1F1E6;
      final second = emojiChars[1] - 0x1F1E6;
      if (first >= 0 && first <= 25 && second >= 0 && second <= 25) {
        return String.fromCharCode(first + 0x41) + String.fromCharCode(second + 0x41);
      }
    }
    return null;
  }

  /// 从纯文本提取标准节点。
  List<String> parseTextNodes(String text) {
    final nodes = <String>[];
    for (var token in text.split('\n')) {
      token = token.trim();
      if (token.isEmpty) continue;
      if (token.startsWith('#') || token.startsWith('//')) continue;

      String ipPort;
      String label;
      if (token.contains('#')) {
        final parts = token.split('#');
        if (parts.length < 2) continue;
        ipPort = parts[0].trim();
        label = parts.sublist(1).join('#').trim();
      } else {
        ipPort = token;
        label = '';
      }

      if (ipPort.startsWith('[')) continue;

      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ipPort)) {
        ipPort = '$ipPort:443';
      }
      if (RegExp(r'^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}$').hasMatch(ipPort)) {
        ipPort = '$ipPort:443';
      }

      if (RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(ipPort)) {
        final code = extractCountryCode(label);
        if (code != null) nodes.add('$ipPort#$code');
        continue;
      }

      if (RegExp(r'^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}:\d+$').hasMatch(ipPort)) {
        final idx = ipPort.lastIndexOf(':');
        final domain = ipPort.substring(0, idx);
        final port = ipPort.substring(idx + 1);
        try {
          final ip = InternetAddress(domain).address;
          final code = extractCountryCode(label);
          if (code != null) nodes.add('$ip:$port#$code');
        } on SocketException {
          // 解析失败忽略
        }
        continue;
      }
    }
    return nodes;
  }

  /// 递归从 JSON 结构提取节点。
  List<String> parseJsonNodes(dynamic data) {
    final nodes = <String>[];
    if (data is List) {
      for (final item in data) nodes.addAll(parseJsonNodes(item));
    } else if (data is Map) {
      for (final key in const ['nodes', 'data', 'result', 'list']) {
        if (data[key] is List) {
          nodes.addAll(parseJsonNodes(data[key]));
          break;
        }
      }
      final ip = data['ip'] ?? data['host'];
      final port = data['port'];
      final code = data['country'] ?? data['cc'];
      if (ip != null && port != null && code != null) {
        nodes.add('$ip:$port#${(code as String).toUpperCase()}');
      }
    } else if (data is String) {
      nodes.addAll(parseTextNodes(data));
    }
    return nodes;
  }

  /// 自适应解析：尝试 JSON，失败回退纯文本。
  List<String> parseAdaptive(String text) {
    text = text.trim();
    if (text.isEmpty) return [];
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final data = jsonDecode(text);
        return parseJsonNodes(data);
      } on FormatException {
        // 回退文本
      }
    }
    return parseTextNodes(text);
  }

  /// 从 RIPE announced-prefixes 响应提取 CIDR 前缀，按 IP 版本过滤。
  List<String> parseRipePrefixes(Map<String, dynamic> payload, bool ipv6) {
    final prefixes = (payload['data']?['prefixes'] as List?) ?? [];
    final result = <String>[];
    for (final item in prefixes) {
      final prefix = (item as Map)['prefix'];
      if (prefix == null) continue;
      final isV6 = prefix.contains(':');
      if (isV6 == ipv6) result.add(prefix as String);
    }
    return result;
  }

  /// 将 CIDR 前缀展开为 ip:port#CC 节点，按网段规模均匀采样。
  List<String> expandPrefixesToNodes(List<String> prefixes, int maxIps, int port, String country) {
    final target = maxIps;
    final networks = <_NetEntry>[];
    var totalHosts = 0;
    for (final pfx in prefixes) {
      final net = _parseCidr(pfx);
      if (net == null) continue;
      final hostCount = max(1, net.numAddresses);
      networks.add(_NetEntry._(net.first, net.last, net.numAddresses, hostCount));
      totalHosts += hostCount;
    }
    if (networks.isEmpty || totalHosts == 0) return [];

    final nodes = <String>[];
    for (final entry in networks) {
      var quota = max(1, (target * (entry.hostCount / totalHosts)).round());
      if (entry.numAddresses >= 65536) {
        final step = max(1, entry.numAddresses ~/ quota);
        final sampled = min(quota, (entry.numAddresses + step - 1) ~/ step);
        for (var i = 0; i < sampled; i++) {
          final ipInt = entry.first + i * step;
          if (ipInt > entry.last) break;
          nodes.add('${_intToIp(ipInt)}:$port#$country');
        }
      } else {
        // 小网段：跳过网络地址与广播地址（对应 Python net.hosts()）
        for (var ipInt = entry.first + 1; ipInt < entry.last && quota > 0; ipInt++) {
          nodes.add('${_intToIp(ipInt)}:$port#$country');
          quota--;
        }
      }
      if (nodes.length >= target) break;
    }
    return nodes.take(target).toList();
  }

  static _NetEntry? _parseCidr(String pfx) {
    final slash = pfx.indexOf('/');
    if (slash < 0) return null;
    final addr = pfx.substring(0, slash);
    final bits = int.tryParse(pfx.substring(slash + 1));
    if (bits == null) return null;
    final bytes = addr.split('.');
    if (bytes.length != 4) return null;
    var first = 0;
    for (final b in bytes) {
      final v = int.tryParse(b);
      if (v == null || v < 0 || v > 255) return null;
      first = (first << 8) | v;
    }
    final numAddresses = 1 << (32 - bits);
    final last = first + numAddresses - 1;
    return _NetEntry._(first, last, numAddresses, numAddresses);
  }

  static String _intToIp(int v) =>
      '${(v >> 24) & 0xff}.${(v >> 16) & 0xff}.${(v >> 8) & 0xff}.${v & 0xff}';

  /// 从打包的 assets/country_codes.json 构建 NodeParser。
  static Future<NodeParser> fromAssets(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    final data = jsonDecode(text) as Map<String, dynamic>;
    return NodeParser(
      cnToCode: Map<String, String>.from(data['CN_TO_CODE'] as Map),
      alpha3ToAlpha2: Map<String, String>.from(data['ALPHA3_TO_ALPHA2'] as Map),
    );
  }
}

class _NetEntry {
  final int first;
  final int last;
  final int numAddresses;
  final int hostCount;
  _NetEntry._(this.first, this.last, this.numAddresses, this.hostCount);
}
