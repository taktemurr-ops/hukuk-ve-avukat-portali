import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/cikar_raporu.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';

/// Müvekkil ve taraf listesi; Türkçeye duyarlı arama.
class MuvekkillerEkrani extends StatefulWidget {
  const MuvekkillerEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<MuvekkillerEkrani> createState() => _MuvekkillerEkraniState();
}

class _MuvekkillerEkraniState extends State<MuvekkillerEkrani> {
  String _sorgu = '';

  Future<void> _yeniKisi() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => KisiFormuEkrani(depo: widget.depo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('yeni-kisi'),
        onPressed: _yeniKisi,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Yeni kişi'),
      ),
      body: ListenableBuilder(
        listenable: widget.depo,
        builder: (context, _) {
          final liste = widget.depo.ara(_sorgu);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                key: const Key('kisi-ara'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Ad, unvan veya TCKN/VKN ile ara',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _sorgu = v),
              ),
              const SizedBox(height: 12),
              Text('${liste.length} kayıt', style: Theme.of(context).textTheme.labelMedium),
              for (final k in liste)
                Card(
                  child: ListTile(
                    key: Key('kisi-${k.id}'),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => KisiKartiEkrani(depo: widget.depo, kisiId: k.id))),
                    trailing: const Icon(Icons.chevron_right),
                    leading: Icon(k.tur == KisiTuru.gercek ? Icons.person_outline : Icons.business_outlined),
                    title: Text(k.ad),
                    subtitle: Text([
                      if (k.kimlikNo != null) '${k.tur == KisiTuru.gercek ? 'TCKN' : 'VKN'}: ${k.kimlikNo}',
                      '${widget.depo.dosyaSayisi(k.id)} dosya',
                      if (k.unvanGecmisi.isNotEmpty) 'eski unvan: ${k.unvanGecmisi.last.unvan}',
                    ].join(' · ')),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Yeni kişi kaydı. Kaydetmeden önce mükerrer kayıt ve çıkar çatışması kontrol edilir.
class KisiFormuEkrani extends StatefulWidget {
  const KisiFormuEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<KisiFormuEkrani> createState() => _KisiFormuEkraniState();
}

class _KisiFormuEkraniState extends State<KisiFormuEkrani> {
  final _form = GlobalKey<FormState>();
  final _ad = TextEditingController();
  final _kimlikNo = TextEditingController();
  final _eposta = TextEditingController();
  final _telefon = TextEditingController();
  KisiTuru _tur = KisiTuru.gercek;
  TarafSifati _sifat = TarafSifati.muvekkil;

  List<MukerrerAdayi>? _mukerrerler;
  CikarCatismasiRaporu? _rapor;

  @override
  void dispose() {
    _ad.dispose();
    _kimlikNo.dispose();
    _eposta.dispose();
    _telefon.dispose();
    super.dispose();
  }

  void _sifirla() {
    if (_mukerrerler != null || _rapor != null) {
      setState(() {
        _mukerrerler = null;
        _rapor = null;
      });
    }
  }

  String? _kimlikDogrula(String? d) {
    final v = d?.trim() ?? '';
    if (v.isEmpty) return null;
    if (_tur == KisiTuru.gercek) return Dogrulayicilar.tcknGecerli(v) ? null : 'TC kimlik numarası geçersiz.';
    return Dogrulayicilar.vknGecerli(v) ? null : 'Vergi kimlik numarası geçersiz.';
  }

  bool get _kesinMukerrer => _mukerrerler?.any((m) => m.tur == MukerrerTuru.kesin) ?? false;

  void _kontrolEt() {
    if (!_form.currentState!.validate()) return;
    final no = _kimlikNo.text.trim().isEmpty ? null : _kimlikNo.text.trim();
    setState(() {
      _mukerrerler = MukerrerKontrol.bul(widget.depo.kisiler, ad: _ad.text, kimlikNo: no);
      _rapor = _sifat == TarafSifati.diger
          ? const CikarCatismasiRaporu([])
          : widget.depo.tarayici.tara([AdayTaraf(ad: _ad.text.trim(), sifat: _sifat, kimlikNo: no)]);
    });
  }

  Future<void> _kaydet() async {
    final hata = await widget.depo.sunucudaVeyaYerelde(
      sunucuda: (u) =>
          u.kisiEkle(tur: _tur, ad: _ad.text, kimlikNo: _kimlikNo.text, eposta: _eposta.text, telefon: _telefon.text),
      yerelde: () {
        widget.depo.kisiEkle(
          tur: _tur,
          ad: _ad.text,
          kimlikNo: _kimlikNo.text,
          eposta: _eposta.text,
          telefon: _telefon.text,
        );
        return null;
      },
    );
    if (!mounted) return;
    if (hata != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kontrolEdildi = _mukerrerler != null && _rapor != null;
    final rapor = _rapor;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni kişi')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<KisiTuru>(
              segments: const [
                ButtonSegment(value: KisiTuru.gercek, label: Text('Gerçek kişi'), icon: Icon(Icons.person_outline)),
                ButtonSegment(value: KisiTuru.tuzel, label: Text('Tüzel kişi'), icon: Icon(Icons.business_outlined)),
              ],
              selected: {_tur},
              onSelectionChanged: (s) {
                setState(() => _tur = s.first);
                _sifirla();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('kisi-ad'),
              controller: _ad,
              decoration: InputDecoration(labelText: _tur == KisiTuru.gercek ? 'Ad soyad' : 'Unvan'),
              validator: (d) => Dogrulayicilar.zorunlu(d, alan: 'Ad'),
              onChanged: (_) => _sifirla(),
            ),
            TextFormField(
              key: const Key('kisi-kimlik'),
              controller: _kimlikNo,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _tur == KisiTuru.gercek ? 'TC kimlik no' : 'Vergi kimlik no'),
              validator: _kimlikDogrula,
              onChanged: (_) => _sifirla(),
            ),
            TextFormField(
              controller: _eposta,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (d) => (d == null || d.trim().isEmpty) ? null : Dogrulayicilar.eposta(d),
            ),
            TextFormField(
              controller: _telefon,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon'),
            ),
            const SizedBox(height: 16),
            Text('Bu kişi hangi sıfatla ekleniyor?', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<TarafSifati>(
              segments: const [
                ButtonSegment(value: TarafSifati.muvekkil, label: Text('Müvekkil')),
                ButtonSegment(value: TarafSifati.karsiTaraf, label: Text('Karşı taraf')),
                ButtonSegment(value: TarafSifati.diger, label: Text('Diğer')),
              ],
              selected: {_sifat},
              onSelectionChanged: (s) {
                setState(() => _sifat = s.first);
                _sifirla();
              },
            ),
            const SizedBox(height: 16),
            if (!kontrolEdildi)
              FilledButton.icon(
                key: const Key('kisi-kontrol'),
                onPressed: _kontrolEt,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Mükerrer ve çıkar çatışması kontrolü'),
              ),
            if (kontrolEdildi) ...[
              if (_mukerrerler!.isNotEmpty) ...[
                Text('Olası mükerrer kayıtlar', style: Theme.of(context).textTheme.titleSmall),
                for (final m in _mukerrerler!)
                  ListTile(
                    leading: Icon(
                      m.tur == MukerrerTuru.kesin ? Icons.block : Icons.content_copy,
                      color: m.tur == MukerrerTuru.kesin ? Theme.of(context).colorScheme.error : null,
                    ),
                    title: Text(m.kisi.ad),
                    subtitle: Text(m.tur == MukerrerTuru.kesin
                        ? 'Aynı kimlik numarası kayıtlı; yeni kayıt açılamaz.'
                        : 'Benzerlik %${(m.benzerlik * 100).round()}'),
                  ),
                const SizedBox(height: 8),
              ],
              if (rapor != null && _sifat != TarafSifati.diger) ...[
                Text('Çıkar çatışması', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                CikarRaporuGorunumu(rapor: rapor),
                if (rapor.kararGerekir)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Uyarı içeren kayıt için "Çıkar çatışması" ekranından gerekçeli karar verilmelidir.',
                      key: const Key('kisi-karar-gerekir'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('kisi-kaydet'),
                onPressed: _kesinMukerrer || (rapor?.kararGerekir ?? false) ? null : _kaydet,
                child: const Text('Kaydet'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _iliskiAdlari = {
  IliskiTuru.ortak: 'Ortak',
  IliskiTuru.istirak: 'İştirak',
  IliskiTuru.yetkili: 'Yetkili / temsilci',
  IliskiTuru.calisan: 'Çalışan',
  IliskiTuru.akraba: 'Akraba',
  IliskiTuru.vekil: 'Vekil',
  IliskiTuru.grupSirketi: 'Grup şirketi',
};

const _tercihAdlari = {
  IletisimTercihi.eposta: 'E-posta',
  IletisimTercihi.telefon: 'Telefon',
  IletisimTercihi.sms: 'SMS',
  IletisimTercihi.portal: 'Müvekkil portalı',
};

const _sifatAdlari = {TarafSifati.muvekkil: 'müvekkil', TarafSifati.karsiTaraf: 'karşı taraf', TarafSifati.diger: 'diğer'};

/// Kişi kartı: bilgiler (düzenlenebilir), unvan geçmişi, ilişkiler ve yer aldığı dosyalar. İlişkiler ve eski
/// unvanlar çıkar çatışması taramasında kullanılır.
class KisiKartiEkrani extends StatefulWidget {
  const KisiKartiEkrani({super.key, required this.depo, required this.kisiId});

  final BellekVeriDeposu depo;
  final String kisiId;

  @override
  State<KisiKartiEkrani> createState() => _KisiKartiEkraniState();
}

class _KisiKartiEkraniState extends State<KisiKartiEkrani> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final a in ['ad', 'kimlikNo', 'mersisNo', 'eposta', 'telefon', 'adres', 'notlar']) a: TextEditingController()};
  IletisimTercihi _tercih = IletisimTercihi.eposta;
  bool _duzenle = false;
  bool _bekliyor = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _mesaj(String? hata, String basari) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata ?? basari)));

  void _duzenlemeyeBasla(Kisi k) {
    _c['ad']!.text = k.ad;
    _c['kimlikNo']!.text = k.kimlikNo ?? '';
    _c['mersisNo']!.text = k.mersisNo ?? '';
    _c['eposta']!.text = k.eposta ?? '';
    _c['telefon']!.text = k.telefon ?? '';
    _c['adres']!.text = k.adres ?? '';
    _c['notlar']!.text = k.notlar ?? '';
    setState(() {
      _tercih = k.iletisimTercihi;
      _duzenle = true;
    });
  }

  String? _bos(String a) => _c[a]!.text.trim().isEmpty ? null : _c[a]!.text.trim();

  Future<void> _kaydet(Kisi k) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _bekliyor = true);
    final h = await widget.depo.kisiGuncelle(Kisi(
      id: k.id,
      kiraciId: k.kiraciId,
      tur: k.tur,
      ad: _c['ad']!.text.trim(),
      kimlikNo: _bos('kimlikNo'),
      mersisNo: _bos('mersisNo'),
      eposta: _bos('eposta'),
      telefon: _bos('telefon'),
      adres: _bos('adres'),
      iletisimTercihi: _tercih,
      notlar: _bos('notlar'),
      unvanGecmisi: k.unvanGecmisi,
    ));
    if (!mounted) return;
    setState(() {
      _bekliyor = false;
      if (h == null) _duzenle = false;
    });
    _mesaj(h, 'Kart kaydedildi.');
  }

  Future<void> _iliskiEkle(Kisi k) async {
    final secim = await showDialog<(String, IliskiTuru)>(
      context: context,
      builder: (_) => _IliskiDiyalogu(depo: widget.depo, kisi: k),
    );
    if (secim == null || !mounted) return;
    _mesaj(await widget.depo.iliskiEkle(k.id, secim.$1, secim.$2), 'İlişki eklendi.');
  }

  Widget _alan(String a, String etiket, {String? Function(String?)? dogrula, int satir = 1, TextInputType? klavye}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: Key('kart-$a'),
          controller: _c[a],
          maxLines: satir,
          keyboardType: klavye,
          validator: dogrula,
          decoration: InputDecoration(labelText: etiket),
        ),
      );

  Widget _bilgi(String etiket, String? deger) => deger == null || deger.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(etiket, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(deger)),
          ]),
        );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.depo,
      builder: (context, _) {
        final k = widget.depo.kisi(widget.kisiId);
        if (k == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Kişi bulunamadı.')));
        final gercek = k.tur == KisiTuru.gercek;
        final iliskiler = widget.depo.kisininIliskileri(k.id);
        final dosyalar = widget.depo.dosyaKayitlari.where((d) => d.kisiId == k.id).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(k.ad),
            actions: [
              if (!_duzenle)
                IconButton(
                    key: const Key('kart-duzenle'),
                    tooltip: 'Düzenle',
                    onPressed: () => _duzenlemeyeBasla(k),
                    icon: const Icon(Icons.edit_outlined)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Panel(
              baslik: gercek ? 'Gerçek kişi' : 'Tüzel kişi',
              child: _duzenle
                  ? Form(
                      key: _form,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _alan('ad', gercek ? 'Ad soyad' : 'Unvan',
                            dogrula: (v) => (v ?? '').trim().isEmpty ? 'Zorunlu alan.' : null),
                        _alan('kimlikNo', gercek ? 'TC kimlik no' : 'Vergi kimlik no', klavye: TextInputType.number,
                            dogrula: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          return (gercek ? Dogrulayicilar.tcknGecerli(t) : Dogrulayicilar.vknGecerli(t))
                              ? null
                              : 'Numara geçersiz.';
                        }),
                        if (!gercek)
                          _alan('mersisNo', 'MERSİS no', klavye: TextInputType.number,
                              dogrula: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[0-9]{16}$').hasMatch(v!.trim())
                                  ? null
                                  : '16 haneli olmalıdır.'),
                        _alan('eposta', 'E-posta', klavye: TextInputType.emailAddress,
                            dogrula: (v) => (v ?? '').trim().isEmpty ? null : Dogrulayicilar.eposta(v!.trim())),
                        _alan('telefon', 'Telefon', klavye: TextInputType.phone),
                        _alan('adres', 'Adres', satir: 2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownMenu<IletisimTercihi>(
                            key: const Key('kart-tercih'),
                            label: const Text('İletişim tercihi'),
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: _tercih,
                            onSelected: (t) => setState(() => _tercih = t ?? _tercih),
                            dropdownMenuEntries: [
                              for (final t in IletisimTercihi.values) DropdownMenuEntry(value: t, label: _tercihAdlari[t]!),
                            ],
                          ),
                        ),
                        _alan('notlar', 'Notlar (iç kullanım)', satir: 3),
                        if (!gercek)
                          Text('Unvanı değiştirirseniz eski unvan geçmişe eklenir ve çıkar çatışması taramasında aranmaya devam eder.',
                              style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton(onPressed: () => setState(() => _duzenle = false), child: const Text('Vazgeç')),
                          const SizedBox(width: 8),
                          FilledButton(
                              key: const Key('kart-kaydet'),
                              onPressed: _bekliyor ? null : () => _kaydet(k),
                              child: const Text('Kaydet')),
                        ]),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _bilgi(gercek ? 'TCKN' : 'VKN', k.kimlikNo),
                      _bilgi('MERSİS', k.mersisNo),
                      _bilgi('E-posta', k.eposta),
                      _bilgi('Telefon', k.telefon),
                      _bilgi('Adres', k.adres),
                      _bilgi('İletişim tercihi', _tercihAdlari[k.iletisimTercihi]),
                      _bilgi('Notlar', k.notlar),
                    ]),
            ),
            if (k.unvanGecmisi.isNotEmpty) ...[
              const SizedBox(height: 16),
              Panel(
                baslik: 'Eski unvanlar',
                child: Column(children: [
                  for (final u in k.unvanGecmisi.reversed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.unvan),
                      trailing: Text('${u.gecerlilikBitisi.turkceBicim} tarihine kadar'),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Panel(
              baslik: 'İlişkiler',
              sag: TextButton.icon(
                key: const Key('kart-iliski-ekle'),
                onPressed: () => _iliskiEkle(k),
                icon: const Icon(Icons.add),
                label: const Text('Ekle'),
              ),
              child: iliskiler.isEmpty
                  ? const Text('Kayıtlı ilişki yok. Ortaklar, yetkililer ve grup şirketleri çıkar çatışması taramasında '
                      'dolaylı eşleşme için kullanılır.')
                  : Column(children: [
                      for (final i in iliskiler)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(widget.depo.kisi(i.karsiTaraf(k.id) ?? '')?.ad ?? 'Bilinmeyen kişi'),
                          subtitle: Text(_iliskiAdlari[i.tur]!),
                          trailing: IconButton(
                            tooltip: 'İlişkiyi kaldır',
                            icon: const Icon(Icons.link_off),
                            onPressed: () async => _mesaj(await widget.depo.iliskiSil(i), 'İlişki kaldırıldı.'),
                          ),
                        ),
                    ]),
            ),
            const SizedBox(height: 16),
            Panel(
              baslik: 'Yer aldığı dosyalar',
              child: dosyalar.isEmpty
                  ? const Text('Bu kişi hiçbir dosyada taraf değil.')
                  : Column(children: [
                      for (final d in dosyalar)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(d.gizli ? 'Gizli dosya' : d.dosyaAdi),
                          subtitle: Text('${_sifatAdlari[d.sifat]}${d.kapali ? ' · kapalı' : ''}'),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

class _IliskiDiyalogu extends StatefulWidget {
  const _IliskiDiyalogu({required this.depo, required this.kisi});

  final BellekVeriDeposu depo;
  final Kisi kisi;

  @override
  State<_IliskiDiyalogu> createState() => _IliskiDiyaloguState();
}

class _IliskiDiyaloguState extends State<_IliskiDiyalogu> {
  String _sorgu = '';
  String? _secili;
  IliskiTuru _tur = IliskiTuru.ortak;

  @override
  Widget build(BuildContext context) {
    final adaylar = widget.depo.ara(_sorgu).where((k) => k.id != widget.kisi.id).take(8).toList();
    return AlertDialog(
      title: const Text('İlişki ekle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownMenu<IliskiTuru>(
            key: const Key('iliski-tur'),
            label: const Text('İlişki türü'),
            expandedInsets: EdgeInsets.zero,
            initialSelection: _tur,
            onSelected: (t) => setState(() => _tur = t ?? _tur),
            dropdownMenuEntries: [for (final t in IliskiTuru.values) DropdownMenuEntry(value: t, label: _iliskiAdlari[t]!)],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('iliski-ara'),
            decoration: const InputDecoration(labelText: 'İlişkili kişiyi ara', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _sorgu = v),
          ),
          const SizedBox(height: 8),
          for (final a in adaylar)
            ListTile(
              key: Key('iliski-aday-${a.id}'),
              dense: true,
              selected: _secili == a.id,
              title: Text(a.ad),
              leading: Icon(_secili == a.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              onTap: () => setState(() => _secili = a.id),
            ),
          if (adaylar.isEmpty) const Text('Eşleşen kişi yok; önce kişiyi kaydedin.'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('iliski-kaydet'),
          onPressed: _secili == null ? null : () => Navigator.of(context).pop((_secili!, _tur)),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
