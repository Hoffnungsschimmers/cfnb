import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/logging/app_logger.dart';

/// 卡片容器。
Widget card(BuildContext context, {required Widget child, EdgeInsets? padding}) {
  final t = AppThemeExt.of(context);
  return Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.radius,
      border: Border.all(color: t.border),
    ),
    child: child,
  );
}

/// 状态药丸。
Widget pill(BuildContext context, String text, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  const AppButton(this.label, {this.onPressed, this.primary = true, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: 18),
        if (icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

/// 区块标题。
Widget sectionTitle(BuildContext context, String text) {
  final t = AppThemeExt.of(context);
  return Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textDim),
  );
}

/// 单一强调色进度条。
Widget appProgress({double? value}) => LinearProgressIndicator(
      value: value,
      backgroundColor: Colors.orange.withValues(alpha: 0.15),
      color: AppTheme.edgeOrange,
      minHeight: 6,
      borderRadius: BorderRadius.circular(999),
    );

/// 日志视图：订阅 AppLogger 流，节流批量刷新，支持全选/复制。
/// 静态文本查看器：等宽字体整段可选中，支持「复制全部」。
class RawTextView extends StatelessWidget {
  final String text;
  final String? copyTooltip;
  final EdgeInsets padding;
  const RawTextView(this.text, {this.copyTooltip, this.padding = const EdgeInsets.all(0), super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Stack(
      children: [
        SelectionArea(
          child: SingleChildScrollView(
            padding: padding,
            child: SelectableText(
              text,
              style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: t.text),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: copyTooltip ?? '复制全部',
            color: t.textDim,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class LogView extends StatefulWidget {
  final AppLogger logger;
  final String? emptyHint;
  const LogView({required this.logger, this.emptyHint, super.key});
  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final List<String> _lines = [];
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    widget.logger.stream.listen((line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });
    });
    widget.logger.clearStream.listen((_) {
      _lines.clear();
      if (mounted) setState(() {});
    });
  }

  String get _all => _lines.join('\n');

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final child = _lines.isEmpty
        ? Container(
            alignment: Alignment.center,
            child: Text(widget.emptyHint ?? '暂无日志', style: TextStyle(color: t.textDim, fontSize: 12)),
          )
        : SelectionArea(
            child: SingleChildScrollView(
              controller: _sc,
              padding: const EdgeInsets.fromLTRB(8, 36, 8, 8),
              child: SelectableText(
                _all,
                style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: t.logFg),
              ),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        // 固定右上角操作按钮
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制全部',
                  color: t.textDim,
                  onPressed: _lines.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _all));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制全部日志'), duration: Duration(seconds: 1)),
                          );
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: '清空',
                  color: t.textDim,
                  onPressed: _lines.isEmpty
                      ? null
                      : () {
                          widget.logger.clear();
                        },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 统一输入框（带标签 + 等宽字体）。
Widget labeledTextField(
  BuildContext context,
  String label,
  TextEditingController ctl,
  ValueChanged<String> onChanged, {
  bool obscure = false,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
      const SizedBox(height: 4),
      TextField(
        controller: ctl,
        onChanged: onChanged,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
        decoration: inputDecorationFor(context),
      ),
    ],
  );
}

/// 统一开关行。
Widget labeledSwitch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
  final t = AppThemeExt.of(context);
  return Row(
    children: [
      Expanded(child: Text(label, style: TextStyle(color: t.text))),
      Switch(value: value, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 统一整数滑块（显示取整）。
Widget labeledSlider(BuildContext context, String label, double value, double min, double max,
    ValueChanged<double> onChanged) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          Text(value.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
        ],
      ),
      Slider(value: value, min: min, max: max, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 统一浮点滑块（显示 1 位小数 + divisions）。
Widget labeledDoubleSlider(BuildContext context, String label, double value, double min, double max,
    ValueChanged<double> onChanged) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          Text(value.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) * 10).round(),
        activeColor: AppTheme.edgeOrange,
        onChanged: onChanged,
      ),
    ],
  );
}

/// 统一输入框装饰。
InputDecoration inputDecorationFor(BuildContext context) {
  final t = AppThemeExt.of(context);
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.bg,
    border: OutlineInputBorder(borderRadius: t.radius, borderSide: BorderSide(color: t.border)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}
