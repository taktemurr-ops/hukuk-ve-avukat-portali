import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

/// Müvekkil bazında masraf avansı, vekâlet ücreti alacağı ve emanet (müvekkil parası).
class FinansEkrani extends StatelessWidget {
  const FinansEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  Future<void> _hareketEkle(BuildContext context, Kisi muvekkil) async {
    final sonuc = await showDialog<(CariHareketTuru, double, String)>(
      context: context,
      builder: (_) => _CariHareketDiyalogu(muvekkilAdi: muvekkil.ad),
    );
    if (sonuc == null) return;
    final (tur, tutar, aciklama) = sonuc;
    final hata = await depo.sunucudaVeyaYerelde(
      sunucuda: (u) => u.cariEkle(muvekkilId: muvekkil.id, tur: tur, tutar: Para.tl(tutar), aciklama: aciklama),
      yerelde: () {
        depo.cariEkle(muvekkilId: muvekkil.id, tur: tur, tutar: Para.tl(tutar), aciklama: aciklama);
        return null;
      },
    );
    if (hata != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  Future<void> _emanetAktar(BuildContext context, Kisi muvekkil, String dosyaId, Para bakiye) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Müvekkile aktarım'),
        content: Text('${bakiye.bicimli} tutarındaki emanet ${muvekkil.ad} hesabına aktarıldı olarak kaydedilsin mi?\n'
            'Banka dekont numarasını açıklamaya eklemeyi unutmayın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(key: const Key('emanet-onayla'), onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (onay != true) return;
    final hareket = EmanetHareketi(
      id: depo.yeniId('e'),
      muvekkilId: muvekkil.id,
      dosyaId: dosyaId,
      tur: EmanetHareketTuru.muvekkileAktarim,
      tutar: bakiye,
      tarih: Tarih.from(DateTime.now()),
      aciklama: 'Müvekkile aktarım',
    );
    final hata = await depo.sunucudaVeyaYerelde(sunucuda: (u) => u.emanetEkle(hareket), yerelde: () => depo.emanetEkle(hareket));
    if (hata != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final bugun = Tarih.from(DateTime.now());
        final bekleyenler = depo.emanet.bekleyenler(bugun);
        final muvekkiller = depo.finansMuvekkilleri;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Finans', style: Theme.of(context).textTheme.headlineMedium),
            const Text('Masraf avansı, vekâlet ücreti ve müvekkil adına tutulan emanet paraları ayrı izlenir.'),
            const SizedBox(height: 16),
            if (bekleyenler.isNotEmpty)
              Card(
                key: const Key('emanet-uyarisi'),
                color: Renkler.uyariZemin,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bekleyen emanet', style: TextStyle(fontWeight: FontWeight.w700, color: Renkler.uyari)),
                      const SizedBox(height: 4),
                      for (final (m, d, b, gun) in bekleyenler)
                        Row(
                          children: [
                            Expanded(
                              child: Text('${depo.kisi(m)?.ad ?? m} · ${depo.dosya(d)?.baslik ?? d}: '
                                  '${b.bicimli}, $gun gündür müvekkile aktarılmadı'),
                            ),
                            TextButton(
                              key: Key('emanet-aktar-$m-$d'),
                              onPressed: () => _emanetAktar(context, depo.kisi(m)!, d, b),
                              child: const Text('Aktarıldı'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            for (final m in muvekkiller) _muvekkilKarti(context, m),
          ],
        );
      },
    );
  }

  Widget _muvekkilKarti(BuildContext context, Kisi m) {
    final o = depo.cariOzet(m.id);
    final emanet = depo.emanet.bakiye(m.id);
    final hareketler = depo.cariHareketler(m.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        baslik: m.ad,
        sag: OutlinedButton.icon(
          key: Key('hareket-ekle-${m.id}'),
          onPressed: () => _hareketEkle(context, m),
          icon: const Icon(Icons.add),
          label: const Text('Hareket'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _Tutar('Masraf avansı bakiyesi', o.avansBakiyesi, key: Key('avans-${m.id}'), uyari: o.avansBakiyesi.negatif),
                _Tutar('Vekâlet ücreti alacağı', o.ucretAlacagi, key: Key('ucret-${m.id}')),
                _Tutar('Emanet (müvekkil parası)', emanet, key: Key('emanet-${m.id}')),
              ],
            ),
            if (o.avansBakiyesi.negatif)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: DurumRozeti('Avans tükendi: büro müvekkil adına masraf yapıyor, avans talep edin', RozetTuru.kritik),
              ),
            const SizedBox(height: 12),
            for (final h in hareketler.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 92, child: Text(h.tarih.turkceBicim, style: const TextStyle(color: Renkler.metinIkincil))),
                    Expanded(child: Text('${h.tur.ad}${h.aciklama.isNotEmpty ? ' · ${h.aciklama}' : ''}')),
                    Text(h.tutar.bicimli),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tutar extends StatelessWidget {
  const _Tutar(this.etiket, this.tutar, {super.key, this.uyari = false});

  final String etiket;
  final Para tutar;
  final bool uyari;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiket, style: const TextStyle(color: Renkler.metinIkincil)),
        Text(
          tutar.bicimli,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: uyari ? Renkler.kritik : Renkler.metin),
        ),
      ],
    );
  }
}

class _CariHareketDiyalogu extends StatefulWidget {
  const _CariHareketDiyalogu({required this.muvekkilAdi});

  final String muvekkilAdi;

  @override
  State<_CariHareketDiyalogu> createState() => _CariHareketDiyaloguState();
}

class _CariHareketDiyaloguState extends State<_CariHareketDiyalogu> {
  final _tutar = TextEditingController();
  final _aciklama = TextEditingController();
  CariHareketTuru _tur = CariHareketTuru.masrafYapildi;
  String? _hata;

  @override
  void dispose() {
    _tutar.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cari hareket · ${widget.muvekkilAdi}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<CariHareketTuru>(
              key: const Key('cari-tur'),
              label: const Text('Tür'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _tur,
              onSelected: (t) => setState(() => _tur = t ?? _tur),
              dropdownMenuEntries: [
                for (final t in CariHareketTuru.values) DropdownMenuEntry(value: t, label: t.ad),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cari-tutar'),
              controller: _tutar,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Tutar (TL)', errorText: _hata),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cari-aciklama'),
              controller: _aciklama,
              decoration: const InputDecoration(labelText: 'Açıklama / belge no'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('cari-kaydet'),
          onPressed: () {
            final v = tutarCoz(_tutar.text);
            if (v == null || v <= 0) {
              setState(() => _hata = 'Geçerli bir tutar girin.');
              return;
            }
            Navigator.pop(context, (_tur, v, _aciklama.text.trim()));
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
