import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF030712); // Deep Stage Black
  static const Color card = Color(0xFF0F172A);       // Slate 900
  static const Color cardBorder = Color(0xFF1E293B); // Slate 800
  static const Color primary = Color(0xFF38BDF8);    // Sky 400 (Destaque)
  static const Color amberCue = Color(0xFFFBBF24);   // Âmbar para Click / Guia
  static const Color emeraldSafe = Color(0xFF34D399);// Verde para Split Ativo / Offline
  static const Color emeraldPlay = Color(0xFF10B981);// Verde para Play / Cifras salvas
  static const Color roseMute = Color(0xFFF43F5E);   // Vermelho para Mute

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    cardColor: card,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: amberCue,
      surface: card,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: Color(0xFF334155),
      thumbColor: primary,
      trackHeight: 4.0,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7.0),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14.0),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: card,
      elevation: 0,
      centerTitle: false,
    ),
  );
}
