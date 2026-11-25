import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kurumsal_depo.dart';
import '../tema/tema.dart';
import 'sozlesmeler_ekrani.dart';

RozetTuru slaRozeti(SlaDurumu s) => switch (s) {
      SlaDurumu.zamaninda => RozetTuru.onay,
      SlaDurumu.riskli => RozetTuru.uyari,
      SlaDurumu.gecikti => RozetTuru.kritik,
      SlaDurumu.durduruldu => RozetTuru.notr,
    };

RozetTuru oncelikRozeti(Oncelik o) => switch (o) {
      Oncelik.acil => RozetTuru.kritik,
      Oncelik.yuksek => RozetTuru.uyari,
      Oncelik.normal => RozetTuru.devam,
      Oncelik.dusuk => RozetTuru.notr,
    };

enum _Gorunum {
  acik('Açık'),
  benim('Bana atanan'),
  atanmamis('Atanmamış'),
  tumu('Tümü');

  const _Gorunum(this.ad);
  final String ad;
}

class TaleplerEkrani extends StatefulWidget {
  const TaleplerEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  State<TaleplerEkrani> createState() => _TaleplerEkraniState();
}

class _TaleplerEkraniState extends State<TaleplerEkrani> {
  _Gorunum _gorunum = _Gorunum.acik;

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('talep-yeni'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => TalepFormu(kurumsal: k)),
        icon: const Icon(Icons.add),
        label: const Text('Yeni talep'),
      ),
      body: ListenableBuilder(
        listenable: k,
        builder: (context, _) {
          final hepsi = k.defter.talepler;
          final acik = hepsi.where((t) => !t.durum.kapali).toList();
          final liste = switch (_gorunum) {
            _Gorunum.acik => acik.toList(),
            _Gorunum.benim => acik.where((t) => t.atanan == k.kullaniciId).toList(),
            _Gorunum.atanmamis => acik.where((t) => t.atanan.isEmpty).toList(),
            _Gorunum.tumu => hepsi.toList(),
          };
          liste.sort((a, b) => a.slaSonGun.compareTo(b.slaSonGun));
          int say(SlaDurumu s) => acik.where((t) => k.sla(t) == s).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Text('Hukuk talepleri', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('İş birimlerinden gelen talepler hizmet süresine (SLA) göre sıralanır.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                DurumRozeti('${acik.length} açık', RozetTuru.devam),
                DurumRozeti('${say(SlaDurumu.gecikti)} gecikti', RozetTuru.kritik),
                DurumRozeti('${say(SlaDurumu.riskli)} süre doluyor', RozetTuru.uyari),
                DurumRozeti('${say(SlaDurumu.durduruldu)} bilgi bekliyor', RozetTuru.notr),
              ]),
              const SizedBox(height: 16),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in _Gorunum.values)
                      ChoiceChip(
                        key: Key('talep-gorunum-${g.name}'),
                        label: Text(g.ad),
                        selected: _gorunum == g,
                        onSelected: (_) => setState(() => _gorunum = g),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  if (liste.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Talep yok.'))
                  else
                    for (final t in liste)
                      _TalepSatiri(
                        t,
                        k,
                        () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => TalepDetayEkrani(kurumsal: k, talepId: t.id))),
                      ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TalepSatiri extends StatelessWidget {
  const _TalepSatiri(this.t, this.k, this.ac);

  final HukukTalebi t;
  final KurumsalDepo k;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final sla = k.sla(t);
    final kucuk = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      key: Key('talep-${t.id}'),
      onTap: ac,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renkler.kenar))),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${t.no} · ${t.tur.ad} · ${t.birim}', style: kucuk),
            ]),
          ),
          Expanded(flex: 2, child: Text(k.kisiAdi(t.atanan), style: kucuk)),
          Expanded(flex: 2, child: Text('${kisaTarih(t.slaSonGun)} · ${t.durum.ad}', style: kucuk)),
          DurumRozeti(t.oncelik.ad, oncelikRozeti(t.oncelik)),
          const SizedBox(width: 8),
          if (!t.durum.kapali) DurumRozeti(sla.ad, slaRozeti(sla)),
        ]),
      ),
    );
  }
}

class TalepFormu extends StatefulWidget {
  const TalepFormu({super.key, required this.kurumsal, this.sozlesmeId});

  final KurumsalDepo kurumsal;
  final String? sozlesmeId;

  @override
  State<TalepFormu> createState() => _TalepFormuState();
}

class _TalepFormuState extends State<TalepFormu> {
  final _baslik = TextEditingController();
  final _aciklama = TextEditingController();
  final _birim = TextEditingController();
  TalepTuru _tur = TalepTuru.sozlesmeInceleme;
  Oncelik _oncelik = Oncelik.normal;
  String? _hata;

