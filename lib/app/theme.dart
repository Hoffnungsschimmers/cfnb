import 'package:flutter/material.dart';

/// 设计语言：Edge Telemetry
/// 单一强调色 = Cloudflare 橙 (#ff7a1a)，其余皆为中性灰阶，杜绝"背景与字体同色"。
class AppTheme {
  static const edgeOrange = Color(0xFFFF7A1A);
  static const edgeOrangeDark = Color(0xFFE0640A);

  static const _lightBg = Color(0xFFFBFAF8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHover = Color(0xFFF3F1EC);
  static const _lightText = Color(0xFF1C1917);
  static const _lightTextDim = Color(0xFF78716C);
  static const _lightBorder = Color(0xFFE7E3DC);
  static const _lightLogBg = Color(0xFFFCFBF9);
  static const _lightLogFg = Color(0xFF1C1917);

  static const _darkBg = Color(0xFF0C0A09);
  static const _darkSurface = Color(0xFF171412);
  static const _darkSurfaceHover = Color(0xFF221D19);
  static const _darkText = Color(0xFFF5F0EA);
  static const _darkTextDim = Color(0xFF9A9189);
  static const _darkBorder = Color(0xFF2A241E);
  static const _darkLogBg = Color(0xFF0C0A09);
  static const _darkLogFg = Color(0xFFCBD5E1);

  static ThemeData light() => _build(
        bg: _lightBg,
        surface: _lightSurface,
        surfaceHover: _lightSurfaceHover,
        text: _lightText,
        textDim: _lightTextDim,
        border: _lightBorder,
        logBg: _lightLogBg,
        logFg: _lightLogFg,
        brightness: Brightness.light,
      );

  static ThemeData dark() => _build(
        bg: _darkBg,
        surface: _darkSurface,
        surfaceHover: _darkSurfaceHover,
        text: _darkText,
        textDim: _darkTextDim,
        border: _darkBorder,
        logBg: _darkLogBg,
        logFg: _darkLogFg,
        brightness: Brightness.dark,
      );

  static ThemeData _build({
    required Color bg,
    required Color surface,
    required Color surfaceHover,
    required Color text,
    required Color textDim,
    required Color border,
    required Color logBg,
    required Color logFg,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: edgeOrange,
      brightness: brightness,
      surface: surface,
      primary: edgeOrange,
      onPrimary: Colors.white,
      onSurface: text,
    ).copyWith(
      surface: surface,
      onSurface: text,
    );

    final radius = BorderRadius.circular(10);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'MicrosoftYaHei',
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: edgeOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textDim),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: edgeOrange,
      ),
      extensions: [
        AppThemeExt(
          bg: bg,
          surface: surface,
          surfaceHover: surfaceHover,
          text: text,
          textDim: textDim,
          border: border,
          logBg: logBg,
          logFg: logFg,
          radius: radius,
        ),
      ],
    );
  }
}

/// 主题语义色扩展，供自定义组件直接取色（对应旧版 C 字典）。
class AppThemeExt extends ThemeExtension<AppThemeExt> {
  final Color bg;
  final Color surface;
  final Color surfaceHover;
  final Color text;
  final Color textDim;
  final Color border;
  final Color logBg;
  final Color logFg;
  final BorderRadius radius;

  const AppThemeExt({
    required this.bg,
    required this.surface,
    required this.surfaceHover,
    required this.text,
    required this.textDim,
    required this.border,
    required this.logBg,
    required this.logFg,
    required this.radius,
  });

  static AppThemeExt of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExt>()!;

  @override
  AppThemeExt copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHover,
    Color? text,
    Color? textDim,
    Color? border,
    Color? logBg,
    Color? logFg,
    BorderRadius? radius,
  }) =>
      AppThemeExt(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHover: surfaceHover ?? this.surfaceHover,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        border: border ?? this.border,
        logBg: logBg ?? this.logBg,
        logFg: logFg ?? this.logFg,
        radius: radius ?? this.radius,
      );

  @override
  AppThemeExt lerp(ThemeExtension<AppThemeExt>? other, double t) {
    if (other is! AppThemeExt) return this;
    return this;
  }
}
