import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_repository.dart';
import '../core/fetch/node_parser.dart';
import '../core/logging/app_logger.dart';

/// 配置仓库（单例）。
final configRepositoryProvider = FutureProvider<ConfigRepository>((ref) async {
  return ConfigRepository.init();
});

/// 节点解析器（从 assets 加载国家码映射）。
final nodeParserProvider = FutureProvider<NodeParser>((ref) async {
  return NodeParser.fromAssets('assets/country_codes.json');
});

/// 订阅器独立日志器（与优选执行日志互相隔离）。
final subLoggerProvider = Provider<AppLogger>((ref) {
  final l = AppLogger();
  ref.onDispose(l.dispose);
  return l;
});

/// 当前生效的配置（从仓库读取）。
final configProvider = FutureProvider<AppConfig>((ref) async {
  final repo = await ref.watch(configRepositoryProvider.future);
  final AppConfig c = repo.current;
  return c;
});

/// 全局主题模式（配置页可切换并自动保存到 AppConfig.guiTheme）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
