import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

/// Önümüzdeki 30 günün duruşmaları ve süre son günleri, güne göre gruplu.
class TakvimEkrani extends StatelessWidget {
  const TakvimEkrani({super.key, required this.depo, required this.dosyaAc});

  final BellekVeriDeposu depo;
  final ValueChanged<String> dosyaAc;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final bugun = Tarih.from(DateTime.now());
        final bitis = bugun.gunEkle(30);
        final gunler = <Tarih, List<(String, String, RozetTuru, String)>>{};
        for (final d in depo.durusmalar) {
          final t = Tarih.from(d.baslangic);
          if (t.isBefore(bugun) || t.isAfter(bitis)) continue;
          gunler.putIfAbsent(t, () => []).add(
              ('${saat(d.baslangic)} ${d.tur}', '${depo.dosya(d.dosyaId)?.baslik ?? ''} · ${d.yer}', RozetTuru.devam, d.dosyaId));
        }
        for (final s in depo.sureler.where((s) => s.acik)) {
          if (s.sonGun.isBefore(bugun) || s.sonGun.isAfter(bitis)) continue;
          gunler.putIfAbsent(s.sonGun, () => []).add((
            'Son gün: ${s.sonuc.kural.ad}',
            '${depo.dosya(s.dosyaId)?.baslik ?? ''} · ${s.durum.ad}',
            s.durum == SureDurumu.teyitBekliyor ? RozetTuru.uyari : RozetTuru.kritik,
            s.dosyaId,
          ));
        }
        final sirali = gunler.keys.toList()..sort();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Takvim', style: Theme.of(context).textTheme.headlineMedium),
            const Text('Önümüzdeki 30 gün: duruşmalar ve süre son günleri'),
            const SizedBox(height: 16),
            if (sirali.isEmpty) const Text('Kayıt yok.'),
            for (final gun in sirali) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(uzunTarih(gun), style: const TextStyle(fontWeight: FontWeight.w700, color: Renkler.yesil)),
              ),
              for (final (baslik, alt, rozet, dosyaId) in gunler[gun]!)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(baslik),
                    subtitle: Text(alt),
                    trailing: DurumRozeti(rozet == RozetTuru.devam ? 'Duruşma' : 'Süre', rozet),
                    onTap: () => dosyaAc(dosyaId),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
