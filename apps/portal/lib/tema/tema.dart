import 'package:material_ui/material_ui.dart';

/// Ürün adı tek yerden değişir.
const String urunAdi = 'Hukuk ve Avukat Portalı';

/// Tasarım renkleri: lacivert yan menü, koyu yeşil vurgu, altın logo, krem zemin.
abstract final class Renkler {
  static const lacivert = Color(0xFF0F1E33);
  static const lacivertAcik = Color(0xFF1A2C47);
  static const yesil = Color(0xFF0E5A4E);
  static const yesilAcik = Color(0xFF147062);
  static const yesilZemin = Color(0xFFDDF1EC);
  static const altin = Color(0xFFC9A45C);
  static const krem = Color(0xFFF7F5F0);
  static const kenar = Color(0xFFE6E2D9);
  static const metin = Color(0xFF14213D);
  static const metinIkincil = Color(0xFF5B6475);

  static const kritik = Color(0xFFB42318);
  static const kritikZemin = Color(0xFFF8D9D6);
  static const uyari = Color(0xFFA15C07);
  static const uyariZemin = Color(0xFFFCEBCB);
  static const bilgi = Color(0xFF1F4E79);
  static const bilgiZemin = Color(0xFFE3ECF7);
  static const notr = Color(0xFF475467);
  static const notrZemin = Color(0xFFEDEFF2);
}

const _govde = 'Inter';
const _baslik = 'SourceSerif4';

ThemeData acikTema() {
  final renkler = ColorScheme.fromSeed(
    seedColor: Renkler.yesil,
    primary: Renkler.yesil,
    secondary: Renkler.altin,
    surface: Colors.white,
    error: Renkler.kritik,
  );
  final temel = ThemeData(useMaterial3: true, colorScheme: renkler, fontFamily: _govde);
  final yazi = temel.textTheme.apply(bodyColor: Renkler.metin, displayColor: Renkler.metin);

  return temel.copyWith(
    scaffoldBackgroundColor: Renkler.krem,
    textTheme: yazi.copyWith(
      displaySmall: yazi.displaySmall?.copyWith(fontFamily: _baslik, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: yazi.headlineLarge?.copyWith(fontFamily: _baslik, fontWeight: FontWeight.w700),
      headlineMedium: yazi.headlineMedium?.copyWith(fontFamily: _baslik, fontWeight: FontWeight.w700),
      headlineSmall: yazi.headlineSmall?.copyWith(fontFamily: _baslik, fontWeight: FontWeight.w700),
      titleLarge: yazi.titleLarge?.copyWith(fontFamily: _baslik, fontWeight: FontWeight.w700),
      titleMedium: yazi.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: yazi.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Renkler.metin,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: Renkler.kenar)),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Renkler.kenar),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Renkler.kenar, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Renkler.yesil,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: _govde, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Renkler.yesil,
        side: const BorderSide(color: Renkler.kenar),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Renkler.kenar)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Renkler.kenar)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Renkler.yesil, width: 1.5)),
    ),
    chipTheme: temel.chipTheme.copyWith(
      backgroundColor: Renkler.krem,
      side: const BorderSide(color: Renkler.kenar),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Renkler.yesil,
      unselectedLabelColor: Renkler.metinIkincil,
      indicatorColor: Renkler.yesil,
      dividerColor: Renkler.kenar,
      labelStyle: TextStyle(fontFamily: _govde, fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontFamily: _govde, fontWeight: FontWeight.w500, fontSize: 15),
    ),
  );
}
