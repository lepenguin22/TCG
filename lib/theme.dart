import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0E1116);
  static const surface = Color(0xFF161B22);
  static const surfaceAlt = Color(0xFF1C232C);
  static const border = Color(0xFF252D38);
  static const text = Color(0xFFE9EEF5);
  static const textMuted = Color(0xFF9AA5B1);
  static const textFaint = Color(0xFF6B7683);
  static const danger = Color(0xFFF26D6D);
  static const warning = Color(0xFFF5C453);
  static const success = Color(0xFF5BD6A8);
  static const accent = Color(0xFFE4573D);
}

class Accent {
  const Accent(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;
}

const accents = <Accent>[
  Accent('ember', 'Ember', Color(0xFFE4573D)),
  Accent('violet', 'Violet', Color(0xFF8C6BD1)),
  Accent('azure', 'Azure', Color(0xFF4FB3E8)),
  Accent('gold', 'Gold', Color(0xFFF0C24B)),
  Accent('jade', 'Jade', Color(0xFF4FC08D)),
  Accent('rose', 'Rose', Color(0xFFEE85B5)),
];

Color accentColor(String key) {
  for (final accent in accents) {
    if (accent.key == key) return accent.color;
  }
  return accents.first.color;
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.danger,
      onPrimary: AppColors.bg,
      onSurface: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(color: AppColors.surface),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      hintStyle: const TextStyle(color: AppColors.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.bg,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}
