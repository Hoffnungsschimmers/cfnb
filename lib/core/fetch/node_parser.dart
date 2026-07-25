import 'dart:convert';
import 'dart:io';

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
  ///
  /// 兼容多种格式：
  /// - `ip:port#CC` / `ip#CC` / `domain:port#CC`
  /// - `ip`（无端口，默认 443）
  /// - 测速结果格式 `ip [延迟 xx ms]` / `ip 延迟xxms` / `ip 12.3Mbps`（剥离注释取 IP）
  /// - 区域优先格式 `HK [延迟 xx ms]`（无 IP，跳过）
  List<String> parseTextNodes(String text) {
    final nodes = <String>[];
    final ipRe = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::(\d{1,5}))?');
    final domainRe =
        RegExp(r'([a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,})(?::(\d{1,5}))?');
    for (var token in text.split('\n')) {
      token = token.trim();
      if (token.isEmpty) continue;
      if (token.startsWith('#') || token.startsWith('//')) continue;

      // 拆分标签（# 之后为国家/备注）
      String body = token;
      String label = '';
      if (token.contains('#')) {
        final parts = token.split('#');
        body = parts[0].trim();
        label = parts.sublist(1).join('#').trim();
      }

      String? ipPort;
      final ipMatch = ipRe.firstMatch(body);
      if (ipMatch != null) {
        final ip = ipMatch.group(1)!;
        final port = ipMatch.group(2);
        ipPort = port != null ? '$ip:$port' : '$ip:443';
      } else {
        final dm = domainRe.firstMatch(body);
        if (dm != null) {
          final domain = dm.group(1)!;
          final port = dm.group(2);
          ipPort = port != null ? '$domain:$port' : '$domain:443';
        }
      }
      if (ipPort == null) continue; // 无 IP/域名（如纯区域注释）跳过

      if (RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(ipPort)) {
        final code = extractCountryCode(label.isEmpty ? body : label);
        if (code != null) nodes.add('$ipPort#$code');
        continue;
      }

      if (RegExp(r'^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}:\d+$').hasMatch(ipPort)) {
        final idx = ipPort.lastIndexOf(':');
        final domain = ipPort.substring(0, idx);
        final port = ipPort.substring(idx + 1);
        try {
          final ip = InternetAddress(domain).address;
          final code = extractCountryCode(label.isEmpty ? body : label);
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
      for (final item in data) {
        nodes.addAll(parseJsonNodes(item));
      }
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

