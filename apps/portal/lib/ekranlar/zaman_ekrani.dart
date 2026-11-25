import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'dosyalar_ekrani.dart' show oturumAktoru;

String sureMetni(int dakika) {
  final s = dakika ~/ 60, d = dakika % 60;
  return s == 0 ? '$d dk' : '$s sa ${d.toString().padLeft(2, '0')} dk';
}

RozetTuru _zamanRozeti(ZamanDurumu d) => switch (d) {
      ZamanDurumu.taslak => RozetTuru.devam,
      ZamanDurumu.onaylandi => RozetTuru.onay,
      ZamanDurumu.faturalandi => RozetTuru.notr,
    };

class ZamanEkrani extends StatelessWidget {
  const ZamanEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  static const _onayRolleri = {Rol.buroSahibi, Rol.yoneticiOrtak, Rol.ortak};

  bool get _onaylayabilir => oturum.roller.any(_onayRolleri.contains);

  void _mesaj(BuildContext context, String? hata, [String? basari]) {
    final m = hata ?? basari;
    if (m != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('zaman-elle'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => _ZamanDiyalogu(depo: depo, oturum: oturum)),
        icon: const Icon(Icons.more_time),
        label: const Text('Elle kayıt'),
      ),
      body: ListenableBuilder(
        listenable: depo,
        builder: (context, _) {
          final dosyalar = depo.gorunurDosyalar(oturumAktoru(oturum));
          final idler = dosyalar.map((d) => d.id).toSet();
          final kayitlar = depo.zaman.kayitlar.where((k) => idler.contains(k.dosyaId)).toList()
            ..sort((a, b) => b.tarih.compareTo(a.tarih));
          final bugun = Tarih.from(DateTime.now());
          final haftaBasi = bugun.gunEkle(-(bugun.haftaninGunu - 1));
          final hafta = <String, (int, int)>{};
          for (final k in kayitlar.where((k) => k.tarih.arasinda(haftaBasi, bugun))) {
            final (t, f) = hafta[k.kullanici] ?? (0, 0);
            hafta[k.kullanici] = (t + k.dakika, f + k.faturaDakikasi(birim: depo.zaman.yuvarlamaBirimi));
          }
          final faturalanacak = [
            for (final d in dosyalar)
              if (depo.zamanFaturaOnizleme(d.id).kalemler.isNotEmpty) (d, depo.zamanFaturaOnizleme(d.id)),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Text('Zaman kaydı', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              KronometrePaneli(depo: depo, dosyalar: dosyalar),
              const SizedBox(height: 20),
              Panel(
                baslik: 'Bu hafta',
                child: hafta.isEmpty
                    ? const Text('Bu hafta kayıt yok.')
                    : Wrap(spacing: 24, runSpacing: 12, children: [
                        for (final e in hafta.entries)
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(depo.kullaniciAdi(e.key), style: Theme.of(context).textTheme.bodySmall),
                            Text(sureMetni(e.value.$1), style: Theme.of(context).textTheme.titleLarge),
                            Text('Faturalanabilir ${sureMetni(e.value.$2)}', style: Theme.of(context).textTheme.bodySmall),
                          ]),
                      ]),
              ),
              const SizedBox(height: 20),
              Panel(
                baslik: 'Kayıtlar',
                child: kayitlar.isEmpty
                    ? const Text('Kayıt yok.')
                    : Column(children: [
                        for (final k in kayitlar)
                          ListTile(
                            key: Key('zaman-${k.id}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(k.aciklama),
                            subtitle: Text('${kisaTarih(k.tarih)} · ${depo.kullaniciAdi(k.kullanici)} · '
                                '${depo.dosya(k.dosyaId)?.icNo ?? k.dosyaId} · ${sureMetni(k.dakika)}'
                                '${k.faturalanabilir ? ' · ${k.tutar(birim: depo.zaman.yuvarlamaBirimi).bicimli}' : ' · faturalanmaz'}'),
                            trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              DurumRozeti(k.durum.ad, _zamanRozeti(k.durum)),
                              if (k.durum == ZamanDurumu.taslak && _onaylayabilir && k.kullanici != oturum.kullaniciId)
                                IconButton(
                                  key: Key('zaman-onayla-${k.id}'),
                                  tooltip: 'Onayla',
                                  icon: const Icon(Icons.check_circle_outline, color: Renkler.yesil),
                                  onPressed: () async {
                                    final h = await depo.sunucudaVeyaYerelde(
                                        sunucuda: (u) => u.zamanOnayla(k.id), yerelde: () => depo.zamanOnayla(k.id));
                                    if (context.mounted) _mesaj(context, h);
                                  },
                                ),
                              if (k.durum == ZamanDurumu.taslak && k.kullanici == oturum.kullaniciId)
                                IconButton(
                                  key: Key('zaman-sil-${k.id}'),
                                  tooltip: 'Sil',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final h = await depo.sunucudaVeyaYerelde(
                                        sunucuda: (u) => u.zamanSil(k.id), yerelde: () => depo.zamanSil(k.id));
                                    if (context.mounted) _mesaj(context, h);
                                  },
                                ),
                            ]),
                          ),
                      ]),
              ),
              const SizedBox(height: 20),
              Panel(
                baslik: 'Faturalanmaya hazır',
                child: faturalanacak.isEmpty
                    ? const Text('Onaylanmış, faturalanmamış kayıt yok.')
                    : Column(children: [
                        for (final (d, t) in faturalanacak)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${d.icNo} · ${d.baslik}'),
                            subtitle: Text('${t.kalemler.length} kalem · ${sureMetni(t.toplamDakika)} · ${t.toplam.bicimli} (KDV hariç)'),
                            trailing: FilledButton(
                              key: Key('zaman-fatura-${d.id}'),
                              onPressed: () async {
                                final evet = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: Text('Fatura taslağı ${t.no}'),
                                    content: SizedBox(
                                      width: 480,
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        for (final kalem in t.kalemler)
                                          ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(kalem.kayit.aciklama),
                                            subtitle: Text('${kisaTarih(kalem.kayit.tarih)} · '
                                                '${depo.kullaniciAdi(kalem.kayit.kullanici)} · '
                                                '${sureMetni(kalem.kayit.faturaDakikasi(birim: depo.zaman.yuvarlamaBirimi))}'),
                                            trailing: Text(kalem.tutar.bicimli),
                                          ),
                                        const Divider(),
                                        Row(children: [
                                          const Expanded(child: Text('Toplam (KDV hariç)')),
                                          Text(t.toplam.bicimli, style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ]),
                                        const SizedBox(height: 8),
                                        const Text('Onaylarsanız kayıtlar faturalanmış olur ve tutar müvekkil carisine '
                                            'vekâlet ücreti alacağı olarak yazılır.'),
                                      ]),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                                      FilledButton(
                                          key: const Key('zaman-fatura-onay'),
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Faturala')),
                                    ],
                                  ),
                                );
                                if (evet != true || !context.mounted) return;
                                final h = await depo.sunucudaVeyaYerelde(
                                  sunucuda: (u) => u.zamanFaturaKes(d.id),
                                  yerelde: () => depo.zamanFaturaKes(d.id),
                                );
                                if (context.mounted) _mesaj(context, h, 'Fatura taslağı oluşturuldu, cariye işlendi.');
                              },
                              child: const Text('Faturala'),
                            ),
                          ),
                      ]),
              ),
              if (oturum.lisans.modulAcik(Modul.ekipVeGelirPaylasimi)) ...[
                const SizedBox(height: 20),
                GelirPaylasimiPaneli(depo: depo, dosyalar: dosyalar),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Dosya seçilir, kronometre başlatılır; bitince süre zaman kaydı olur.
class KronometrePaneli extends StatefulWidget {
  const KronometrePaneli({super.key, required this.depo, required this.dosyalar});

  final BellekVeriDeposu depo;
  final List<Dosya> dosyalar;

  @override
  State<KronometrePaneli> createState() => _KronometrePaneliState();
}

class _KronometrePaneliState extends State<KronometrePaneli> {
  final _kronometre = Kronometre();
  final _aciklama = TextEditingController();
  Timer? _zamanlayici;
  String? _dosyaId;
  String? _hata;

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _aciklama.dispose();
    super.dispose();
  }

  void _baslat() {
    if (_dosyaId == null) {
      setState(() => _hata = 'Önce dosya seçin.');
      return;
    }
    _kronometre.baslat(DateTime.now());
    _zamanlayici ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() => _hata = null);
  }

  void _duraklat() {
    _kronometre.duraklat(DateTime.now());
    _zamanlayici?.cancel();
    _zamanlayici = null;
    setState(() {});
  }

  Future<void> _bitir() async {
    _zamanlayici?.cancel();
    _zamanlayici = null;
    final dakika = _kronometre.bitir(DateTime.now());
    final dosyaId = _dosyaId!;
    final aciklama = _aciklama.text.trim().length < 5 ? 'Kronometre ile kaydedilen çalışma' : _aciklama.text;
    final hata = await widget.depo.sunucudaVeyaYerelde(
      sunucuda: (u) => u.zamanEkle(dosyaId: dosyaId, dakika: dakika, aciklama: aciklama),
      yerelde: () => widget.depo.zamanEkle(dosyaId: dosyaId, dakika: dakika, aciklama: aciklama),
    );
    if (!mounted) return;
    setState(() {
      _hata = hata;
      if (hata == null) _aciklama.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final gecen = _kronometre.gecen(DateTime.now());
    final saat = '${gecen.inHours.toString().padLeft(2, '0')}:'
        '${(gecen.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(gecen.inSeconds % 60).toString().padLeft(2, '0')}';
    final basladi = _kronometre.calisiyor || gecen > Duration.zero;
    return Panel(
      baslik: 'Kronometre',
      child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownMenu<String>(
          key: const Key('kronometre-dosya'),
          label: const Text('Dosya'),
          width: 320,
          initialSelection: _dosyaId,
          onSelected: (v) => setState(() => _dosyaId = v),
          dropdownMenuEntries: [
            for (final d in widget.dosyalar) DropdownMenuEntry(value: d.id, label: '${d.icNo} · ${d.baslik}'),
          ],
        ),
        SizedBox(
          width: 320,
          child: TextField(
            key: const Key('kronometre-aciklama'),
            controller: _aciklama,
            decoration: const InputDecoration(labelText: 'Ne üzerinde çalışıyorsunuz?'),
          ),
        ),
        Text(saat, key: const Key('kronometre-sure'), style: Theme.of(context).textTheme.headlineSmall),
        if (_kronometre.calisiyor)
          OutlinedButton.icon(
              key: const Key('kronometre-duraklat'),
              onPressed: _duraklat,
              icon: const Icon(Icons.pause),
              label: const Text('Duraklat'))
        else
          FilledButton.icon(
              key: const Key('kronometre-baslat'),
              onPressed: _baslat,
              icon: const Icon(Icons.play_arrow),
              label: Text(basladi ? 'Devam' : 'Başlat')),
        if (basladi)
          FilledButton.tonalIcon(
              key: const Key('kronometre-bitir'),
              onPressed: _bitir,
              icon: const Icon(Icons.stop),
              label: const Text('Bitir ve kaydet')),
        if (_hata != null) Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
      ]),
    );
  }
}

