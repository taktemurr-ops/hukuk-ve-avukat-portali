import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

/// Çıkar çatışması raporunu seviyeye göre renklendirerek gösterir.
class CikarRaporuGorunumu extends StatelessWidget {
  const CikarRaporuGorunumu({super.key, required this.rapor});

  final CikarCatismasiRaporu rapor;

  static String sifatAdi(TarafSifati s) => switch (s) {
        TarafSifati.muvekkil => 'müvekkil',
        TarafSifati.karsiTaraf => 'karşı taraf',
        TarafSifati.diger => 'diğer',
      };

  static String eslesmeAdi(EslesmeTuru t) => switch (t) {
        EslesmeTuru.kimlikNo => 'Kimlik no eşleşmesi',
        EslesmeTuru.tamIsim => 'Aynı isim',
        EslesmeTuru.benzerIsim => 'Benzer isim',
        EslesmeTuru.iliskiliKisi => 'İlişkili kişi',
      };

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    if (rapor.eslesmeler.isEmpty) {
      return Card(
        key: const Key('rapor-temiz'),
        child: ListTile(
          leading: Icon(Icons.verified_outlined, color: renkler.primary),
          title: const Text('Eşleşme bulunamadı'),
          subtitle: const Text('Kayıtlı taraflar ve ilişkili kişiler arasında çakışma yok.'),
        ),
      );
    }

    Color renk(RiskSeviyesi s) => switch (s) {
          RiskSeviyesi.catisma => renkler.error,
          RiskSeviyesi.dikkat => Colors.orange.shade800,
          RiskSeviyesi.bilgi => renkler.outline,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in rapor.eslesmeler)
          Card(
            child: ListTile(
              leading: Icon(
                e.seviye == RiskSeviyesi.bilgi ? Icons.info_outline : Icons.warning_amber_rounded,
                color: renk(e.seviye),
              ),
              title: Text('${e.seviye.ad}: ${e.aday.ad} → ${e.kisiAdi}'),
              subtitle: Text([
                '${eslesmeAdi(e.tur)}${e.tur == EslesmeTuru.benzerIsim ? ' (%${(e.benzerlik * 100).round()})' : ''}',
                if (e.iliski != null) 'ilişki: ${e.iliski!.name}',
                if (e.dosya != null)
                  '${e.dosya!.dosyaAdi} · ${sifatAdi(e.dosya!.sifat)}${e.dosya!.kapali ? ' · kapalı' : ''}',
                'yeni işte: ${sifatAdi(e.aday.sifat)}',
              ].join('\n')),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}
