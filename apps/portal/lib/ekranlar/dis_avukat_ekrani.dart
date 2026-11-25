import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kurumsal_depo.dart';
import '../tema/tema.dart';

RozetTuru _butceRozeti(ButceDurumu d) => switch (d) {
      ButceDurumu.normal => RozetTuru.onay,
      ButceDurumu.uyari => RozetTuru.uyari,
      ButceDurumu.asim => RozetTuru.kritik,
    };

RozetTuru _faturaRozeti(FaturaDurumu d) => switch (d) {
      FaturaDurumu.bekliyor => RozetTuru.uyari,
      FaturaDurumu.onaylandi => RozetTuru.onay,
      FaturaDurumu.finansaGonderildi => RozetTuru.notr,
      FaturaDurumu.reddedildi => RozetTuru.kritik,
    };

class DisAvukatlarEkrani extends StatelessWidget {
  const DisAvukatlarEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  void _mesaj(BuildContext context, String? h, [String? basari]) {
    final m = h ?? basari;
    if (m != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final k = kurumsal;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dis-is-yeni'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => _IsDiyalogu(kurumsal: k)),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Yeni iş'),
      ),
      body: ListenableBuilder(
        listenable: k,
        builder: (context, _) {
          final metin = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
            Row(children: [
              Expanded(child: Text('Dış avukatlar', style: metin.headlineMedium)),
              OutlinedButton.icon(
                key: const Key('dis-buro-yeni'),
                onPressed: () => showDialog<void>(context: context, builder: (_) => _BuroDiyalogu(kurumsal: k)),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Büro ekle'),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final o in k.disAvukatOzetleri)
                SizedBox(
                  width: 300,
                  child: Panel(
                    baslik: o.avukat.buro,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${o.avukat.sorumluAvukat} · ${o.avukat.uzmanliklar.join(', ')}', style: metin.bodySmall),
                      const SizedBox(height: 8),
                      Text('Harcanan ${o.harcanan.bicimli} / bütçe ${o.butce.bicimli}'),
                      Text('${o.acikIs} açık iş · onay bekleyen ${o.bekleyen.bicimli}', style: metin.bodySmall),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            for (final i in k.disAvukatIsleri) ...[
              Panel(
                baslik: i.konu,
                sag: DurumRozeti(i.butceDurumu.ad, _butceRozeti(i.butceDurumu)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${k.disAvukat(i.disAvukatId)?.buro ?? i.disAvukatId} · başlangıç ${i.baslangic.turkceBicim}',
                      style: metin.bodySmall),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: Key('butce-${i.id}'),
                      value: (i.kullanimYuzdesi / 100).clamp(0, 1).toDouble(),
                      minHeight: 10,
                      backgroundColor: Renkler.kenar,
                      color: switch (i.butceDurumu) {
                        ButceDurumu.normal => Renkler.yesil,
                        ButceDurumu.uyari => Renkler.uyari,
                        ButceDurumu.asim => Renkler.kritik,
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('%${i.kullanimYuzdesi} · harcanan ${i.harcanan.bicimli} / ${i.butce.bicimli}'
                      '${i.bekleyen.kurus > 0 ? ' · onay bekleyen ${i.bekleyen.bicimli}' : ''}'),
                  for (final a in i.butceArtislari)
                    Text('Bütçe artışı ${a.tutar.bicimli}: ${a.gerekce} (${kisaTarih(a.tarih)})', style: metin.bodySmall),
                  const Divider(height: 24),
                  if (i.faturalar.isEmpty) const Text('Fatura yok.'),
                  for (final f in i.faturalar)
                    ListTile(
                      key: Key('fatura-${f.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('${f.no} · ${f.tutar.bicimli}'),
                      subtitle: Text('${kisaTarih(f.tarih)} · ${f.aciklama}'
                          '${f.retGerekcesi == null ? '' : ' · ret: ${f.retGerekcesi}'}'),
                      trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        DurumRozeti(f.durum.ad, _faturaRozeti(f.durum)),
                        if (f.durum == FaturaDurumu.bekliyor) ...[
                          IconButton(
                            key: Key('fatura-onayla-${f.id}'),
                            tooltip: 'Onayla',
                            icon: const Icon(Icons.check_circle_outline, color: Renkler.yesil),
                            onPressed: () async {
                              final h = await k.sunucudaVeyaYerelde(
                                sunucuda: (u) => u.disFaturaIslemi(f.id, 'onayla'),
                                yerelde: () =>
                                    k.disAvukatIslemi('Fatura onaylandı: ${f.no}', i.id, () => i.faturaOnayla(f, k.kullaniciId)),
                              );
                              if (context.mounted) _mesaj(context, h);
                            },
                          ),
                          IconButton(
                            key: Key('fatura-reddet-${f.id}'),
                            tooltip: 'Reddet',
                            icon: const Icon(Icons.cancel_outlined, color: Renkler.kritik),
                            onPressed: () async {
                              final g = await MetinGirisDiyalogu.goster(
                                context,
                                const MetinGirisDiyalogu(
                                  baslik: 'Faturayı reddet',
                                  etiket: 'Ret gerekçesi',
                                  alanAnahtari: Key('ret-gerekce'),
                                  onayAnahtari: Key('ret-onay'),
                                ),
                              );
                              if (g == null || !context.mounted) return;
                              final h = await k.sunucudaVeyaYerelde(
                                sunucuda: (u) => u.disFaturaIslemi(f.id, 'reddet', gerekce: g),
                                yerelde: () => k.disAvukatIslemi(
                                    'Fatura reddedildi: ${f.no}', i.id, () => i.faturaReddet(f, k.kullaniciId, g)),
                              );
                              if (context.mounted) _mesaj(context, h);
                            },
                          ),
                        ],
                        if (f.durum == FaturaDurumu.onaylandi)
                          TextButton(
                            key: Key('fatura-finans-${f.id}'),
                            onPressed: () async {
                              final h = await k.sunucudaVeyaYerelde(
                                sunucuda: (u) => u.disFaturaIslemi(f.id, 'finans'),
                                yerelde: () => k.disAvukatIslemi('Finansa gönderildi: ${f.no}', i.id, () => i.finansaGonder(f)),
                              );
                              if (context.mounted) _mesaj(context, h);
                            },
                            child: const Text('Finansa gönder'),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      key: Key('is-fatura-${i.id}'),
                      onPressed: i.kapali
                          ? null
                          : () => showDialog<void>(context: context, builder: (_) => _FaturaDiyalogu(kurumsal: k, isi: i)),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Fatura ekle'),
                    ),
                    OutlinedButton.icon(
                      key: Key('is-butce-${i.id}'),
                      onPressed: () => showDialog<void>(context: context, builder: (_) => _ButceDiyalogu(kurumsal: k, isi: i)),
                      icon: const Icon(Icons.trending_up, size: 18),
                      label: const Text('Bütçe artışı'),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
            ],
          ]);
        },
      ),
    );
  }
}

/// Ortak form kalıbı: alanlar, hata satırı ve kaydet düğmesi.
abstract class _FormDiyalogu extends StatefulWidget {
  const _FormDiyalogu({required this.kurumsal});
  final KurumsalDepo kurumsal;
}

class _IsDiyalogu extends _FormDiyalogu {
  const _IsDiyalogu({required super.kurumsal});

  @override
  State<_IsDiyalogu> createState() => _IsDiyaloguState();
}

class _IsDiyaloguState extends State<_IsDiyalogu> {
  final _konu = TextEditingController();
  final _butce = TextEditingController();
  String? _avukat;
  String? _hata;

  @override
  void dispose() {
    _konu.dispose();
    _butce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return AlertDialog(
      title: const Text('Dış avukata yeni iş'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownMenu<String>(
            key: const Key('dis-is-avukat'),
            label: const Text('Büro'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _avukat = v),
            dropdownMenuEntries: [for (final a in k.disAvukatlar) DropdownMenuEntry(value: a.id, label: a.buro)],
          ),
          TextField(key: const Key('dis-is-konu'), controller: _konu, decoration: const InputDecoration(labelText: 'Konu')),
          TextField(
              key: const Key('dis-is-butce'), controller: _butce, decoration: const InputDecoration(labelText: 'Bütçe (TL, KDV hariç)')),
          if (_hata != null) Text(_hata!, key: const Key('dis-is-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('dis-is-kaydet'),
          onPressed: () async {
            final b = tutarCoz(_butce.text);
            final a = _avukat;
            if (a == null || b == null || b <= 0 || _konu.text.trim().isEmpty) {
              setState(() => _hata = 'Büro, konu ve bütçe zorunludur.');
              return;
            }
            final konu = _konu.text;
            final h = await k.sunucudaVeyaYerelde(
              sunucuda: (u) => u.disIsAc(disAvukatId: a, konu: konu, butce: Para.tl(b)),
              yerelde: () {
                k.disAvukatIsiAc(disAvukatId: a, konu: konu, butce: Para.tl(b));
                return null;
              },
            );
            if (!mounted) return;
            if (h != null) {
              setState(() => _hata = h);
              return;
            }
            Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _FaturaDiyalogu extends _FormDiyalogu {
  const _FaturaDiyalogu({required super.kurumsal, required this.isi});
  final DisAvukatIsi isi;

  @override
  State<_FaturaDiyalogu> createState() => _FaturaDiyaloguState();
}

class _FaturaDiyaloguState extends State<_FaturaDiyalogu> {
  final _no = TextEditingController();
  final _tutar = TextEditingController();
  final _aciklama = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _no.dispose();
    _tutar.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return AlertDialog(
      title: const Text('Fatura ekle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('fatura-no'), controller: _no, decoration: const InputDecoration(labelText: 'Fatura no')),
          TextField(
              key: const Key('fatura-tutar'), controller: _tutar, decoration: const InputDecoration(labelText: 'Tutar (TL, KDV hariç)')),
          TextField(
              key: const Key('fatura-aciklama'), controller: _aciklama, decoration: const InputDecoration(labelText: 'Açıklama')),
          if (_hata != null) Text(_hata!, key: const Key('fatura-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('fatura-kaydet'),
          onPressed: () async {
            final t = tutarCoz(_tutar.text);
            if (t == null || _no.text.trim().isEmpty) {
              setState(() => _hata = 'Fatura no ve tutar zorunludur.');
              return;
            }
            final no = _no.text;
            final aciklama = _aciklama.text;
            final h = await k.sunucudaVeyaYerelde(
              sunucuda: (u) => u.disFaturaEkle(widget.isi.id, no: no, tutar: Para.tl(t), aciklama: aciklama),
              yerelde: () => k.disAvukatIslemi(
                'Fatura eklendi: ${no.trim()}',
                widget.isi.id,
                () => widget.isi.faturaEkle(
                    id: 'df${DateTime.now().microsecondsSinceEpoch}',
                    no: no,
                    tarih: k.bugunTarih,
                    tutar: Para.tl(t),
                    aciklama: aciklama),
              ),
            );
            if (!mounted) return;
            if (h == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = h);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _ButceDiyalogu extends _FormDiyalogu {
  const _ButceDiyalogu({required super.kurumsal, required this.isi});
  final DisAvukatIsi isi;

  @override
  State<_ButceDiyalogu> createState() => _ButceDiyaloguState();
}

class _ButceDiyaloguState extends State<_ButceDiyalogu> {
  final _tutar = TextEditingController();
  final _gerekce = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _tutar.dispose();
    _gerekce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return AlertDialog(
      title: const Text('Bütçe artışı'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Mevcut bütçe ${widget.isi.butce.bicimli}, harcanan ${widget.isi.harcanan.bicimli}.'),
          TextField(
              key: const Key('butce-tutar'), controller: _tutar, decoration: const InputDecoration(labelText: 'Artış (TL)')),
          TextField(
              key: const Key('butce-gerekce'), controller: _gerekce, decoration: const InputDecoration(labelText: 'Gerekçe')),
          if (_hata != null) Text(_hata!, key: const Key('butce-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('butce-kaydet'),
          onPressed: () async {
            final t = tutarCoz(_tutar.text);
            final gerekce = _gerekce.text;
            final h = t == null
                ? 'Tutarı kontrol edin.'
                : await k.sunucudaVeyaYerelde(
                    sunucuda: (u) => u.disButceArtir(widget.isi.id, Para.tl(t), gerekce),
                    yerelde: () => k.disAvukatIslemi('Bütçe artışı ${Para.tl(t).bicimli}', widget.isi.id,
                        () => widget.isi.butceArtir(Para.tl(t), gerekce, k.kullaniciId, k.bugunTarih)),
                  );
            if (!mounted) return;
            if (h == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = h);
            }
          },
          child: const Text('Onayla'),
        ),
      ],
    );
  }
}

/// Anlaşmalı dış avukat bürosu ekleme.
class _BuroDiyalogu extends _FormDiyalogu {
  const _BuroDiyalogu({required super.kurumsal});

  @override
  State<_BuroDiyalogu> createState() => _BuroDiyaloguState();
}

class _BuroDiyaloguState extends State<_BuroDiyalogu> {
  final _buro = TextEditingController();
  final _avukat = TextEditingController();
  final _eposta = TextEditingController();
  final _uzmanlik = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    for (final c in [_buro, _avukat, _eposta, _uzmanlik]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    final k = widget.kurumsal;
    final eposta = _eposta.text.trim();
    final hata = _buro.text.trim().length < 2 || _avukat.text.trim().isEmpty
        ? 'Büro ve sorumlu avukat zorunludur.'
        : Dogrulayicilar.eposta(eposta);
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    final uzmanliklar = [for (final x in _uzmanlik.text.split(',')) if (x.trim().isNotEmpty) x.trim()];
    final h = await k.sunucudaVeyaYerelde(
      sunucuda: (u) => u.disAvukatEkle(buro: _buro.text, sorumluAvukat: _avukat.text, eposta: eposta, uzmanliklar: uzmanliklar),
      yerelde: () => k.disAvukatEkle(buro: _buro.text, sorumluAvukat: _avukat.text, eposta: eposta, uzmanliklar: uzmanliklar),
    );
    if (!mounted) return;
    if (h != null) {
      setState(() => _hata = h);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dış avukat bürosu ekle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('buro-ad'), controller: _buro, decoration: const InputDecoration(labelText: 'Büro')),
          TextField(key: const Key('buro-avukat'), controller: _avukat, decoration: const InputDecoration(labelText: 'Sorumlu avukat')),
          TextField(
              key: const Key('buro-eposta'),
              controller: _eposta,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta')),
          TextField(
              key: const Key('buro-uzmanlik'),
              controller: _uzmanlik,
              decoration: const InputDecoration(labelText: 'Uzmanlıklar (virgülle)')),
          if (_hata != null) Text(_hata!, key: const Key('buro-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(key: const Key('buro-kaydet'), onPressed: _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
