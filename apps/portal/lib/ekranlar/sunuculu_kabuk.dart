import 'package:flutter/material.dart';

import '../servisler/api_istemcisi.dart';
import '../servisler/kimlik_servisi.dart';
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
  late Future<void> _yukleme = _senkron.yenile();

  @override
  void dispose() {
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
                    onPressed: () => setState(() => _yukleme = _senkron.yenile()),
                    child: const Text('Tekrar dene'),
                  ),
                  OutlinedButton(onPressed: widget.cikisYap, child: const Text('Çıkış')),
                ]),
              ]),
            ),
          );
        }
        return AnaKabuk(oturum: widget.oturum, cikisYap: widget.cikisYap, depo: _depo);
      },
    );
  }
}
