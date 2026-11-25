import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ekranlar/ana_kabuk.dart';
import 'ekranlar/giris_ekrani.dart';
import 'ekranlar/muvekkil_portali_ekrani.dart';
import 'ekranlar/sunuculu_kabuk.dart';
import 'servisler/api_istemcisi.dart';
import 'servisler/kimlik_servisi.dart';
import 'servisler/sunucu_kimlik_servisi.dart';
import 'tema/tema.dart';

/// Derlemede `--dart-define=SUNUCU_ADRESI=https://api.ornek.com.tr/` verilirse uygulama gerçek sunucuya bağlanır;
/// verilmezse demo verisiyle bellekte çalışır.
const _sunucuAdresi = String.fromEnvironment('SUNUCU_ADRESI');

void main() {
  if (_sunucuAdresi.isEmpty) {
    runApp(PortalUygulamasi(kimlikServisi: BellekKimlikServisi()));
  } else {
    final api = ApiIstemcisi(Uri.parse(_sunucuAdresi));
    runApp(PortalUygulamasi(kimlikServisi: SunucuKimlikServisi(api), api: api));
  }
}

class PortalUygulamasi extends StatefulWidget {
  const PortalUygulamasi({super.key, required this.kimlikServisi, this.api});

  final KimlikServisi kimlikServisi;

  /// Sunucu bağlantısı (yoksa demo modu).
  final ApiIstemcisi? api;

  @override
  State<PortalUygulamasi> createState() => _PortalUygulamasiState();
}

class _PortalUygulamasiState extends State<PortalUygulamasi> {
  Oturum? _oturum;

  @override
  void initState() {
    super.initState();
    _oturum = widget.kimlikServisi.oturum;
  }

  Future<void> _cikisYap() async {
    await widget.kimlikServisi.cikisYap();
    if (mounted) setState(() => _oturum = null);
  }

  bool get _sunucuOturumu {
    final s = widget.kimlikServisi;
    return widget.api != null && s is SunucuKimlikServisi && s.sunucuOturumu;
  }

  @override
  Widget build(BuildContext context) {
    final oturum = _oturum;
    return MaterialApp(
      title: urunAdi,
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: acikTema(),
      themeMode: ThemeMode.light,
      home: oturum == null
          ? GirisEkrani(
              servis: widget.kimlikServisi,
              girisYapildi: (o) => setState(() => _oturum = o),
            )
          : oturum.muvekkilPortali
              ? MuvekkilPortaliEkrani(oturum: oturum, cikisYap: _cikisYap)
              : _sunucuOturumu
                  ? SunuculuKabuk(oturum: oturum, api: widget.api!, cikisYap: _cikisYap)
                  : AnaKabuk(oturum: oturum, cikisYap: _cikisYap),
    );
  }
}