  @override
  void dispose() {
    _baslik.dispose();
    _aciklama.dispose();
    _birim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    final sonGun = k.hesap.ekle(k.bugunTarih, _oncelik.slaIsGunu(_tur));
    return AlertDialog(
      title: const Text('Yeni hukuk talebi'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
                key: const Key('talep-baslik'),
                controller: _baslik,
                decoration: const InputDecoration(labelText: 'Konu')),
            const SizedBox(height: 12),
            DropdownMenu<TalepTuru>(
              key: const Key('talep-tur'),
              label: const Text('Talep türü'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _tur,
              onSelected: (t) => setState(() => _tur = t ?? _tur),
              dropdownMenuEntries: [for (final t in TalepTuru.values) DropdownMenuEntry(value: t, label: t.ad)],
            ),
            const SizedBox(height: 12),
            SegmentedButton<Oncelik>(
              key: const Key('talep-oncelik'),
              segments: [for (final o in Oncelik.values) ButtonSegment(value: o, label: Text(o.ad))],
              selected: {_oncelik},
              onSelectionChanged: (s) => setState(() => _oncelik = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
                key: const Key('talep-birim'),
                controller: _birim,
                decoration: const InputDecoration(labelText: 'Talep eden birim')),
            const SizedBox(height: 12),
            TextField(
              key: const Key('talep-aciklama'),
              controller: _aciklama,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Açıklama ve beklenen çıktı'),
            ),
            const SizedBox(height: 12),
            Text('Hedef yanıt: ${uzunTarih(sonGun)} (${_oncelik.slaIsGunu(_tur)} iş günü)',
                key: const Key('talep-sla'), style: Theme.of(context).textTheme.bodySmall),
            if (_hata != null) ...[
              const SizedBox(height: 8),
              Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('talep-gonder'),
          onPressed: () {
            if (_baslik.text.trim().isEmpty || _birim.text.trim().isEmpty) {
              setState(() => _hata = 'Konu ve birim zorunludur.');
              return;
            }
            k.talepOlustur(
              baslik: _baslik.text,
              aciklama: _aciklama.text,
              tur: _tur,
              oncelik: _oncelik,
              birim: _birim.text.trim(),
              sozlesmeId: widget.sozlesmeId,
            );
            Navigator.pop(context);
          },
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}

class TalepDetayEkrani extends StatelessWidget {
  const TalepDetayEkrani({super.key, required this.kurumsal, required this.talepId});

  final KurumsalDepo kurumsal;
  final String talepId;

  static const _notGerekir = {TalepDurumu.reddedildi, TalepDurumu.bilgiBekleniyor};

  Future<void> _gecis(BuildContext context, HukukTalebi t, TalepDurumu hedef) async {
    var not = '';
    if (_notGerekir.contains(hedef)) {
      final girilen = await MetinGirisDiyalogu.goster(
        context,
        MetinGirisDiyalogu(
          baslik: hedef.ad,
          etiket: hedef == TalepDurumu.reddedildi ? 'Ret gerekçesi' : 'Talep edenden beklenen bilgi',
          onayMetni: 'Kaydet',
          alanAnahtari: const Key('talep-not'),
          onayAnahtari: const Key('talep-not-kaydet'),
        ),
      );
      if (girilen == null || girilen.trim().isEmpty) return;
      not = girilen.trim();
    }
    try {
      kurumsal.talepDurumu(t, hedef, not: not);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kurumsal,
      builder: (context, _) {
        HukukTalebi? bulunan;
        for (final t in kurumsal.defter.talepler) {
          if (t.id == talepId) bulunan = t;
        }
        final t = bulunan;
        if (t == null) return const Scaffold(body: Center(child: Text('Talep bulunamadı.')));
        final sla = kurumsal.sla(t);
        final sonraki = TalepDurumu.gecisler[t.durum]!;
        final sozlesme = t.sozlesmeId == null ? null : kurumsal.sozlesme(t.sozlesmeId!);
        return Scaffold(
          appBar: AppBar(title: Text(t.no)),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Panel(
              baslik: t.baslik,
              sag: DurumRozeti(t.durum.ad, t.durum.kapali ? RozetTuru.notr : RozetTuru.devam),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (t.aciklama.isNotEmpty) ...[Text(t.aciklama), const SizedBox(height: 12)],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  DurumRozeti(t.tur.ad, RozetTuru.notr),
                  DurumRozeti('Öncelik: ${t.oncelik.ad}', oncelikRozeti(t.oncelik)),
                  if (!t.durum.kapali) DurumRozeti(sla.ad, slaRozeti(sla)),
                ]),
                const SizedBox(height: 12),
                Text('Talep eden: ${t.talepEden} · ${t.birim}'),
                Text('Açılış: ${uzunTarih(t.olusturma)}'),
                Text('Hedef yanıt: ${uzunTarih(t.slaSonGun)}', key: const Key('talep-son-gun')),
                if (sozlesme != null)
                  TextButton.icon(
                    key: const Key('talep-sozlesme'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => SozlesmeDetayEkrani(kurumsal: kurumsal, sozlesmeId: sozlesme.id))),
                    icon: const Icon(Icons.article_outlined),
                    label: Text('${sozlesme.no} · ${sozlesme.baslik}'),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            if (!t.durum.kapali)
              Panel(
                baslik: 'İşlemler',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownMenu<String>(
                    key: const Key('talep-ata'),
                    label: const Text('Atanan'),
                    width: 320,
                    initialSelection: t.atanan.isEmpty ? null : t.atanan,
                    onSelected: (kisi) {
                      if (kisi != null && kisi != t.atanan) kurumsal.talepAta(t, kisi);
                    },
                    dropdownMenuEntries: [
                      for (final kisi in kurumsal.ekip) DropdownMenuEntry(value: kisi, label: kurumsal.kisiAdi(kisi)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final h in sonraki)
                      if (h != TalepDurumu.atandi)
                        (h == TalepDurumu.tamamlandi
                            ? FilledButton(
                                key: Key('talep-durum-${h.name}'),
                                onPressed: () => _gecis(context, t, h),
                                child: Text(h.ad))
                            : OutlinedButton(
                                key: Key('talep-durum-${h.name}'),
                                onPressed: () => _gecis(context, t, h),
                                child: Text(h.ad))),
                  ]),
                ]),
              ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Geçmiş',
              child: Column(children: [
                for (final o in t.gecmis.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.circle, size: 10, color: Renkler.yesil),
                    title: Text(o.aciklama),
                    subtitle: Text('${uzunTarih(o.tarih)} · ${o.kullanici == 'sistem' ? 'Sistem' : kurumsal.kisiAdi(o.kullanici)}'),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
