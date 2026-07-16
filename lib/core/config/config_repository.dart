import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// 配置持久化仓库。
///
/// - 内存中持有当前 [AppConfig]（单例语义）。
/// - 启动时尝试从应用私有目录的 config.json 读取；不存在则使用默认值。
/// - 保存时写回 shared_preferences（轻量字段）与应用目录 config.json（完整）。
class ConfigRepository {
  AppConfig _config;
  final SharedPreferences _prefs;

  ConfigRepository._(this._config, this._prefs);

  static Future<ConfigRepository> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kConfigJson);
    final config = jsonStr != null
        ? AppConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>)
        : const AppConfig();
    return ConfigRepository._(config, prefs);
  }

  static const _kConfigJson = 'app_config_json';

  AppConfig get current => _config;

  /// 用一份完整配置替换并持久化。
  Future<void> save(AppConfig config) async {
    _config = config;
    await _prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
  }

  /// 局部更新（传入修改后的一份配置）。
  Future<void> update(AppConfig config) => save(config);

  List<String> validateCurrent() => _config.validate();
}
