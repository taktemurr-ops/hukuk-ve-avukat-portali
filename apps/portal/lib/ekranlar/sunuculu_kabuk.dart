import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/api_istemcisi.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/kurumsal_depo.dart';
import '../servisler/kurumsal_senkronu.dart';
import '../servisler/sunucu_senkronu.dart';
import '../servisler/veri_deposu.dart';
import 'ana_kabuk.dart';

/// Sunucu oturumunda: boş bir yerel önbellek oluşturur, sunucudan yükler ve ana kabuğu açar.
class SunuculuKabuk extends StatefulWidget {
  const SunuculuKabuk({super.key, required this.oturum, required this.api, required this.cikisYap});

  final Oturum oturum;
  final ApiIstemcisi api;
  final VoidCallback cikisYap;

  @override
  State<SunuculuKabuk> createState() => _SunuculuKabukState();
}

class _SunuculuKabukState extends State<SunuculuKabuk> {
  late final BellekVeriDeposu _depo = BellekVeriDeposu(widget.oturum.kiraciId);
  late final SunucuSenkronu _senkron = SunucuSenkronu(widget.api, _depo);

  /// Kurumsal hesapta sözleşme, talep ve grup şirketleri de sunucudan gelir (demo verisi kullanılmaz).
  late final KurumsalDepo? _kurumsal = widget.oturum.hesapTuru == HesapTuru.kurumsal
      ? KurumsalDepo(depo: _depo, kullaniciId: widget.oturum.kullaniciId)
      : null;
  late final KurumsalSenkronu? _kurumsalSenkron = _kurumsal == null ? null : KurumsalSenkronu(widget.api, _kurumsal!);
  late Future<void> _yukleme = _yukle();

  Future<void> _yukle() async {
    await _senkron.yenile();
    await _kurumsalSenkron?.yenile();
  }

  @override
  void dispose() {
    _kurumsal?.dispose();
    _depo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _yukleme,
      builder: (context, durum) {
        if (durum.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (durum.hasError) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Veriler yüklenemedi: ${durum.error}'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  FilledButton(
                    key: const Key('sunucu-tekrar'),
                    onPressed: () => setState(() => _yukleme = _yukle()),
                    child: const Text('Tekrar dene'),
                  ),
                  OutlinedButton(onPressed: widget.cikisYap, child: const Text('Çıkış')),
                ]),
              ]),
            ),
          );
        }
        return AnaKabuk(oturum: widget.oturum, cikisYap: widget.cikisYap, depo: _depo, kurumsal: _kurumsal);
      },
    );
  }
}
