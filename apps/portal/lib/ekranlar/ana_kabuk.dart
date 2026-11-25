import 'package:flutter/material.dart';

import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import 'cikar_catismasi_ekrani.dart';
import 'hesap_turleri_ekrani.dart';
import 'muvekkiller_ekrani.dart';
import 'sure_hesaplama_ekrani.dart';
import 'vekaletler_ekrani.dart';

class _Bolum {
  const _Bolum(this.baslik, this.ikon, this.seciliIkon);

  final String baslik;
  final IconData ikon;
  final IconData seciliIkon;
}

/// Uygulamanın ana iskeleti. Geniş ekranda yan menü, dar ekranda alt menü.
class AnaKabuk extends StatefulWidget {
  const AnaKabuk({super.key, required this.oturum, required this.cikisYap, this.depo});

  final Oturum oturum;
  final VoidCallback cikisYap;

  /// Verilmezse demo verisiyle bellek deposu oluşturulur.
  final BellekVeriDeposu? depo;

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> {
  int _secili = 0;
  late final BellekVeriDeposu _depo =
      widget.depo ?? BellekVeriDeposu.demo(kiraciId: widget.oturum.kiraciId, avukatId: widget.oturum.kullaniciId);

  static const _bolumler = [
    _Bolum('Süre hesapla', Icons.event_available_outlined, Icons.event_available),
    _Bolum('Müvekkiller', Icons.people_outline, Icons.people),
    _Bolum('Çıkar çatışması', Icons.gpp_maybe_outlined, Icons.gpp_maybe),
    _Bolum('Vekâletler', Icons.assignment_ind_outlined, Icons.assignment_ind),
    _Bolum('Hesap türleri', Icons.apartment_outlined, Icons.apartment),
  ];

  Widget _sayfa() => switch (_secili) {
        0 => const SureHesaplamaEkrani(),
        1 => MuvekkillerEkrani(depo: _depo),
        2 => CikarCatismasiEkrani(depo: _depo, oturum: widget.oturum),
        3 => VekaletlerEkrani(depo: _depo, oturum: widget.oturum),
        _ => const HesapTurleriEkrani(),
      };

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 840;
    final icerik = _sayfa();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.oturum.kurumAdi} · ${_bolumler[_secili].baslik}'),
        actions: [
          if (genis)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text(widget.oturum.adSoyad)),
            ),
          IconButton(
            key: const Key('cikis-yap'),
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: widget.cikisYap,
          ),
        ],
      ),
      body: genis
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _secili,
                  onDestinationSelected: (i) => setState(() => _secili = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final b in _bolumler)
                      NavigationRailDestination(
                        icon: Icon(b.ikon),
                        selectedIcon: Icon(b.seciliIkon),
                        label: Text(b.baslik),
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
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                for (final b in _bolumler)
                  NavigationDestination(icon: Icon(b.ikon), selectedIcon: Icon(b.seciliIkon), label: b.baslik),
              ],
            ),
    );
  }
}
