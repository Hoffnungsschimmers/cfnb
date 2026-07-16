import 'dart:io';

/// 延迟优选历史记录（追加写入 latency_history.csv）。
class HistoryStore {
  static Future<String?> appendLatencySummary({
    required String outputFile,
    required int topnKept,
    required int tested,
    required int connected,
  }) async {
    final out = File(outputFile);
    final histDir = Directory('${out.parent.path}/history');
    await histDir.create(recursive: true);
    final histFile = File('${histDir.path}/latency_history.csv');
    final ts = DateTime.now().toString().substring(0, 19);
    final header = 'time,tested,connected,kept\n';
    final line = '$ts,$tested,$connected,$topnKept\n';
    try {
      if (!await histFile.exists()) {
        await histFile.writeAsString(header);
      }
      await histFile.writeAsString(line, mode: FileMode.append);
      return histFile.path;
    } on FileSystemException {
      return null;
    }
  }
}