class _ZamanDiyalogu extends StatefulWidget {
  const _ZamanDiyalogu({required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<_ZamanDiyalogu> createState() => _ZamanDiyaloguState();
}

class _ZamanDiyaloguState extends State<_ZamanDiyalogu> {
  final _sure = TextEditingController();
  final _aciklama = TextEditingController();
  String? _dosyaId;
  bool _faturalanabilir = true;
  String? _hata;

  @override
  void dispose() {
    _sure.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  /// "90", "1:30", "1,5" (saat) biçimlerini dakikaya çevirir.
  static int? dakikaCoz(String metin) {
    final s = metin.trim();
    final saatDakika = RegExp(r'^(\d+):(\d{1,2})$').firstMatch(s);
    if (saatDakika != null) return int.parse(saatDakika[1]!) * 60 + int.parse(saatDakika[2]!);
    if (s.contains(',') || s.contains('.')) {
      final saat = double.tryParse(s.replaceAll(',', '.'));
      return saat == null ? null : (saat * 60).round();
    }
    return int.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final dosyalar = widget.depo.gorunurDosyalar(oturumAktoru(widget.oturum));
    return AlertDialog(
      title: const Text('Zaman kaydı'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownMenu<String>(
            key: const Key('zaman-dosya'),
            label: const Text('Dosya'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _dosyaId = v),
            dropdownMenuEntries: [
              for (final d in dosyalar) DropdownMenuEntry(value: d.id, label: '${d.icNo} · ${d.baslik}'),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('zaman-sure'),
            controller: _sure,
            decoration: const InputDecoration(labelText: 'Süre (dakika, 1:30 veya 1,5 saat)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('zaman-aciklama'),
            controller: _aciklama,
            decoration: const InputDecoration(labelText: 'Yapılan iş'),
          ),
          SwitchListTile(
            key: const Key('zaman-faturalanabilir'),
            contentPadding: EdgeInsets.zero,
            value: _faturalanabilir,
            onChanged: (v) => setState(() => _faturalanabilir = v),
            title: const Text('Faturalanabilir'),
          ),
          if (_hata != null) Text(_hata!, key: const Key('zaman-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('zaman-kaydet'),
          onPressed: () async {
            final dk = dakikaCoz(_sure.text);
            final dosyaId = _dosyaId;
            if (dosyaId == null || dk == null) {
              setState(() => _hata = 'Dosya ve süre girin.');
              return;
            }
            final aciklama = _aciklama.text;
            final fat = _faturalanabilir;
            final hata = await widget.depo.sunucudaVeyaYerelde(
              sunucuda: (u) => u.zamanEkle(dosyaId: dosyaId, dakika: dk, aciklama: aciklama, faturalanabilir: fat),
              yerelde: () => widget.depo.zamanEkle(dosyaId: dosyaId, dakika: dk, aciklama: aciklama, faturalanabilir: fat),
            );
            if (!mounted) return;
            if (hata == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = hata);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class GelirPaylasimiPaneli extends StatefulWidget {
  const GelirPaylasimiPaneli({super.key, required this.depo, required this.dosyalar});

  final BellekVeriDeposu depo;
  final List<Dosya> dosyalar;

  @override
  State<GelirPaylasimiPaneli> createState() => _GelirPaylasimiPaneliState();
}

class _GelirPaylasimiPaneliState extends State<GelirPaylasimiPaneli> {
  final _tutar = TextEditingController();
  String? _dosyaId;

  @override
  void dispose() {
    _tutar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tutar = tutarCoz(_tutar.text);
    Dosya? dosya;
    for (final d in widget.dosyalar) {
      if (d.id == _dosyaId) dosya = d;
    }
    final d = dosya;
    final dagilim = d == null || tutar == null || tutar <= 0
        ? null
        : GelirPaylasimi.dagit(
            tahsilat: Para.tl(tutar),
            getiren: d.sorumlu,
            calisanDakikalari: widget.depo.dosyaCalisanDakikalari(d.id),
          );
    const k = PaylasimKurali.varsayilan;
    return Panel(
      baslik: 'Gelir paylaşımı',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kural: dosyayı getiren %${k.getiren}, dosyada çalışanlar %${k.calisan} (çalıştıkları süre oranında), '
            'büro %${k.buro}. Kuruş farkları büroya yazılır.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 12, children: [
          DropdownMenu<String>(
            key: const Key('paylasim-dosya'),
            label: const Text('Dosya'),
            width: 320,
            onSelected: (v) => setState(() => _dosyaId = v),
            dropdownMenuEntries: [
              for (final x in widget.dosyalar) DropdownMenuEntry(value: x.id, label: '${x.icNo} · ${x.baslik}'),
            ],
          ),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('paylasim-tutar'),
              controller: _tutar,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tahsil edilen ücret (TL)'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        if (dagilim != null) ...[
          const SizedBox(height: 12),
          for (final e in dagilim.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                    child: Text(e.key == GelirPaylasimi.buroHesabi
                        ? 'Büro'
                        : '${widget.depo.kullaniciAdi(e.key)}${e.key == d!.sorumlu ? ' (getiren)' : ''}')),
                Text(e.value.bicimli, key: Key('paylasim-${e.key}')),
              ]),
            ),
        ],
      ]),
    );
  }
}
