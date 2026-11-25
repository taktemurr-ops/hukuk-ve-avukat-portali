import 'package:flutter/material.dart';

import 'hesap_turleri_ekrani.dart';
import 'sure_hesaplama_ekrani.dart';

/// Uygulamanın ana iskeleti. Geniş ekranda yan menü, dar ekranda alt menü.
class AnaKabuk extends StatefulWidget {
  const AnaKabuk({super.key});

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> {
  int _secili = 0;

  static const _sayfalar = <Widget>[
    SureHesaplamaEkrani(),
    HesapTurleriEkrani(),
  ];

  static const _basliklar = ['Süre hesapla', 'Hesap türleri'];

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 840;

    final icerik = _sayfalar[_secili];

    return Scaffold(
      appBar: AppBar(
        title: Text('Hukuk ve Avukat Portalı · ${_basliklar[_secili]}'),
      ),
      body: genis
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _secili,
                  onDestinationSelected: (i) => setState(() => _secili = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.event_available_outlined),
                      selectedIcon: Icon(Icons.event_available),
                      label: Text('Süre hesapla'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.apartment_outlined),
                      selectedIcon: Icon(Icons.apartment),
                      label: Text('Hesap türleri'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: icerik),
              ],
            )
          : icerik,
      bottomNavigationBar: genis
          ? null
          : NavigationBar(
              selectedIndex: _secili,
              onDestinationSelected: (i) => setState(() => _secili = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.event_available_outlined),
                  label: 'Süre hesapla',
                ),
                NavigationDestination(
                  icon: Icon(Icons.apartment_outlined),
                  label: 'Hesap türleri',
                ),
              ],
            ),
    );
  }
}
