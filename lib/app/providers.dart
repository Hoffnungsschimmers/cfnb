import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/config/config_repository.dart';
import '../core/fetch/node_parser.dart';
import '../core/logging/app_logger.dart';
import 'dart:io';

/// 配置仓库（单例）。
final configRepositoryProvider = FutureProvider<ConfigRepository>((ref) async {
  return ConfigRepository.init();
});

/// 节点解析器（从 assets 加载国家码映射）。
final nodeParserProvider = FutureProvider<NodeParser>((ref) async {
  return NodeParser.fromAssets('assets/country_codes.json');
});

/// 全局日志器。
final loggerProvider = Provider<AppLogger>((ref) {
  final l = AppLogger();
  ref.onDispose(l.clear);
  return l;
});

/// 当前生效的配置（从仓库读取）。
final configProvider = FutureProvider<AppConfig>((ref) async {
  final repo = await ref.watch(configRepositoryProvider.future);
  final AppConfig c = repo.current;
  return c;
});

/// 应用私有目录（用于输出 ip.txt 等）。
final appDirProvider = FutureProvider<Directory>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return dir;
});
