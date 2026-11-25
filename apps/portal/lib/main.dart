import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ekranlar/ana_kabuk.dart';
import 'ekranlar/giris_ekrani.dart';
import 'servisler/kimlik_servisi.dart';
import 'tema/tema.dart';

void main() {
  runApp(PortalUygulamasi(kimlikServisi: BellekKimlikServisi()));
}

class PortalUygulamasi extends StatefulWidget {
  const PortalUygulamasi({super.key, required this.kimlikServisi});

  final KimlikServisi kimlikServisi;

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
          : AnaKabuk(oturum: oturum, cikisYap: _cikisYap),
    );
  }
}
