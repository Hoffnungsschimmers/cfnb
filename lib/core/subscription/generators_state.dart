import 'package:shared_preferences/shared_preferences.dart';

/// 订阅器启用/禁用状态持久化（对应旧版 load/save_generators_state）。
///
/// 使用 shared_preferences 存储被禁用的订阅器名称集合。
class GeneratorsState {
  static const _kDisabled = 'sub_disabled_generators';

  final SharedPreferences _prefs;
  GeneratorsState(this._prefs);

  static Future<GeneratorsState> init() async {
    final prefs = await SharedPreferences.getInstance();
    return GeneratorsState(prefs);
  }

  Set<String> loadDisabled() {
    final list = _prefs.getStringList(_kDisabled) ?? [];
    return {...list};
  }

  Future<void> saveDisabled(Set<String> disabled) async {
    await _prefs.setStringList(_kDisabled, disabled.toList());
  }

  bool isDisabled(String name) => loadDisabled().contains(name);

  Future<void> setDisabled(String name, bool disabled) async {
    final set = loadDisabled();
    if (disabled) {
      set.add(name);
    } else {
      set.remove(name);
    }
    await saveDisabled(set);
  }
}
