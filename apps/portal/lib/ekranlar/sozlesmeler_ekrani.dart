import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kurumsal_depo.dart';
import '../servisler/ornek_sozlesmeler.dart';
import '../tema/tema.dart';

RozetTuru riskRozeti(SozlesmeRiski s) => switch (s) {
      SozlesmeRiski.yuksek => RozetTuru.kritik,
      SozlesmeRiski.orta => RozetTuru.uyari,
      SozlesmeRiski.dusuk => RozetTuru.onay,
    };

RozetTuru sozlesmeDurumRozeti(SozlesmeDurumu d) => switch (d) {
      SozlesmeDurumu.yururlukte => RozetTuru.onay,
      SozlesmeDurumu.onayda || SozlesmeDurumu.imzada => RozetTuru.uyari,
      SozlesmeDurumu.taslak || SozlesmeDurumu.muzakere => RozetTuru.devam,
      SozlesmeDurumu.sonaErdi || SozlesmeDurumu.feshedildi => RozetTuru.notr,
    };

enum _Filtre {
  tumu('Tümü'),
  hazirlik('Taslak / müzakere'),
  onay('Onay / imza'),
  yururlukte('Yürürlükte'),
  bitti('Sona eren');

  const _Filtre(this.ad);
  final String ad;

  bool uyar(SozlesmeDurumu d) => switch (this) {
        tumu => true,
        hazirlik => d == SozlesmeDurumu.taslak || d == SozlesmeDurumu.muzakere,
        onay => d == SozlesmeDurumu.onayda || d == SozlesmeDurumu.imzada,
        yururlukte => d == SozlesmeDurumu.yururlukte,
        bitti => d == SozlesmeDurumu.sonaErdi || d == SozlesmeDurumu.feshedildi,
      };
}

class SozlesmelerEkrani extends StatefulWidget {
  const SozlesmelerEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  State<SozlesmelerEkrani> createState() => _SozlesmelerEkraniState();
}

class _SozlesmelerEkraniState extends State<SozlesmelerEkrani> {
  _Filtre _filtre = _Filtre.tumu;
  String _arama = '';

  void _ac(Sozlesme s) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => SozlesmeDetayEkrani(kurumsal: widget.kurumsal, sozlesmeId: s.id)));

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sozlesme-yukle'),
        onPressed: () async {
          final s = await Navigator.of(context)
              .push<Sozlesme>(MaterialPageRoute(builder: (_) => SozlesmeYuklemeEkrani(kurumsal: k)));
          if (s != null && mounted) _ac(s);
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Sözleşme yükle'),
      ),
      body: ListenableBuilder(
        listenable: k,
        builder: (context, _) {
          final uyarilar = k.uyarilar();
          final arama = _arama.trim().toLowerCase();
          final liste = k.gorunurSozlesmeler
              .where((s) => _filtre.uyar(s.durum))
              .where((s) =>
                  arama.isEmpty ||
                  '${s.no} ${s.baslik} ${s.karsiTaraf} ${s.birim}'.toLowerCase().contains(arama))
              .toList();
          final yuksek = k.gorunurSozlesmeler.where((s) => s.tarama?.genelSeviye == SozlesmeRiski.yuksek).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Text('Sözleşmeler', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                _Kpi('Yürürlükte', '${k.gorunurSozlesmeler.where((s) => s.durum == SozlesmeDurumu.yururlukte).length}'),
                _Kpi('Onay / imza bekleyen',
                    '${k.gorunurSozlesmeler.where((s) => _Filtre.onay.uyar(s.durum)).length}'),
                _Kpi('Onayınızı bekleyen', '${k.onayimiBekleyenler.length}', vurgu: k.onayimiBekleyenler.isNotEmpty),
                _Kpi('60 gün içinde dikkat', '${uyarilar.length}', vurgu: uyarilar.isNotEmpty),
                _Kpi('Yüksek riskli', '$yuksek', vurgu: yuksek > 0),
              ]),
              if (uyarilar.isNotEmpty) ...[
                const SizedBox(height: 20),
                Panel(
                  baslik: 'Yaklaşan tarihler',
                  child: Column(children: [
                    for (final (s, u) in uyarilar)
                      ListTile(
                        key: Key('sozlesme-uyari-${s.id}-${u.tur.name}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          u.tur == SozlesmeUyariTuru.ihbarKacti || u.tur == SozlesmeUyariTuru.yukumlulukGecikti
                              ? Icons.error_outline
                              : Icons.event_note_outlined,
                          color: u.tur == SozlesmeUyariTuru.ihbarKacti || u.tur == SozlesmeUyariTuru.yukumlulukGecikti
                              ? Renkler.kritik
                              : Renkler.uyari,
                        ),
                        title: Text(u.mesaj),
                        subtitle: Text('${s.no} · ${s.baslik}'),
                        trailing: Text(kalanMetni(k.bugunTarih.farkGun(u.tarih))),
                        onTap: () => _ac(s),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('sozlesme-ara'),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search), hintText: 'No, başlık, karşı taraf veya birim ara'),
                      onChanged: (v) => setState(() => _arama = v),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in _Filtre.values)
                        ChoiceChip(
                          key: Key('sozlesme-filtre-${f.name}'),
                          label: Text(f.ad),
                          selected: _filtre == f,
                          onSelected: (_) => setState(() => _filtre = f),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    if (liste.isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('Sözleşme bulunamadı.'))
                    else
                      for (final s in liste) _SozlesmeSatiri(s, k, () => _ac(s)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.etiket, this.deger, {this.vurgu = false});

  final String etiket;
  final String deger;
  final bool vurgu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Panel(
        dolgu: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiket, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(deger,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: vurgu ? Renkler.uyari : Renkler.metin)),
        ]),
      ),
    );
  }
}

