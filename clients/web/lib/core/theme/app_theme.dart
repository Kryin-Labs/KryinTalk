/// ConnectHub — Material 3 Theme System (Exact Port of SaaSSchool Light Cream & Claymorphism Engine).
///
/// Matches F:\NARCOSTUFF-LAPTOP\Apps\SaaSSchool\src\index.css:
/// - Background: #FAF9F6 (Cream Light)
/// - Foreground: #1C1917 (Dark Charcoal)
/// - Primary: #0F766E (Teal-700)
/// - Muted: #78716C (Muted Gray)
/// - Light Emerald Fill: #F0FDF9
/// - Lime Highlight: #B8F28B / #EDFCE2
/// - Clay Shadow: 20px 20px 40px #E6E4E0, -20px -20px 40px #FFFFFF
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── SaaSSchool Light Claymorphism Color Tokens ──
  static const creamBackground = Color(0xFFFAF9F6);
  static const charcoalForeground = Color(0xFF1C1917);
  static const primaryTeal = Color(0xFF0F766E);
  static const mutedText = Color(0xFF78716C);
  static const emeraldLight = Color(0xFFF0FDF9);
  static const emeraldBorder = Color(0xFFCCFBF1);
  static const limeHighlight = Color(0xFFB8F28B);
  static const limeLight = Color(0xFFEDFCE2);
  static const clayShadowDark = Color(0xFFE6E4E0);
  static const clayShadowLight = Colors.white;

  // ── Light Theme (Primary SaaSSchool Engine) ──
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryTeal,
      primary: primaryTeal,
      secondary: const Color(0xFF2C5F53),
      tertiary: const Color(0xFF5EEAD4),
      brightness: Brightness.light,
      surface: creamBackground,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: creamBackground,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: charcoalForeground,
        displayColor: charcoalForeground,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: creamBackground,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: charcoalForeground),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: charcoalForeground,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: const BorderSide(color: Color(0x80FFFFFF), width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: creamBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryTeal, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: charcoalForeground,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE6E4E0),
        thickness: 1,
      ),
    );
  }

  static ThemeData get dark {
    const background = Color(0xFF111318);
    const surface = Color(0xFF191C23);
    const border = Color(0xFF2B303B);
    const text = Color(0xFFF3F4F6);
    const muted = Color(0xFF9CA3AF);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DD4BF),
      primary: const Color(0xFF2DD4BF),
      secondary: const Color(0xFF5EEAD4),
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      textTheme:
          GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme)
              .apply(
        bodyColor: text,
        displayColor: text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        iconTheme: const IconThemeData(color: text),
        titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 18, fontWeight: FontWeight.w700, color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF20242D),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2DD4BF), width: 1.5)),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: surface),
      dialogTheme: DialogThemeData(
          backgroundColor: surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
    );
  }
}
