import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/sunucu_senkronu.dart';
import '../tema/tema.dart';

/// Sunucu bağlıyken abonelik: durum, fiyatlar (sunucuda hesaplanır), ödeme ve ödeme geçmişi.
/// Kart bilgisi uygulamada istenmez; ödeme kuruluşunun sayfası tarayıcıda açılır.
class SunucuAbonelikEkrani extends StatefulWidget {
  const SunucuAbonelikEkrani({super.key, required this.uzak, this.sayfaAc});

  final UzakIslemler uzak;

  /// Testlerde tarayıcı yerine kullanılır.
  final Future<bool> Function(Uri adres)? sayfaAc;

  @override
  State<SunucuAbonelikEkrani> createState() => _SunucuAbonelikEkraniState();
}

class _SunucuAbonelikEkraniState extends State<SunucuAbonelikEkrani> {
  late Future<Map<String, dynamic>> _bilgi = widget.uzak.abonelik();
  OdemeDonemi _donem = OdemeDonemi.aylik;
  bool _bekliyor = false;

  void _yenile() => setState(() => _bilgi = widget.uzak.abonelik());

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _ode(int? koltuk) async {
    setState(() => _bekliyor = true);
    try {
      final adres = await widget.uzak.odemeBaslat(_donem, koltuk: koltuk);
      final ac = widget.sayfaAc ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
      final acildi = await ac(adres);
      if (!mounted) return;
      _mesaj(acildi
          ? 'Ödeme sayfası açıldı. Ödeme tamamlanınca bu ekranı yenileyin.'
          : 'Ödeme sayfası açılamadı: $adres');
    } on Exception catch (e) {
      if (mounted) _mesaj('$e');
    } finally {
      if (mounted) setState(() => _bekliyor = false);
    }
  }

  static String _tl(Object? kurus) => Para.kurus(kurus as int? ?? 0).bicimli;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonelik ve ödeme'),
        actions: [IconButton(key: const Key('abonelik-yenile'), tooltip: 'Yenile', onPressed: _yenile, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _bilgi,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return Center(child: Text('Abonelik bilgisi alınamadı: ${s.error}'));
          final b = s.data!;
          final fiyatlar = (b['fiyatlar'] as List? ?? const []).cast<Map<String, dynamic>>();
          final secili = fiyatlar.where((f) => f['donem'] == _donem.name).firstOrNull;
          final odemeler = (b['odemeler'] as List? ?? const []).cast<Map<String, dynamic>>();
          final yazilabilir = b['yazilabilir'] == true;
          final teklif = (b['paket'] as Map?)?['fiyatTuru'] == 'teklif';
          return ListView(padding: const EdgeInsets.all(24), children: [
            Panel(
              baslik: 'Durum',
              sag: DurumRozeti('${b['etkinDurumAdi']}', yazilabilir ? RozetTuru.onay : RozetTuru.kritik),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dönem: ${uzunTarih(Tarih.parse(b['donemBasi'] as String))} – ${uzunTarih(Tarih.parse(b['donemSonu'] as String))}'
                    '${b['donemSonundaIptal'] == true ? ' (dönem sonunda iptal edilecek)' : ''}',
                    key: const Key('sunucu-abonelik-donem')),
                Text('Kullanılan koltuk: ${b['kullanilanKoltuk']} · ücretli: ${b['ucretliKoltuk']}'),
                if (!yazilabilir) ...[
                  const SizedBox(height: 8),
                  const Text('Hesabınız salt okunur. Verileriniz korunuyor; ödeme yapınca kaldığınız yerden devam edersiniz.',
                      style: TextStyle(color: Renkler.kritik)),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            if (teklif)
              const Panel(
                baslik: 'Kurumsal sözleşme',
                child: Text('Kurumsal paket teklif usulüdür; faturalar sözleşme dönemine göre kesilir.'),
              )
            else
              Panel(
                baslik: 'Ödeme',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SegmentedButton<OdemeDonemi>(
                    key: const Key('sunucu-odeme-donemi'),
                    segments: const [
                      ButtonSegment(value: OdemeDonemi.aylik, label: Text('Aylık')),
                      ButtonSegment(value: OdemeDonemi.yillik, label: Text('Yıllık (2 ay hediye)')),
                    ],
                    selected: {_donem},
                    onSelectionChanged: (x) => setState(() => _donem = x.first),
                  ),
                  const SizedBox(height: 12),
                  if (secili != null) ...[
                    Text('Tutar: ${_tl(secili['matrahKurus'])} + KDV ${_tl(secili['kdvKurus'])} = '
                        '${_tl(secili['toplamKurus'])}', key: const Key('sunucu-odeme-tutar')),
                    if ((secili['koltuk'] as int? ?? 1) > 1) Text('${secili['koltuk']} ücretli kullanıcı için'),
                  ],
                  const SizedBox(height: 12),
                  if (b['odemeAltyapisi'] != true)
                    const Text('Online ödeme henüz açılmadı; ödeme için bizimle iletişime geçin.')
                  else
                    FilledButton.icon(
                      key: const Key('sunucu-odeme-yap'),
                      onPressed: _bekliyor || secili == null ? null : () => _ode(secili['koltuk'] as int?),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Güvenli ödeme sayfasına git'),
                    ),
                  const SizedBox(height: 8),
                  Text('Kart bilgileriniz ödeme kuruluşunun sayfasında girilir; uygulamamızda saklanmaz.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('sunucu-abonelik-iptal'),
                    onPressed: () async {
                      final iptal = b['donemSonundaIptal'] != true;
                      try {
                        await widget.uzak.abonelikIptal(iptal);
                        _yenile();
                      } on Exception catch (e) {
                        if (mounted) _mesaj('$e');
                      }
                    },
                    child: Text(b['donemSonundaIptal'] == true ? 'İptal isteğini geri al' : 'Dönem sonunda iptal et'),
                  ),
                ]),
              ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Ödeme geçmişi',
              child: odemeler.isEmpty
                  ? const Text('Kayıt yok.')
                  : Column(children: [
                      for (final o in odemeler)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${tarihSaat(DateTime.parse(o['zaman'] as String).toLocal())} · ${_tl(o['toplamKurus'])}'),
                          subtitle: Text('${o['donem'] == 'yillik' ? 'Yıllık' : 'Aylık'} · ${o['koltuk']} koltuk'
                              '${o['hata'] == null ? '' : ' · ${o['hata']}'}'),
                          trailing: DurumRozeti(
                            switch (o['durum']) { 'basarili' => 'Ödendi', 'basarisiz' => 'Başarısız', _ => 'Bekliyor' },
                            switch (o['durum']) { 'basarili' => RozetTuru.onay, 'basarisiz' => RozetTuru.kritik, _ => RozetTuru.uyari },
                          ),
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}
