import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFFFF3B5C);
  static const Color primaryDark = Color(0xFFE11D48);
  static const Color secondary = Color(0xFF22D3EE);
  static const Color accent = Color(0xFFFBBF24);

  // Dark palette
  static const Color dBackground = Color(0xFF0A0A0B);
  static const Color dSurface = Color(0xFF141416);
  static const Color dSurfaceLight = Color(0xFF1E1E22);
  static const Color dSurfaceVariant = Color(0xFF2A2A30);
  static const Color dBorder = Color(0xFF2E2E36);
  static const Color dTextPrimary = Color(0xFFF5F5F7);
  static const Color dTextSecondary = Color(0xFFA1A1AA);
  static const Color dTextMuted = Color(0xFF71717A);

  // Light palette
  static const Color lBackground = Color(0xFFF4F4F6);
  static const Color lSurface = Color(0xFFFFFFFF);
  static const Color lSurfaceLight = Color(0xFFEEEEF2);
  static const Color lSurfaceVariant = Color(0xFFE4E4EA);
  static const Color lBorder = Color(0xFFD4D4DC);
  static const Color lTextPrimary = Color(0xFF111118);
  static const Color lTextSecondary = Color(0xFF5C5C66);
  static const Color lTextMuted = Color(0xFF8B8B96);

  // Legacy aliases (dark defaults) — prefer ThemeColors.of(context)
  static const Color background = dBackground;
  static const Color surface = dSurface;
  static const Color surfaceLight = dSurfaceLight;
  static const Color surfaceVariant = dSurfaceVariant;
  static const Color border = dBorder;
  static const Color textPrimary = dTextPrimary;
  static const Color textSecondary = dTextSecondary;
  static const Color textMuted = dTextMuted;

  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color sbSponsor = Color(0xFF00D400);
  static const Color sbSelfpromo = Color(0xFFFFE600);
  static const Color sbInteraction = Color(0xFFCC00FF);
  static const Color sbIntro = Color(0xFF00FFFF);
  static const Color sbOutro = Color(0xFF0202ED);
  static const Color sbFiller = Color(0xFF7300FF);

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        background: dBackground,
        surface: dSurface,
        surfaceLight: dSurfaceLight,
        surfaceVariant: dSurfaceVariant,
        border: dBorder,
        textPrimary: dTextPrimary,
        textSecondary: dTextSecondary,
        textMuted: dTextMuted,
      );

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        background: lBackground,
        surface: lSurface,
        surfaceLight: lSurfaceLight,
        surfaceVariant: lSurfaceVariant,
        border: lBorder,
        textPrimary: lTextPrimary,
        textSecondary: lTextSecondary,
        textMuted: lTextMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceLight,
    required Color surfaceVariant,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.black,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceVariant,
        outline: border,
      ),
      extensions: [
        VibeColors(
          background: background,
          surface: surface,
          surfaceLight: surfaceLight,
          surfaceVariant: surfaceVariant,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textMuted: textMuted,
        ),
      ],
    );

    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: surface,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: surface,
              ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: primary,
        disabledColor: surfaceLight,
        labelStyle: TextStyle(color: textPrimary, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        hintStyle: TextStyle(color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surfaceVariant : const Color(0xFF2A2A30),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: textSecondary, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : surfaceVariant),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      iconTheme: IconThemeData(color: textPrimary),
    );
  }

  static void applySystemUi(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? dSurface : lSurface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }
}

@immutable
class VibeColors extends ThemeExtension<VibeColors> {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceVariant;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const VibeColors({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceVariant,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  static VibeColors of(BuildContext context) {
    return Theme.of(context).extension<VibeColors>() ??
        const VibeColors(
          background: AppTheme.dBackground,
          surface: AppTheme.dSurface,
          surfaceLight: AppTheme.dSurfaceLight,
          surfaceVariant: AppTheme.dSurfaceVariant,
          border: AppTheme.dBorder,
          textPrimary: AppTheme.dTextPrimary,
          textSecondary: AppTheme.dTextSecondary,
          textMuted: AppTheme.dTextMuted,
        );
  }

  @override
  VibeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? surfaceVariant,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return VibeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  VibeColors lerp(ThemeExtension<VibeColors>? other, double t) {
    if (other is! VibeColors) return this;
    return VibeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}
