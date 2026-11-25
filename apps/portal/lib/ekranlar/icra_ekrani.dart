import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'dosyalar_ekrani.dart' show oturumAktoru;

RozetTuru icraRozeti(IcraDurumu d) => switch (d) {
      IcraDurumu.kapandi => RozetTuru.notr,
      IcraDurumu.itirazEdildi => RozetTuru.kritik,
      IcraDurumu.haciz || IcraDurumu.satis => RozetTuru.uyari,
      IcraDurumu.kesinlesti => RozetTuru.onay,
      _ => RozetTuru.devam,
    };

Tarih? tarihCoz(String metin) {
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(metin.trim());
  if (m == null) return null;
  try {
    return Tarih(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  } on ArgumentError {
    return null;
  }
}

class IcraEkrani extends StatelessWidget {
  const IcraEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('icra-yeni'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => IcraTakipFormu(depo: depo, oturum: oturum))),
        icon: const Icon(Icons.add),
        label: const Text('Yeni takip'),
      ),
      body: ListenableBuilder(
        listenable: depo,
        builder: (context, _) {
          final bugun = Tarih.from(DateTime.now());
          final gorunur = depo.gorunurDosyalar(oturumAktoru(oturum)).map((d) => d.id).toSet();
          final liste = depo.icraDosyalari.where((i) => gorunur.contains(i.dosyaId)).toList();
          var toplamKalan = Para.sifir;
          var toplamTahsil = Para.sifir;
          final hesaplar = {
            for (final i in liste) i.id: i.hesap(bugun.isBefore(i.talep.takipTarihi) ? i.talep.takipTarihi : bugun,
                depo.icraFaizTablosu(i.id)),
          };
          for (final h in hesaplar.values) {
            toplamKalan = toplamKalan + h.kalanBorc;
            toplamTahsil = toplamTahsil + h.tahsilEdilen;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Row(children: [
                Expanded(child: Text('İcra takipleri', style: Theme.of(context).textTheme.headlineMedium)),
                if (oturum.lisans.modulAcik(Modul.topluIcra))
                  OutlinedButton.icon(
                    key: const Key('icra-toplu'),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => TopluTakipEkrani(depo: depo, oturum: oturum))),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Toplu takip'),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                DurumRozeti('${liste.where((i) => i.durum != IcraDurumu.kapandi).length} açık takip', RozetTuru.devam),
                DurumRozeti('Kalan alacak ${toplamKalan.bicimli}', RozetTuru.uyari),
                DurumRozeti('Tahsil edilen ${toplamTahsil.bicimli}', RozetTuru.onay),
              ]),
              const SizedBox(height: 16),
              Panel(
                child: liste.isEmpty
                    ? const Text('İcra takibi yok.')
                    : Column(children: [
                        for (final i in liste)
                          ListTile(
                            key: Key('icra-${i.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.gavel_outlined),
                            title: Text(i.borclu, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${i.icraDairesi}${i.esasNo == null ? '' : ' · ${i.esasNo}'} · ${i.talep.tur.ad}\n'
                                'Kalan ${hesaplar[i.id]!.kalanBorc.bicimli} · tahsil ${hesaplar[i.id]!.tahsilEdilen.bicimli}'),
                            isThreeLine: true,
                            trailing: DurumRozeti(i.durum.ad, icraRozeti(i.durum)),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => IcraDetayEkrani(depo: depo, icraId: i.id))),
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

class IcraDetayEkrani extends StatefulWidget {
  const IcraDetayEkrani({super.key, required this.depo, required this.icraId});

  final BellekVeriDeposu depo;
  final String icraId;

  @override
  State<IcraDetayEkrani> createState() => _IcraDetayEkraniState();
}

class _IcraDetayEkraniState extends State<IcraDetayEkrani> {
  late Tarih _hesapTarihi = Tarih.from(DateTime.now());

  Future<void> _tahsilat() =>
      showDialog<void>(context: context, builder: (_) => _TahsilatDiyalogu(depo: widget.depo, icraId: widget.icraId));

  @override
  Widget build(BuildContext context) {
    final depo = widget.depo;
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final i = depo.icraDosyasi(widget.icraId);
        if (i == null) return const Scaffold(body: Center(child: Text('İcra dosyası bulunamadı.')));
        final hesapTarihi = _hesapTarihi.isBefore(i.talep.takipTarihi) ? i.talep.takipTarihi : _hesapTarihi;
        final k = i.hesap(hesapTarihi, depo.icraFaizTablosu(i.id));
        Widget satir(String e, Para p, {bool kalin = false, String? anahtar}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(e, style: kalin ? const TextStyle(fontWeight: FontWeight.w700) : null)),
                Text(p.bicimli,
                    key: anahtar == null ? null : Key(anahtar),
                    style: kalin ? const TextStyle(fontWeight: FontWeight.w700) : null),
              ]),
            );
        return Scaffold(
          appBar: AppBar(title: Text('${i.borclu} · icra')),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('tahsilat-ekle'),
            onPressed: _tahsilat,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Tahsilat'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
            Panel(
              baslik: i.icraDairesi,
              sag: DurumRozeti(i.durum.ad, icraRozeti(i.durum)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i.talep.tur.ad}${i.esasNo == null ? '' : ' · ${i.esasNo}'}'),
                Text('Takip tarihi ${i.talep.takipTarihi.turkceBicim} · temerrüt ${i.talep.temerrutTarihi.turkceBicim} · '
                    '${depo.icraFaizTuru(i.id).ad}'),
                const SizedBox(height: 12),
                DropdownMenu<IcraDurumu>(
                  key: const Key('icra-durum'),
                  label: const Text('Durum'),
                  width: 300,
                  initialSelection: i.durum,
                  onSelected: (d) async {
                    if (d == null) return;
                    final hata = await depo.sunucudaVeyaYerelde(
                      sunucuda: (u) => u.icraDurumu(i.id, d),
                      yerelde: () {
                        depo.icraDurumu(i.id, d);
                        return null;
                      },
                    );
                    if (hata != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
                    }
                  },
                  dropdownMenuEntries: [for (final d in IcraDurumu.values) DropdownMenuEntry(value: d, label: d.ad)],
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Dosya hesabı',
              sag: TextButton.icon(
                key: const Key('hesap-tarihi'),
                onPressed: () async {
                  final secilen = await showDatePicker(
                    context: context,
                    initialDate: DateTime.utc(hesapTarihi.yil, hesapTarihi.ay, hesapTarihi.gun),
                    firstDate: DateTime.utc(i.talep.takipTarihi.yil, i.talep.takipTarihi.ay, i.talep.takipTarihi.gun),
                    lastDate: DateTime(2100),
                  );
                  if (secilen != null) setState(() => _hesapTarihi = Tarih.from(secilen));
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(hesapTarihi.turkceBicim),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                satir('Asıl alacak', k.asilAlacak),
                satir('İşlemiş faiz (takip öncesi)', k.islemisFaiz),
                satir('Takip sonrası faiz', k.takipSonrasiFaiz, anahtar: 'icra-takip-sonrasi-faiz'),
                satir('Masraflar ve harçlar', k.masraflar),
                satir('Vekâlet ücreti', k.vekaletUcreti),
                const Divider(),
                satir('Toplam alacak', k.toplamAlacak, kalin: true),
                satir('Tahsil edilen', k.tahsilEdilen),
                const Divider(),
                satir('Kalan asıl alacak', k.kalanAnapara),
                satir('Kalan faiz', k.kalanFaiz),
                satir('Kalan masraf ve vekâlet ücreti', k.kalanMasraf),
                satir('Kalan borç', k.kalanBorc, kalin: true, anahtar: 'icra-kalan'),
                satir('Tahsil harcı (${k.pesinHarcMahsubu.kurus > 0 ? 'peşin harç mahsup edildi' : i.durum.tahsilAsamasi.ad})',
                    k.tahsilHarci),
                satir('Borçlunun ödemesi gereken', k.borcluyaToplam, kalin: true),
                const SizedBox(height: 8),
                Text('Cezaevi harcı (alacaklıdan): ${k.cezaeviHarci.bicimli}', style: Theme.of(context).textTheme.bodySmall),
                for (final u in k.uyarilar)
                  Text('• $u', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Renkler.uyari)),
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Tahsilatlar ve mahsup',
              child: k.mahsuplar.isEmpty
                  ? const Text('Tahsilat yok.')
                  : Column(children: [
                      for (final m in k.mahsuplar)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${m.tahsilat.tarih.turkceBicim} · ${m.tahsilat.tutar.bicimli}'
                              '${m.tahsilat.aciklama.isEmpty ? '' : ' · ${m.tahsilat.aciklama}'}'),
                          subtitle: Text('Masrafa ${m.masrafa.bicimli} · faize ${m.faize.bicimli} · '
                              'asıl alacağa ${m.anaparaya.bicimli}'
                              '${m.fazla.kurus > 0 ? ' · fazla ${m.fazla.bicimli}' : ''}'),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

class _TahsilatDiyalogu extends StatefulWidget {
  const _TahsilatDiyalogu({required this.depo, required this.icraId});

  final BellekVeriDeposu depo;
  final String icraId;

  @override
  State<_TahsilatDiyalogu> createState() => _TahsilatDiyaloguState();
}

class _TahsilatDiyaloguState extends State<_TahsilatDiyalogu> {
  final _tutar = TextEditingController();
  final _tarih = TextEditingController(text: Tarih.from(DateTime.now()).turkceBicim);
  final _aciklama = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _tutar.dispose();
    _tarih.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tahsilat ekle'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('tahsilat-tutar'),
              controller: _tutar,
              decoration: const InputDecoration(labelText: 'Tutar (TL)')),
          TextField(
              key: const Key('tahsilat-tarih'),
              controller: _tarih,
              decoration: const InputDecoration(labelText: 'Tarih (GG.AA.YYYY)')),
          TextField(
              key: const Key('tahsilat-aciklama'),
              controller: _aciklama,
              decoration: const InputDecoration(labelText: 'Açıklama (ör. maaş haczi)')),
          if (_hata != null) ...[
            const SizedBox(height: 8),
            Text(_hata!, key: const Key('tahsilat-hata'), style: const TextStyle(color: Renkler.kritik)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('tahsilat-kaydet'),
          onPressed: () async {
            final t = tutarCoz(_tutar.text);
            final g = tarihCoz(_tarih.text);
            final aciklama = _aciklama.text.trim();
            final h = t == null || g == null
                ? 'Tutar ve tarihi kontrol edin.'
                : await widget.depo.sunucudaVeyaYerelde(
                    sunucuda: (u) => u.icraTahsilat(widget.icraId, Para.tl(t), g, aciklama),
                    yerelde: () => widget.depo.icraTahsilatEkle(widget.icraId, Para.tl(t), g, aciklama),
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

class IcraTakipFormu extends StatefulWidget {
  const IcraTakipFormu({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<IcraTakipFormu> createState() => _IcraTakipFormuState();
}

class _IcraTakipFormuState extends State<IcraTakipFormu> {
  final _borclu = TextEditingController();
  final _daire = TextEditingController();
  final _alacak = TextEditingController();
  final _temerrut = TextEditingController();
  final _vekalet = TextEditingController();
  String? _dosyaId;
  TakipTuru _tur = TakipTuru.ilamsiz;
  FaizTuru _faiz = FaizTuru.yasal;
  String? _hata;

  @override
  void dispose() {
    for (final c in [_borclu, _daire, _alacak, _temerrut, _vekalet]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dosyalar = widget.depo.gorunurDosyalar(oturumAktoru(widget.oturum));
    final alacak = tutarCoz(_alacak.text);
    final bugun = Tarih.from(DateTime.now());
    final oneri = alacak == null || alacak <= 0
        ? null
        : AvukatlikUcretTarifesi.gecerli(bugun).nispiHesapla(Para.tl(alacak)).$1;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni icra takibi')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownMenu<String>(
              key: const Key('icra-dosya'),
              label: const Text('Bağlı dosya'),
              expandedInsets: EdgeInsets.zero,
              onSelected: (v) => setState(() => _dosyaId = v),
              dropdownMenuEntries: [
                for (final d in dosyalar) DropdownMenuEntry(value: d.id, label: '${d.icNo} · ${d.baslik}'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                key: const Key('icra-borclu'),
                controller: _borclu,
                decoration: const InputDecoration(labelText: 'Borçlu')),
            const SizedBox(height: 12),
            TextField(
                key: const Key('icra-daire'),
                controller: _daire,
                decoration: const InputDecoration(labelText: 'İcra dairesi')),
            const SizedBox(height: 12),
            DropdownMenu<TakipTuru>(
              key: const Key('icra-tur'),
              label: const Text('Takip türü'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _tur,
              onSelected: (t) => setState(() => _tur = t ?? _tur),
              dropdownMenuEntries: [for (final t in TakipTuru.values) DropdownMenuEntry(value: t, label: t.ad)],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('icra-alacak'),
              controller: _alacak,
              decoration: const InputDecoration(labelText: 'Asıl alacak (TL)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
                key: const Key('icra-temerrut'),
                controller: _temerrut,
                decoration: const InputDecoration(labelText: 'Temerrüt tarihi (GG.AA.YYYY)')),
            const SizedBox(height: 12),
            SegmentedButton<FaizTuru>(
              segments: const [
                ButtonSegment(value: FaizTuru.yasal, label: Text('Yasal faiz')),
                ButtonSegment(value: FaizTuru.avans, label: Text('Ticari (avans) faiz')),
              ],
              selected: {_faiz},
              onSelectionChanged: (s) => setState(() => _faiz = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('icra-vekalet'),
              controller: _vekalet,
              decoration: InputDecoration(
                labelText: 'Vekâlet ücreti (TL)',
                helperText: oneri == null ? null : 'AAÜT nispi öneri: ${oneri.bicimli} (taslak tarife, avukat kontrol etmeli)',
              ),
            ),
            if (_hata != null) ...[
              const SizedBox(height: 12),
              Text(_hata!, key: const Key('icra-hata'), style: const TextStyle(color: Renkler.kritik)),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('icra-kaydet'),
                onPressed: () async {
                  final temerrut = tarihCoz(_temerrut.text);
                  final dosyaId = _dosyaId;
                  if (dosyaId == null ||
                      _borclu.text.trim().isEmpty ||
                      _daire.text.trim().isEmpty ||
                      alacak == null ||
                      alacak <= 0 ||
                      temerrut == null) {
                    setState(() => _hata = 'Dosya, borçlu, icra dairesi, alacak ve temerrüt tarihi zorunludur.');
                    return;
                  }
                  if (temerrut.isAfter(bugun)) {
                    setState(() => _hata = 'Temerrüt tarihi bugünden sonra olamaz.');
                    return;
                  }
                  final vekalet = tutarCoz(_vekalet.text);
                  final talep =
                      TakipTalebi(tur: _tur, asilAlacak: Para.tl(alacak), temerrutTarihi: temerrut, takipTarihi: bugun);
                  final vekaletUcreti = vekalet == null ? null : Para.tl(vekalet);
                  final uzak = widget.depo.uzak;
                  String icraId;
                  if (uzak != null) {
                    try {
                      icraId = await uzak.icraEkle(
                        dosyaId: dosyaId,
                        icraDairesi: _daire.text,
                        borclu: _borclu.text,
                        faizTuru: _faiz,
                        vekaletUcreti: vekaletUcreti,
                        talep: talep,
                      );
                    } on Exception catch (e) {
                      if (mounted) setState(() => _hata = '$e');
                      return;
                    }
                  } else {
                    icraId = widget.depo
                        .icraEkle(
                          dosyaId: dosyaId,
                          icraDairesi: _daire.text,
                          borclu: _borclu.text,
                          faizTuru: _faiz,
                          vekaletUcreti: vekaletUcreti,
                          talep: talep,
                        )
                        .id;
                  }
                  if (!mounted) return;
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => IcraDetayEkrani(depo: widget.depo, icraId: icraId)));
                },
                child: const Text('Takibi kaydet'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Excel'den kopyalanan listeyle toplu takip: Borçlu; Kimlik/vergi no; Alacak; Temerrüt tarihi.
class TopluTakipEkrani extends StatefulWidget {
  const TopluTakipEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<TopluTakipEkrani> createState() => _TopluTakipEkraniState();
}

class _TopluTakipEkraniState extends State<TopluTakipEkrani> {
  final _metin = TextEditingController();
  final _daire = TextEditingController();
  String? _muvekkil;
  List<TopluTakipSatiri>? _onizleme;
  String? _hata;

  @override
  void dispose() {
    _metin.dispose();
    _daire.dispose();
    super.dispose();
  }

  void _onizle() {
    final csv = CsvAyristirici.ayristir(_metin.text);
    final satirlar = csv.where((r) => r.any((h) => h.trim().isNotEmpty)).toList();
    if (satirlar.isNotEmpty && satirlar.first.first.toLowerCase().contains('borçlu')) satirlar.removeAt(0);
    setState(() => _onizleme = TopluTakip.dogrula(satirlar, Tarih.from(DateTime.now()),
        kimlikGecerli: (s) => Dogrulayicilar.tcknVeyaVkn(s) == null));
  }

  @override
  Widget build(BuildContext context) {
    final o = _onizleme;
    final gecerli = o?.where((r) => r.gecerli).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Toplu icra takibi')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownMenu<String>(
              key: const Key('toplu-muvekkil'),
              label: const Text('Alacaklı müvekkil'),
              expandedInsets: EdgeInsets.zero,
              onSelected: (v) => setState(() => _muvekkil = v),
              dropdownMenuEntries: [
                for (final k in widget.depo.kisiler) DropdownMenuEntry(value: k.id, label: k.ad),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                key: const Key('toplu-daire'),
                controller: _daire,
                decoration: const InputDecoration(labelText: 'İcra dairesi')),
            const SizedBox(height: 12),
            TextField(
              key: const Key('toplu-metin'),
              controller: _metin,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Excel\'den yapıştırın: Borçlu; Kimlik/vergi no; Alacak; Temerrüt tarihi',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(key: const Key('toplu-onizle'), onPressed: _onizle, child: const Text('Önizle')),
            ),
          ]),
        ),
        if (o != null) ...[
          const SizedBox(height: 20),
          Panel(
            baslik: '$gecerli / ${o.length} satır takibe hazır',
            child: Column(children: [
              for (final r in o)
                ListTile(
                  key: Key('toplu-satir-${r.satir}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.gecerli ? Icons.check_circle_outline : Icons.error_outline,
                      color: r.gecerli ? Renkler.yesil : Renkler.kritik),
                  title: Text('${r.satir}. ${r.borclu.isEmpty ? '(adsız)' : r.borclu}'),
                  subtitle: Text(r.gecerli
                      ? '${r.alacak!.bicimli} · temerrüt ${r.temerrut!.turkceBicim}'
                      : r.hatalar.join(' ')),
                ),
              if (_hata != null) Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('toplu-ac'),
                  onPressed: gecerli == 0
                      ? null
                      : () {
                          final m = _muvekkil;
                          if (m == null || _daire.text.trim().isEmpty) {
                            setState(() => _hata = 'Müvekkil ve icra dairesini seçin.');
                            return;
                          }
                          if (widget.depo.uzak != null) {
                            setState(() => _hata = 'Toplu takip sunucu bağlantısında henüz desteklenmiyor; '
                                'takipleri tek tek açın.');
                            return;
                          }
                          final n = widget.depo.topluTakipAc(
                            satirlar: o,
                            muvekkilId: m,
                            icraDairesi: _daire.text,
                            tur: TakipTuru.ilamsiz,
                            takipTarihi: Tarih.from(DateTime.now()),
                            sorumlu: widget.oturum.kullaniciId,
                          );
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$n takip açıldı. Hatalı satırlar atlandı.')));
                          Navigator.of(context).pop();
                        },
                  child: Text('$gecerli takibi aç'),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
