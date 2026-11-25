import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';

Aktor oturumAktoru(Oturum o) => Aktor(kullaniciId: o.kullaniciId, kiraciId: o.kiraciId, roller: o.roller);

/// Kullanıcının görebildiği dosyalar (tek kapı yetki denetçisiyle süzülür).
class DosyalarEkrani extends StatelessWidget {
  const DosyalarEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final bugun = Tarih.from(DateTime.now());
        final dosyalar = depo.gorunurDosyalar(oturumAktoru(oturum));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${dosyalar.length} dosya', style: Theme.of(context).textTheme.labelMedium),
            for (final d in dosyalar)
              Card(
                child: ListTile(
                  key: Key('dosya-${d.id}'),
                  leading: Icon(d.gizli ? Icons.lock_outline : Icons.folder_outlined),
                  title: Text('${d.icNo} · ${d.baslik}'),
                  subtitle: Text(_altBilgi(d, bugun)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => DosyaDetayEkrani(depo: depo, oturum: oturum, dosyaId: d.id)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _altBilgi(Dosya d, Tarih bugun) {
    final acikSureler = depo.dosyaSureleri(d.id).where((s) => s.acik).toList();
    return [
      d.tur.ad,
      d.asama.ad,
      if (d.mahkeme != null) d.mahkeme!,
      if (d.esasNo != null) d.esasNo!,
      'sorumlu: ${depo.kullaniciAdi(d.sorumlu)}',
      if (acikSureler.isNotEmpty) 'en yakın süre: ${kalanMetni(acikSureler.first.kalanGun(bugun))}',
    ].join(' · ');
  }
}

class DosyaDetayEkrani extends StatelessWidget {
  const DosyaDetayEkrani({super.key, required this.depo, required this.oturum, required this.dosyaId});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final String dosyaId;

  Future<String?> _kanitIste(BuildContext context, String baslik) async {
    final c = TextEditingController();
    final sonuc = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(baslik),
        content: TextField(
          key: const Key('kanit-alani'),
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'İşlem no, makbuz no veya belge adı'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            key: const Key('kanit-onayla'),
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    c.dispose();
    return sonuc;
  }

  void _mesaj(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final d = depo.dosya(dosyaId)!;
        final bugun = Tarih.from(DateTime.now());
        final metin = Theme.of(context).textTheme;
        final sureler = depo.dosyaSureleri(d.id);
        final gorevler = depo.dosyaGorevleri(d.id);
        final tebligatlar = depo.dosyaTebligatlari(d.id);
        return Scaffold(
          appBar: AppBar(title: Text('${d.icNo} · ${d.baslik}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(d.tur.ad)),
                  Chip(label: Text(d.asama.ad)),
                  if (d.gizli) const Chip(avatar: Icon(Icons.lock_outline, size: 16), label: Text('Gizli')),
                  if (d.mahkeme != null) Chip(label: Text(d.mahkeme!)),
                  if (d.esasNo != null) Chip(label: Text(d.esasNo!)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Asıl sorumlu: ${depo.kullaniciAdi(d.sorumlu)} · '
                'Yedek: ${d.yedekSorumlu == null ? 'atanmamış' : depo.kullaniciAdi(d.yedekSorumlu!)}',
              ),
              const Divider(height: 32),
              Text('Süreler', style: metin.titleMedium),
              if (sureler.isEmpty) const ListTile(title: Text('Kayıtlı süre yok.')),
              for (final s in sureler)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.aciklama, style: metin.titleSmall),
                        Text(
                          'Son gün ${s.sonGun.turkceBicim} ${s.sonGun.gunAdi} (${kalanMetni(s.kalanGun(bugun))}) · '
                          '${s.durum.ad}${s.teyitEden != null ? ' · teyit: ${depo.kullaniciAdi(s.teyitEden!)}' : ''}'
                          '${s.tamamlanmaKaniti != null ? ' · kanıt: ${s.tamamlanmaKaniti}' : ''}',
                        ),
                        Text('Dayanak: ${s.sonuc.kural.dayanak} · hesaplayan: ${depo.kullaniciAdi(s.olusturan)}',
                            style: metin.bodySmall),
                        if (s.oncekiHesaplar.isNotEmpty)
                          Text('${s.oncekiHesaplar.length} önceki hesap saklanıyor', style: metin.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (s.durum == SureDurumu.teyitBekliyor)
                              FilledButton.tonal(
                                key: Key('teyit-${s.id}'),
                                onPressed: () {
                                  try {
                                    depo.sureGuncelle(s.teyitEt(kullanici: oturum.kullaniciId, tarih: bugun));
                                    _mesaj(context, 'Süre teyit edildi.');
                                  } on StateError catch (e) {
                                    _mesaj(context, e.message);
                                  }
                                },
                                child: const Text('Hesabı teyit et'),
                              ),
                            if (s.durum == SureDurumu.teyitli)
                              FilledButton.tonal(
                                key: Key('tamamla-${s.id}'),
                                onPressed: () async {
                                  final kanit = await _kanitIste(context, 'Süreyi tamamla');
                                  if (kanit == null || !context.mounted) return;
                                  try {
                                    depo.sureGuncelle(s.tamamla(kanit: kanit));
                                    _mesaj(context, 'Süre tamamlandı.');
                                  } on ArgumentError catch (e) {
                                    _mesaj(context, '${e.message}');
                                  }
                                },
                                child: const Text('İşlem yapıldı'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 32),
              Text('Görevler', style: metin.titleMedium),
              if (gorevler.isEmpty) const ListTile(title: Text('Görev yok.')),
              for (final g in gorevler)
                CheckboxListTile(
                  key: Key('gorev-${g.id}'),
                  value: g.durum == GorevDurumu.tamamlandi,
                  onChanged: g.durum != GorevDurumu.acik
                      ? null
                      : (_) async {
                          final kanitGerekir = g.kanitGerekir || g.kaynakSureId != null;
                          String? kanit;
                          if (kanitGerekir) {
                            kanit = await _kanitIste(context, 'Görevi kapat');
                            if (kanit == null || !context.mounted) return;
                          }
                          try {
                            depo.gorevGuncelle(g.kapat(kanit: kanit));
                          } on ArgumentError catch (e) {
                            if (context.mounted) _mesaj(context, '${e.message}');
                          }
                        },
                  title: Text(g.baslik),
                  subtitle: Text(
                    '${depo.kullaniciAdi(g.atanan)}'
                    '${g.sonTarih != null ? ' · ${g.sonTarih!.turkceBicim}' : ''}'
                    '${g.gecikti(bugun) ? ' · gecikti' : ''}'
                    '${g.kapanisKaniti != null ? ' · kanıt: ${g.kapanisKaniti}' : ''}',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const Divider(height: 32),
              Text('Tebligatlar', style: metin.titleMedium),
              if (tebligatlar.isEmpty) const ListTile(title: Text('Tebligat yok.')),
              for (final t in tebligatlar)
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text('${t.konu} · ${t.gonderen}'),
                  subtitle: Text(
                    '${t.kanal.ad} · ulaşma ${t.ulasmaTarihi.turkceBicim} · tebliğ ${t.tebligTarihi.turkceBicim}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
