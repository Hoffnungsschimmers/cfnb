import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// 配置持久化仓库。内存持有当前 [AppConfig]（单例语义）。
/// 启动时从 shared_preferences 读取；不存在则用默认值。旧键忽略，向后兼容。
class ConfigRepository {
  AppConfig _config;
  final SharedPreferences _prefs;

  ConfigRepository._(this._config, this._prefs);

  static Future<ConfigRepository> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kConfigJson);
    final Map<String, dynamic> data = jsonStr != null
        ? (jsonDecode(jsonStr) as Map<String, dynamic>)
        : <String, dynamic>{};
    var config = data.isNotEmpty ? AppConfig.fromJson(data) : const AppConfig();
    var dirty = false;

    // 迁移：旧配置若没有数据源，补入默认源。
    if (config.additionalSources.isEmpty) {
      config = config.copyWith(
        additionalSources: defaultAdditionalSources,
        subGenerators: defaultSubGenerators,
      );
      dirty = true;
    }

    // 迁移：旧默认国家 UN 视为未配置，改为空串（由节点名国家码决定）。
    if (config.subDefaultCountry.toUpperCase() == 'UN') {
      config = config.copyWith(subDefaultCountry: '');
      dirty = true;
    }

    // 迁移：带宽测速参数升级为更真实的默认值（仅当用户仍用旧默认值时生效）。
    if (config.subSpeedSizeMb == 1.0) {
      config = config.copyWith(subSpeedSizeMb: 10.0);
      dirty = true;
    }
    if (config.subSpeedTimeout == 15.0) {
      config = config.copyWith(subSpeedTimeout: 20.0);
      dirty = true;
    }
    if (config.subSpeedWorkers == 20) {
      config = config.copyWith(subSpeedWorkers: 10);
      dirty = true;
    }
    if (config.subLatencyTimeout == 2.0) {
      config = config.copyWith(subLatencyTimeout: 3.0);
      dirty = true;
    }
    if (config.subLatencyMaxMs == 0) {
      config = config.copyWith(subLatencyMaxMs: 200);
      dirty = true;
    }
    if (config.subSpeedLatencyLimit == 0) {
      config = config.copyWith(subSpeedLatencyLimit: 200);
      dirty = true;
    }

    // 质量最优前 50 名：对齐综合优选目标参数（强制，确保不论历史存值均生效）。
    if (config.subLatencyTopN != 50) {
      config = config.copyWith(subLatencyTopN: 50);
      dirty = true;
    }
    if (!config.subSpeedEnabled) {
      config = config.copyWith(subSpeedEnabled: true);
      dirty = true;
    }
    if (config.subBandwidthRefMbps != 30.0) {
      config = config.copyWith(subBandwidthRefMbps: 30.0);
      dirty = true;
    }
    if (config.subSpeedProbes != 3) {
      config = config.copyWith(subSpeedProbes: 3);
      dirty = true;
    }
    if ((config.subQualityLatencyWeight - 0.6).abs() > 1e-9) {
      config = config.copyWith(subQualityLatencyWeight: 0.6);
      dirty = true;
    }
    if (config.subLatencyProbes != 3) {
      config = config.copyWith(subLatencyProbes: 3);
      dirty = true;
    }

    if (dirty) {
      await prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
    }

    return ConfigRepository._(config, prefs);
  }

  static const _kConfigJson = 'app_config_json';

  AppConfig get current => _config;

  Future<void> save(AppConfig config) async {
    _config = config;
    await _prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
  }

  Future<void> update(AppConfig config) => save(config);

  List<String> validateCurrent() => _config.validate();
}
