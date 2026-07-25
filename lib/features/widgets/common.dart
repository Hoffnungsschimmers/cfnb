import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/motion.dart';
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
Widget pill(BuildContext context, String text, Color bg) {
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
              style: TextStyle(fontFamily: 'AppMono', fontSize: 12, color: t.text),
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
  StreamSubscription<String>? _logSub;
  StreamSubscription<void>? _clearSub;

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    _logSub = widget.logger.stream.listen((line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });
    });
    _clearSub = widget.logger.clearStream.listen((_) {
      _lines.clear();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _clearSub?.cancel();
    _sc.dispose();
    super.dispose();
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
              padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < _lines.length; i++) ...[
                      if (i > 0) const TextSpan(text: '\n'),
                      TextSpan(
                        text: _lines[i],
                        style: TextStyle(
                          fontFamily: 'AppMono',
                          fontSize: 12,
                          color: _lines[i].startsWith('[错误]') ? t.danger : t.logFg,
                          fontWeight: _lines[i].startsWith('[错误]') ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
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
        style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
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

// ═══════════════════════════════════════════════════════
// 增强组件：折叠分区 / 数字滚动 / Toast
// ═══════════════════════════════════════════════════════

/// 可折叠分区（带 chevron 旋转动效）。
class SectionCollapsible extends StatefulWidget {
  final String title;
  final IconData? icon;
  final bool initiallyExpanded;
  final Widget child;
  const SectionCollapsible({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.initiallyExpanded = true,
  });

  @override
  State<SectionCollapsible> createState() => _SectionCollapsibleState();
}

class _SectionCollapsibleState extends State<SectionCollapsible>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _chevronCtrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _chevronCtrl = AnimationController(
      vsync: this,
      duration: Motion.durFast,
      value: _expanded ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _chevronCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _chevronCtrl.forward();
      } else {
        _chevronCtrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radius,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: t.radius,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: AppTheme.edgeOrange),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textDim),
                    ),
                  ),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_chevronCtrl),
                    child: Icon(Icons.expand_more, color: t.textDim, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.durBase,
            curve: Motion.curveStandard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

/// 数字滚动文本：值变化时 tween 动画。
class CountUpText extends StatefulWidget {
  final num value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;
  final String? suffix;

  const CountUpText(
    this.value, {
    super.key,
    this.decimals = 0,
    this.style,
    this.duration = const Duration(milliseconds: 300),
    this.suffix,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> {
  double _prev = 0;

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _prev = old.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _prev, end: widget.value.toDouble()),
      duration: widget.duration,
      builder: (context, v, _) {
        final text = widget.decimals > 0
            ? v.toStringAsFixed(widget.decimals)
            : v.round().toString();
        return Text(
          widget.suffix != null ? '$text${widget.suffix}' : text,
          style: widget.style,
        );
      },
    );
  }
}

/// 带 count-up 的整数滑块。
Widget labeledSliderCountUp(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> onChanged, {
  String? suffix,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          CountUpText(
            value.round(),
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange),
            suffix: suffix,
          ),
        ],
      ),
      Slider(value: value, min: min, max: max, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 带 count-up 的浮点滑块。
Widget labeledDoubleSliderCountUp(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> onChanged, {
  String? suffix,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          CountUpText(
            value,
            decimals: 2,
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange),
            suffix: suffix,
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: min == max ? null : ((max - min) * 100).round().clamp(1, 1 << 30),
        activeColor: AppTheme.edgeOrange,
        onChanged: onChanged,
      ),
    ],
  );
}

/// 轻量应用内 Toast（OverlayEntry + AnimatedSwitcher）。
/// 使用：AppToast.show(context, '消息', success: true);
class AppToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    bool success = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    _current?.remove();
    _current = null;

    final t = AppThemeExt.of(context);
    final bg = success ? t.success : t.danger;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        bg: bg,
        icon: icon,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
        duration: duration,
      ),
    );
    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Color bg;
  final IconData icon;
  final VoidCallback onDismiss;
  final Duration duration;
  const _ToastWidget({
    required this.message,
    required this.bg,
    required this.icon,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> {
  bool _visible = false;
  Timer? _dismissTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    // 进场
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    // 自动消失
    _dismissTimer = Timer(widget.duration, () {
      if (!mounted) return;
      setState(() => _visible = false);
      _removeTimer = Timer(Motion.durBase, () {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: Motion.durBase,
        curve: Motion.curveStandard,
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : const Offset(0, 0.3),
          duration: Motion.durBase,
          curve: Motion.curveStandard,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.bg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: widget.bg.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
