import 'dart:io';

import '../config/app_config.dart';

/// 结果输出（对应旧版 output.py）。
class IpWriter {
  /// 生成 ip.txt：支持带宽/延迟附加信息、广告头/尾/逐行。
  static Future<String> writeIpTxt(
    List<String> finalNodes,
    String outputFile,
    AppConfig config, {
    Map<String, double>? speedMap,
    Map<String, double>? latencyMap,
  }) async {
    final buf = StringBuffer();
    if (config.adHeaderEnabled) {
      for (final line in config.adHeaderLines) buf.writeln(line);
    }
    for (final node in finalNodes) {
      var line = node;
      if (config.ipTxtShowBandwidth && speedMap != null && speedMap.containsKey(node)) {
        line += ' ${speedMap[node]!.toStringAsFixed(2)} Mbps';
      }
      if (config.ipTxtShowLatency && latencyMap != null && latencyMap.containsKey(node)) {
        line += ' ${(latencyMap[node]! * 1000).toStringAsFixed(2)} ms';
      }
      if (config.adPerlineEnabled && config.adPerlineText.isNotEmpty) {
        line += config.adPerlineText;
      }
      buf.writeln(line);
    }
    if (config.adFooterEnabled) {
      for (final line in config.adFooterLines) buf.writeln(line);
    }

    final file = File(outputFile);
    await file.create(recursive: true);
    await file.writeAsString(buf.toString());
    return file.path;
  }
}

/// 运行摘要（对应旧版 print_summary）。
class Summary {
  final int candidatesCount;
  final int tcpPassed;
  final int availabilityPassed;
  final List<(String, double)> speedResults;
  final List<String> finalSelected;

  Summary({
    required this.candidatesCount,
    required this.tcpPassed,
    required this.availabilityPassed,
    required this.speedResults,
    required this.finalSelected,
  });

  int get speedCount => speedResults.where((r) => r.$2 > 0).length;

  @override
  String toString() {
    return '''
==================================================
运行摘要：
  端口过滤后：$candidatesCount 个节点
  TCP 测试：$tcpPassed 个通过
  可用性检测：$availabilityPassed 个可用
  带宽测速：$speedCount 个有速度 / ${speedResults.length} 个总计
  最终选择：${finalSelected.length} 个节点
==================================================''';
  }
}
