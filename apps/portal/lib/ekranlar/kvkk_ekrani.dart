import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

RozetTuru _imhaRozeti(ImhaDurumu d) => switch (d) {
      ImhaDurumu.imhayaHazir => RozetTuru.uyari,
      ImhaDurumu.engelli => RozetTuru.kritik,
      ImhaDurumu.saklaniyor => RozetTuru.onay,
      ImhaDurumu.sureBaslamadi => RozetTuru.notr,
    };

/// KVKK saklama ve imha: kurallar, imha zamanı gelen kayıtlar, dört göz onaylı imha tutanakları.
class KvkkEkrani extends StatefulWidget {
  const KvkkEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<KvkkEkrani> createState() => _KvkkEkraniState();
}

class _KvkkEkraniState extends State<KvkkEkrani> {
  final Set<String> _secilen = {};
  ImhaYontemi _yontem = ImhaYontemi.yokEtme;

  void _mesaj(String? h, String basari) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h ?? basari)));

  @override
  Widget build(BuildContext context) {
    final depo = widget.depo;
    return Scaffold(
      appBar: AppBar(title: const Text('KVKK: saklama ve imha')),
      body: ListenableBuilder(
        listenable: depo,
        builder: (context, _) {
          final s = depo.saklama;
          final bugun = Tarih.from(DateTime.now());
          final degerlendirme = s.degerlendirTumu(depo.saklamaKayitlari, bugun);
          final hazir = degerlendirme.where((d) => d.durum == ImhaDurumu.imhayaHazir).toList();
          _secilen.removeWhere((id) => !hazir.any((d) => d.kayit.id == id));
          final sonraki = s.sonrakiPeriyodikImha();
          final metin = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Panel(
              baslik: 'Periyodik imha',
              sag: s.periyodikImhaGecikti(bugun)
                  ? const DurumRozeti('Gecikti', RozetTuru.kritik)
                  : const DurumRozeti('Zamanında', RozetTuru.onay),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Son periyodik imha: ${s.sonPeriyodikImha?.turkceBicim ?? 'yapılmadı'}'),
                Text('Sonraki en geç: ${sonraki?.turkceBicim ?? 'ilk imhadan sonra belirlenir'}', key: const Key('kvkk-sonraki')),
                const SizedBox(height: 6),
                Text('Silme, yok etme ve anonim hâle getirme yönetmeliği uyarınca periyodik imha aralığı '
                    '${SaklamaVeImha.periyodikImhaAyi} ayı geçemez.', style: metin.bodySmall),
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Saklama süreleri',
              sag: const DurumRozeti('Taslak · avukat onayı bekliyor', RozetTuru.uyari),
              child: Column(children: [
                for (final k in s.kurallar)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(k.kategori.ad),
                    subtitle: Text(k.dayanak),
                    trailing: Text('${k.sureYil} yıl', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Kayıtlar (${hazir.length} imhaya hazır)',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final d in degerlendirme.where((d) => d.durum != ImhaDurumu.sureBaslamadi))
                  CheckboxListTile(
                    key: Key('kvkk-${d.kayit.id}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _secilen.contains(d.kayit.id),
                    onChanged: d.durum != ImhaDurumu.imhayaHazir
                        ? null
                        : (v) => setState(() => v == true ? _secilen.add(d.kayit.id) : _secilen.remove(d.kayit.id)),
                    title: Text(d.kayit.ad),
                    subtitle: Text([
                      d.kayit.kategori.ad,
                      if (d.kayit.kapanis != null) 'kapanış ${d.kayit.kapanis!.turkceBicim}',
                      if (d.imhaTarihi != null) 'imha ${d.imhaTarihi!.turkceBicim}',
                      if (d.kayit.yasalSaklamaEngeli != null) 'engel: ${d.kayit.yasalSaklamaEngeli}',
                    ].join(' · ')),
                    secondary: DurumRozeti(d.durum.ad, _imhaRozeti(d.durum)),
                  ),
                Text('Açık dosyalar listelenmez; saklama süresi dosya kapanınca başlar.', style: metin.bodySmall),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SegmentedButton<ImhaYontemi>(
                    segments: [for (final y in ImhaYontemi.values) ButtonSegment(value: y, label: Text(y.ad))],
                    selected: {_yontem},
                    onSelectionChanged: (v) => setState(() => _yontem = v.first),
                  ),
                  FilledButton(
                    key: const Key('kvkk-tutanak'),
                    onPressed: _secilen.isEmpty
                        ? null
                        : () async {
                            final h = await depo.imhaTutanagiHazirla({..._secilen}, _yontem);
                            if (!mounted) return;
                            if (h == null) setState(_secilen.clear);
                            _mesaj(h, 'İmha tutanağı hazırlandı; ikinci bir yetkilinin onayı bekleniyor.');
                          },
                    child: Text('Tutanak hazırla (${_secilen.length})'),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'İmha tutanakları',
              child: s.tutanaklar.isEmpty
                  ? const Text('Tutanak yok.')
                  : Column(children: [
                      for (final t in s.tutanaklar.reversed)
                        ListTile(
                          key: Key('kvkk-tutanak-${t.no}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text('${t.no} · ${t.kayitIdleri.length} kayıt · ${t.yontem.ad}'),
                          subtitle: Text('Hazırlayan ${depo.kullaniciAdi(t.hazirlayan)}, ${kisaTarih(t.tarih)}'
                              '${t.onaylandi ? ' · onaylayan ${depo.kullaniciAdi(t.onaylayan!)}, ${t.onayTarihi!.turkceBicim}' : ''}'),
                          trailing: t.onaylandi
                              ? const DurumRozeti('Onaylandı', RozetTuru.onay)
                              : t.hazirlayan == depo.aktifKullanici
                                  ? const DurumRozeti('İkinci onay bekliyor', RozetTuru.uyari)
                                  : FilledButton(
                                      key: Key('kvkk-onayla-${t.no}'),
                                      onPressed: () async {
                                        final h = await depo.imhaTutanagiOnayla(t);
                                        if (mounted) _mesaj(h, 'İmha onaylandı.');
                                      },
                                      child: const Text('Onayla ve imha et'),
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