class _SozlesmeSatiri extends StatelessWidget {
  const _SozlesmeSatiri(this.s, this.k, this.ac);

  final Sozlesme s;
  final KurumsalDepo k;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final t = s.tarama;
    return InkWell(
      key: Key('sozlesme-${s.id}'),
      onTap: ac,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renkler.kenar))),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${s.no} · ${k.sirketAdi(s.sirketId)} ↔ ${s.karsiTaraf}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Expanded(flex: 2, child: Text(s.tur.ad, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
            flex: 2,
            child: Text(s.bitis == null ? 'Bitiş yok' : 'Bitiş ${kisaTarih(s.bitis!)} ${s.bitis!.yil}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          if (t != null) ...[
            DurumRozeti('Risk ${t.genelSeviye.ad.toLowerCase()}', riskRozeti(t.genelSeviye)),
            const SizedBox(width: 8),
          ],
          DurumRozeti(s.durum.ad, sozlesmeDurumRozeti(s.durum)),
        ]),
      ),
    );
  }
}

/// Sözleşme metni yapıştırılır veya örnek seçilir, taranır, sonuç gözden geçirilip kaydedilir.
/// PDF/Word yükleme ve OCR, Türkiye'deki belge servisi bağlanınca bu ekrana eklenecek.
class SozlesmeYuklemeEkrani extends StatefulWidget {
  const SozlesmeYuklemeEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  State<SozlesmeYuklemeEkrani> createState() => _SozlesmeYuklemeEkraniState();
}

class _SozlesmeYuklemeEkraniState extends State<SozlesmeYuklemeEkrani> {
  final _baslik = TextEditingController();
  final _karsi = TextEditingController();
  final _birim = TextEditingController();
  final _metin = TextEditingController();
  TaramaSonucu? _sonuc;
  String? _hata;

  @override
  void dispose() {
    for (final c in [_baslik, _karsi, _birim, _metin]) {
      c.dispose();
    }
    super.dispose();
  }

  void _tara() {
    if (_metin.text.trim().length < 40) {
      setState(() => _hata = 'Taramak için sözleşme metnini yapıştırın.');
      return;
    }
    final s = widget.kurumsal.tara(_metin.text);
    setState(() {
      _hata = null;
      _sonuc = s;
      if (_karsi.text.trim().isEmpty && s.taraflar.length > 1) _karsi.text = s.taraflar.last;
    });
  }

  Future<void> _kaydet() async {
    if (_baslik.text.trim().isEmpty) {
      setState(() => _hata = 'Sözleşme başlığını yazın.');
      return;
    }
    final k = widget.kurumsal;
    final uzak = k.uzak;
    Sozlesme? s;
    if (uzak != null) {
      try {
        final id = await uzak.sozlesmeEkle(
            baslik: _baslik.text, karsiTaraf: _karsi.text, birim: _birim.text, metin: _metin.text, sirketId: k.aktifSirketId);
        s = k.sozlesme(id);
      } on Exception catch (e) {
        if (mounted) setState(() => _hata = '$e');
        return;
      }
    } else {
      s = k.sozlesmeYukle(baslik: _baslik.text, karsiTaraf: _karsi.text, birim: _birim.text, metin: _metin.text);
    }
    if (mounted) Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuc;
    return Scaffold(
      appBar: AppBar(title: const Text('Sözleşme yükle')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Panel(
            baslik: 'Sözleşme bilgileri',
            child: Column(children: [
              TextField(
                  key: const Key('sozlesme-baslik'),
                  controller: _baslik,
                  decoration: const InputDecoration(labelText: 'Başlık')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('sozlesme-karsi'),
                  controller: _karsi,
                  decoration: const InputDecoration(labelText: 'Karşı taraf')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('sozlesme-birim'),
                  controller: _birim,
                  decoration: const InputDecoration(labelText: 'İlgili birim')),
            ]),
          ),
          const SizedBox(height: 20),
          Panel(
            baslik: 'Sözleşme metni',
            sag: PopupMenuButton<String>(
              key: const Key('ornek-metin'),
              tooltip: 'Örnek metin',
              onSelected: (m) => setState(() {
                _metin.text = m;
                _sonuc = null;
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: ornekHizmetSozlesmesi, child: Text('Örnek hizmet sözleşmesi')),
                PopupMenuItem(value: ornekKiraSozlesmesi, child: Text('Örnek kira sözleşmesi')),
                PopupMenuItem(value: ornekGizlilikSozlesmesi, child: Text('Örnek gizlilik sözleşmesi')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.description_outlined, size: 18, color: Renkler.yesil),
                  SizedBox(width: 4),
                  Text('Örnek metin', style: TextStyle(color: Renkler.yesil, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const Key('sozlesme-metin'),
                controller: _metin,
                minLines: 8,
                maxLines: 16,
                decoration: const InputDecoration(
                    hintText: 'Sözleşme metnini buraya yapıştırın. Metin yalnızca Türkiye\'deki sunucularda işlenir.'),
              ),
              if (_hata != null) ...[
                const SizedBox(height: 8),
                Text(_hata!, key: const Key('sozlesme-hata'), style: const TextStyle(color: Renkler.kritik)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                OutlinedButton.icon(
                    key: const Key('sozlesme-tara'),
                    onPressed: _tara,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Tara')),
                FilledButton.icon(
                    key: const Key('sozlesme-kaydet'),
                    onPressed: s == null ? null : _kaydet,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Kaydet')),
              ]),
            ]),
          ),
          if (s != null) ...[
            const SizedBox(height: 20),
            TaramaRaporu(sonuc: s),
          ],
        ],
      ),
    );
  }
}

/// Tarama sonucunun özeti ve bulguları.
class TaramaRaporu extends StatelessWidget {
  const TaramaRaporu({super.key, required this.sonuc});

  final TaramaSonucu sonuc;

  @override
  Widget build(BuildContext context) {
    final t = sonuc;
    String tarih(Tarih? d) => d == null ? 'Bulunamadı' : d.turkceBicim;
    final alanlar = <(String, String)>[
      ('Tür', t.tur?.ad ?? 'Belirlenemedi'),
      ('Taraflar', t.taraflar.isEmpty ? 'Bulunamadı' : t.taraflar.join('\n')),
      ('Başlangıç', tarih(t.baslangic)),
      ('Bitiş', t.bitis != null ? tarih(t.bitis) : t.sureAy != null ? '${t.sureAy} ay süreli' : 'Bulunamadı'),
      ('Otomatik yenileme', t.otomatikYenileme ? 'Var' : 'Yok'),
      ('İhbar süresi', t.ihbarSuresiGun == null ? 'Bulunamadı' : '${t.ihbarSuresiGun} gün'),
      ('Bedel', t.bedel?.bicimli ?? 'Bulunamadı'),
      ('Ödeme vadesi', t.odemeVadesiGun == null ? 'Bulunamadı' : '${t.odemeVadesiGun} gün'),
      ('Uygulanacak hukuk', t.uygulanacakHukuk ?? 'Belirtilmemiş'),
      ('Uyuşmazlık çözümü', t.tahkim ? 'Tahkim' : t.yetkiliYer == null ? 'Belirtilmemiş' : '${t.yetkiliYer} mahkemeleri'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        baslik: 'Tarama sonucu',
        sag: DurumRozeti('Risk ${t.genelSeviye.ad.toLowerCase()} · ${t.riskPuani}/100', riskRozeti(t.genelSeviye)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (e, d) in alanlar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 170, child: Text(e, style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: Text(d)),
              ]),
            ),
          const SizedBox(height: 8),
          Text(TaramaSonucu.uyari, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        ]),
      ),
      const SizedBox(height: 20),
      Panel(
        baslik: 'Riskler ve eksik maddeler (${t.bulgular.length})',
        child: t.bulgular.isEmpty
            ? const Text('Dikkat gerektiren madde bulunamadı.')
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final b in t.bulgular)
                  Container(
                    key: Key('bulgu-${b.kod}'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renkler.kenar))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        DurumRozeti(b.seviye.ad, riskRozeti(b.seviye)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(b.baslik, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                      const SizedBox(height: 6),
                      Text(b.aciklama),
                      if (b.alinti.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Renkler.krem,
                            border: const Border(left: BorderSide(color: Renkler.altin, width: 3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('“${b.alinti}”', style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class SozlesmeDetayEkrani extends StatelessWidget {
  const SozlesmeDetayEkrani({super.key, required this.kurumsal, required this.sozlesmeId});

  final KurumsalDepo kurumsal;
  final String sozlesmeId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kurumsal,
      builder: (context, _) {
        final s = kurumsal.sozlesme(sozlesmeId);
        if (s == null) return const Scaffold(body: Center(child: Text('Sözleşme bulunamadı.')));
        final metin = kurumsal.metin(s.id);
        // Onay ve imzaya geçiş yalnızca onay zinciriyle olur.
        final sonraki = s.durum == SozlesmeDurumu.onayda
            ? <SozlesmeDurumu>{}
            : SozlesmeDurumu.gecisler[s.durum]!.where((h) => h != SozlesmeDurumu.onayda).toSet();
        final onaySureci = kurumsal.onaySureci(s.id);
        void mesaj(String? h) {
          if (h != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.baslik),
              bottom: const TabBar(tabs: [Tab(text: 'Özet'), Tab(text: 'Tarama'), Tab(text: 'Metin')]),
            ),
            body: TabBarView(children: [
              ListView(padding: const EdgeInsets.all(24), children: [
                Panel(
                  baslik: s.no,
                  sag: DurumRozeti(s.durum.ad, sozlesmeDurumRozeti(s.durum)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Bilgi('Karşı taraf', s.karsiTaraf.isEmpty ? '—' : s.karsiTaraf),
                    _Bilgi('Tür', s.tur.ad),
                    _Bilgi('Grup şirketi', kurumsal.sirketAdi(s.sirketId)),
                    _Bilgi('Birim', s.birim.isEmpty ? '—' : s.birim),
                    _Bilgi('Sorumlu', kurumsal.kisiAdi(s.sorumlu)),
                    _Bilgi('Başlangıç', s.baslangic == null ? '—' : uzunTarih(s.baslangic!)),
                    _Bilgi('Bitiş', s.bitis == null ? '—' : uzunTarih(s.bitis!)),
                    _Bilgi('Yenileme', s.otomatikYenileme ? 'Otomatik, ${s.yenilemeSuresiAy} ay' : 'Yok'),
                    _Bilgi('İhbar son günü', s.ihbarSonGunu == null ? '—' : uzunTarih(s.ihbarSonGunu!),
                        anahtar: 'ihbar-son-gunu'),
                    _Bilgi('Bedel', s.bedel?.bicimli ?? '—'),
                    if (sonraki.isNotEmpty || s.durum == SozlesmeDurumu.taslak || s.durum == SozlesmeDurumu.muzakere) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (s.durum == SozlesmeDurumu.taslak || s.durum == SozlesmeDurumu.muzakere)
                          FilledButton.icon(
                            key: const Key('sozlesme-onaya-gonder'),
                            onPressed: () async => mesaj(await kurumsal.sunucudaVeyaYerelde(
                                sunucuda: (u) => u.sozlesmeDurumu(s.id, SozlesmeDurumu.onayda),
                                yerelde: () => kurumsal.onayaGonder(s))),
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: Text('Onaya gönder (${kurumsal.onayPolitikasi.adimlar(s).map((a) => a.ad).join(' → ')})'),
                          ),
                        for (final h in sonraki)
                          OutlinedButton(
                            key: Key('sozlesme-durum-${h.name}'),
                            onPressed: () async => mesaj(await kurumsal.sunucudaVeyaYerelde(
                                  sunucuda: (u) => u.sozlesmeDurumu(s.id, h, baslangic: s.baslangic),
                                  yerelde: () {
                                    kurumsal.sozlesmeDurumu(s, h);
                                    return null;
                                  },
                                )),
                            child: Text('${h.ad} yap'),
                          ),
                      ]),
                    ],
                  ]),
                ),
                if (onaySureci != null) ...[
                  const SizedBox(height: 20),
                  OnayZinciriPaneli(kurumsal: kurumsal, sozlesme: s, surec: onaySureci),
                ],
                const SizedBox(height: 20),
                Panel(
                  baslik: 'Yükümlülükler',
                  sag: TextButton.icon(
                    key: const Key('yukumluluk-ekle'),
                    onPressed: () => showDialog<void>(
                        context: context, builder: (_) => _YukumlulukDiyalogu(kurumsal: kurumsal, sozlesme: s)),
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  ),
                  child: s.yukumlulukler.isEmpty
                      ? const Text('Takip edilen yükümlülük yok.')
                      : Column(children: [
                          for (final y in s.yukumlulukler)
                            CheckboxListTile(
                              key: Key('yukumluluk-${y.id}'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: y.tamamlandi,
                              onChanged: y.tamamlandi ? null : (_) => kurumsal.yukumlulukTamamla(s, y),
                              title: Text(y.aciklama),
                              subtitle: Text('${y.taraf == YukumlulukTarafi.biz ? 'Bizim' : 'Karşı tarafın'} yükümlülüğü · '
                                  'son gün ${uzunTarih(y.sonTarih)}'),
                            ),
                        ]),
                ),
              ]),
              ListView(padding: const EdgeInsets.all(24), children: [
                if (s.tarama == null)
                  const Panel(child: Text('Bu sözleşme için metin yüklenmedi; tarama yapılmadı.'))
                else
                  TaramaRaporu(sonuc: s.tarama!),
              ]),
              ListView(padding: const EdgeInsets.all(24), children: [
                Panel(child: SelectableText(metin ?? 'Metin yok.')),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _Bilgi extends StatelessWidget {
  const _Bilgi(this.etiket, this.deger, {this.anahtar});

  final String etiket;
  final String deger;
  final String? anahtar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(etiket, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(deger, key: anahtar == null ? null : Key(anahtar!))),
        ]),
      );
}

class _YukumlulukDiyalogu extends StatefulWidget {
  const _YukumlulukDiyalogu({required this.kurumsal, required this.sozlesme});

  final KurumsalDepo kurumsal;
  final Sozlesme sozlesme;

  @override
  State<_YukumlulukDiyalogu> createState() => _YukumlulukDiyaloguState();
}

class _YukumlulukDiyaloguState extends State<_YukumlulukDiyalogu> {
  final _aciklama = TextEditingController();
  YukumlulukTarafi _taraf = YukumlulukTarafi.biz;
  late Tarih _tarih = widget.kurumsal.bugunTarih.gunEkle(30);

  @override
  void dispose() {
    _aciklama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yükümlülük ekle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
              key: const Key('yukumluluk-aciklama'),
              controller: _aciklama,
              decoration: const InputDecoration(labelText: 'Yükümlülük (ör. teminat mektubu teslimi)')),
          const SizedBox(height: 12),
          SegmentedButton<YukumlulukTarafi>(
            segments: const [
              ButtonSegment(value: YukumlulukTarafi.biz, label: Text('Bizim')),
              ButtonSegment(value: YukumlulukTarafi.karsiTaraf, label: Text('Karşı taraf')),
            ],
            selected: {_taraf},
            onSelectionChanged: (s) => setState(() => _taraf = s.first),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final secilen = await showDatePicker(
                context: context,
                initialDate: DateTime.utc(_tarih.yil, _tarih.ay, _tarih.gun),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (secilen != null) setState(() => _tarih = Tarih.from(secilen));
            },
            icon: const Icon(Icons.event),
            label: Text('Son gün: ${uzunTarih(_tarih)}'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('yukumluluk-kaydet'),
          onPressed: () {
            if (_aciklama.text.trim().isEmpty) return;
            widget.kurumsal.yukumlulukEkle(widget.sozlesme, _aciklama.text, _taraf, _tarih);
            Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class OnayZinciriPaneli extends StatelessWidget {
  const OnayZinciriPaneli({super.key, required this.kurumsal, required this.sozlesme, required this.surec});

  final KurumsalDepo kurumsal;
  final Sozlesme sozlesme;
  final OnaySureci surec;

  Future<void> _gerekceli(BuildContext context, OnayKarariTuru tur) async {
    final g = await MetinGirisDiyalogu.goster(
      context,
      MetinGirisDiyalogu(
        baslik: tur == OnayKarariTuru.ret ? 'Sözleşmeyi reddet' : 'Revizyon iste',
        etiket: 'Gerekçe',
        alanAnahtari: const Key('onay-gerekce'),
        onayAnahtari: const Key('onay-gerekce-kaydet'),
      ),
    );
    if (g == null || !context.mounted) return;
    final h = await kurumsal.sunucudaVeyaYerelde(
      sunucuda: (u) => u.onayKarari(sozlesme.id, tur, not: g),
      yerelde: () => kurumsal.onayKarari(sozlesme, tur, not: g),
    );
    if (h != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
  }

  @override
  Widget build(BuildContext context) {
    final siradaki = surec.siradaki;
    final kararlar = {for (final k in surec.kararlar) k.adimKodu: k};
    return Panel(
      baslik: 'Onay zinciri',
      sag: DurumRozeti(surec.durum.ad, switch (surec.durum) {
        OnaySurecDurumu.onaylandi => RozetTuru.onay,
        OnaySurecDurumu.devam => RozetTuru.uyari,
        _ => RozetTuru.kritik,
      }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < surec.adimlar.length; i++)
          () {
            final a = surec.adimlar[i];
            final k = kararlar[a.kod];
            final sirada = siradaki?.kod == a.kod;
            return ListTile(
              key: Key('onay-adim-${a.kod}'),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: k?.tur == OnayKarariTuru.onay
                    ? Renkler.yesil
                    : k != null
                        ? Renkler.kritik
                        : sirada
                            ? Renkler.uyari
                            : Renkler.kenar,
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text(a.ad),
              subtitle: Text(k != null
                  ? '${k.tur.ad} · ${kurumsal.kisiAdi(k.kullanici)} · ${tarihSaat(k.zaman)}${k.not.isEmpty ? '' : ' · ${k.not}'}'
                  : '${a.neden} · onaycı: ${a.onaycilar.map(kurumsal.kisiAdi).join(', ')}'),
            );
          }(),
        if (siradaki != null && surec.onaylayabilir(kurumsal.kullaniciId)) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              key: const Key('onay-onayla'),
              onPressed: () async {
                final h = await kurumsal.sunucudaVeyaYerelde(
                  sunucuda: (u) => u.onayKarari(sozlesme.id, OnayKarariTuru.onay),
                  yerelde: () => kurumsal.onayKarari(sozlesme, OnayKarariTuru.onay),
                );
                if (h != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
              },
              icon: const Icon(Icons.check, size: 18),
              label: Text('${siradaki.ad} olarak onayla'),
            ),
            OutlinedButton(
              key: const Key('onay-revizyon'),
              onPressed: () => _gerekceli(context, OnayKarariTuru.revizyon),
              child: const Text('Revizyon iste'),
            ),
            OutlinedButton(
              key: const Key('onay-reddet'),
              onPressed: () => _gerekceli(context, OnayKarariTuru.ret),
              child: const Text('Reddet'),
            ),
          ]),
        ] else if (siradaki != null)
          Text('Sıradaki onay: ${siradaki.ad} (${siradaki.onaycilar.map(kurumsal.kisiAdi).join(', ')})',
              key: const Key('onay-bekleniyor'), style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
