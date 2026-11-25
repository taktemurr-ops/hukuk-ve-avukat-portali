import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../tema/tema.dart';
import 'sure_hesaplama_ekrani.dart';

/// Süre, faiz, harç, vekâlet ücreti, serbest meslek makbuzu, işçilik alacakları ve döviz hesapları.
class HesaplamalarEkrani extends StatelessWidget {
  const HesaplamalarEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 7,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(key: Key('sekme-sure'), text: 'Süre'),
                Tab(key: Key('sekme-faiz'), text: 'Faiz'),
                Tab(key: Key('sekme-harc'), text: 'Dava harcı'),
                Tab(key: Key('sekme-ucret'), text: 'Vekâlet ücreti'),
                Tab(key: Key('sekme-makbuz'), text: 'Makbuz (SMM)'),
                Tab(key: Key('sekme-iscilik'), text: 'İşçilik alacakları'),
                Tab(key: Key('sekme-doviz'), text: 'Döviz'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                SureHesaplamaEkrani(),
                _FaizHesabi(),
                _HarcHesabi(),
                _UcretHesabi(),
                _MakbuzHesabi(),
                _IscilikHesabi(),
                _DovizHesabi(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ortak düzen: sol form, altında sonuç.
class _HesapSayfasi extends StatelessWidget {
  const _HesapSayfasi({required this.baslik, required this.aciklama, required this.form, this.sonuc});

  final String baslik;
  final String aciklama;
  final List<Widget> form;
  final Widget? sonuc;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Panel(
            baslik: baslik,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(aciklama, style: const TextStyle(color: Renkler.metinIkincil)),
                const SizedBox(height: 16),
                ...form,
                if (sonuc != null) ...[const Divider(height: 32), sonuc!],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir(this.etiket, this.deger, {this.vurgulu = false});

  final String etiket;
  final String deger;
  final bool vurgulu;

  @override
  Widget build(BuildContext context) {
    final stil = vurgulu
        ? Theme.of(context).textTheme.titleLarge?.copyWith(color: Renkler.yesil)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(etiket)),
          Text(deger, style: stil),
        ],
      ),
    );
  }
}

class _TarihAlani extends StatelessWidget {
  const _TarihAlani({required this.etiket, required this.tarih, required this.degisti});

  final String etiket;
  final Tarih tarih;
  final ValueChanged<Tarih> degisti;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_month),
      title: Text('$etiket: ${tarih.turkceBicim}'),
      onTap: () async {
        final s = await showDatePicker(
          context: context,
          initialDate: DateTime(tarih.yil, tarih.ay, tarih.gun),
          firstDate: DateTime(2000),
          lastDate: DateTime(2040),
        );
        if (s != null) degisti(Tarih.from(s));
      },
    );
  }
}

String? _tutarDogrula(String? d) => tutarCoz(d ?? '') == null ? 'Geçerli bir tutar girin (ör. 150.000,00).' : null;

// ----------------------------------------------------------------------------- Faiz

class _FaizHesabi extends StatefulWidget {
  const _FaizHesabi();

  @override
  State<_FaizHesabi> createState() => _FaizHesabiState();
}

class _FaizHesabiState extends State<_FaizHesabi> {
  final _form = GlobalKey<FormState>();
  final _anapara = TextEditingController();
  final _akdiOran = TextEditingController();
  FaizTuru _tur = FaizTuru.yasal;
  Tarih _baslangic = Tarih.from(DateTime.now()).gunEkle(-180);
  Tarih _bitis = Tarih.from(DateTime.now());
  FaizSonucu? _sonuc;
  String? _hata;

  @override
  void dispose() {
    _anapara.dispose();
    _akdiOran.dispose();
    super.dispose();
  }

  void _hesapla() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _hata = null;
      try {
        final tablo = switch (_tur) {
          FaizTuru.yasal => FaizTablosu.yasal,
          FaizTuru.avans => FaizTablosu.avans,
          FaizTuru.akdi => FaizTablosu.sabit(tutarCoz(_akdiOran.text) ?? 0),
        };
        _sonuc = FaizHesaplayici.hesapla(
            anapara: Para.tl(tutarCoz(_anapara.text)!), baslangic: _baslangic, bitis: _bitis, tablo: tablo);
      } on ArgumentError catch (e) {
        _sonuc = null;
        _hata = '${e.message}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuc;
    return Form(
      key: _form,
      child: _HesapSayfasi(
        baslik: 'Faiz hesabı',
        aciklama: 'Basit faiz, gün esaslı (365). Oran değişen dönemler ayrı ayrı hesaplanır.',
        form: [
          TextFormField(
            key: const Key('faiz-anapara'),
            controller: _anapara,
            decoration: const InputDecoration(labelText: 'Anapara (TL)'),
            keyboardType: TextInputType.number,
            validator: _tutarDogrula,
          ),
          const SizedBox(height: 12),
          SegmentedButton<FaizTuru>(
            segments: [for (final t in FaizTuru.values) ButtonSegment(value: t, label: Text(t.ad))],
            selected: {_tur},
            onSelectionChanged: (v) => setState(() => _tur = v.first),
          ),
          if (_tur == FaizTuru.akdi)
            TextFormField(
              controller: _akdiOran,
              decoration: const InputDecoration(labelText: 'Yıllık oran (%)'),
              keyboardType: TextInputType.number,
              validator: _tutarDogrula,
            ),
          _TarihAlani(etiket: 'Temerrüt (başlangıç) tarihi', tarih: _baslangic, degisti: (t) => setState(() => _baslangic = t)),
          _TarihAlani(etiket: 'Hesap tarihi', tarih: _bitis, degisti: (t) => setState(() => _bitis = t)),
          FilledButton(key: const Key('faiz-hesapla'), onPressed: _hesapla, child: const Text('Hesapla')),
          if (_hata != null) Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
        ],
        sonuc: s == null
            ? null
            : Column(
                key: const Key('faiz-sonuc'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final k in s.kalemler)
                    _Satir('${k.baslangic.turkceBicim} – ${k.bitis.turkceBicim} · ${k.gun} gün · %${k.oran}',
                        k.faiz.bicimli),
                  const Divider(),
                  _Satir('Toplam faiz (${s.toplamGun} gün)', s.toplamFaiz.bicimli, vurgulu: true),
                  _Satir('Anapara + faiz', s.toplam.bicimli),
                  for (final u in s.uyarilar)
                    Padding(padding: const EdgeInsets.only(top: 8), child: DurumRozeti(u, RozetTuru.uyari)),
                ],
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- Harç

class _HarcHesabi extends StatefulWidget {
  const _HarcHesabi();

  @override
  State<_HarcHesabi> createState() => _HarcHesabiState();
}

class _HarcHesabiState extends State<_HarcHesabi> {
  final _deger = TextEditingController();
  MahkemeTuru _mahkeme = MahkemeTuru.asliye;
  DavaHarci? _sonuc;

  @override
  void dispose() {
    _deger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuc;
    const tarife = HarcTarifesi.y2026;
    return _HesapSayfasi(
      baslik: 'Dava açılış harcı (${tarife.yil})',
      aciklama: 'Konusu para olan davada değeri girin; boş bırakılırsa maktu harçlı dava olarak hesaplanır.',
      form: [
        SegmentedButton<MahkemeTuru>(
          segments: const [
            ButtonSegment(value: MahkemeTuru.sulhHukuk, label: Text('Sulh hukuk')),
            ButtonSegment(value: MahkemeTuru.asliye, label: Text('Asliye')),
          ],
          selected: {_mahkeme},
          onSelectionChanged: (v) => setState(() => _mahkeme = v.first),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('harc-deger'),
          controller: _deger,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Dava değeri (TL, isteğe bağlı)'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('harc-hesapla'),
          onPressed: () {
            final v = tutarCoz(_deger.text);
            setState(() => _sonuc = tarife.davaAcilisi(mahkeme: _mahkeme, deger: v == null ? null : Para.tl(v)));
          },
          child: const Text('Hesapla'),
        ),
      ],
      sonuc: s == null
          ? null
          : Column(
              key: const Key('harc-sonuc'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Satir('Başvurma harcı', s.basvurma.bicimli),
                _Satir('Peşin karar ve ilam harcı', s.pesinKararHarci.bicimli),
                _Satir('Dava açılışında ödenecek', s.acilistaOdenecek.bicimli, vurgulu: true),
                if (!s.kalanKararHarci.sifirMi) _Satir('Karar aşamasında kalan harç', s.kalanKararHarci.bicimli),
                const SizedBox(height: 8),
                Text(s.aciklama, style: const TextStyle(color: Renkler.metinIkincil)),
                const SizedBox(height: 8),
                const DurumRozeti('Harç tarifesi avukat onayı bekliyor; gider avansı ayrıca eklenir', RozetTuru.uyari),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------------------- Vekâlet ücreti

class _UcretHesabi extends StatefulWidget {
  const _UcretHesabi();

  @override
  State<_UcretHesabi> createState() => _UcretHesabiState();
}

class _UcretHesabiState extends State<_UcretHesabi> {
  final _deger = TextEditingController();
  MahkemeTuru? _mahkeme = MahkemeTuru.asliye;
  Tarih _tarih = Tarih.from(DateTime.now());
  UcretSonucu? _sonuc;

  @override
  void dispose() {
    _deger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuc;
    return _HesapSayfasi(
      baslik: 'Karşı taraf vekâlet ücreti (AAÜT)',
      aciklama: 'Konusu para olan işlerde üçüncü kısım dilimleri; hüküm tarihinde yürürlükteki tarife uygulanır.',
      form: [
        TextField(
          key: const Key('ucret-deger'),
          controller: _deger,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Hükmedilen / kabul edilen değer (TL)'),
        ),
        const SizedBox(height: 12),
        DropdownMenu<MahkemeTuru?>(
          label: const Text('Mahkeme (maktu alt sınır için)'),
          expandedInsets: EdgeInsets.zero,
          initialSelection: _mahkeme,
          onSelected: (m) => setState(() => _mahkeme = m),
          dropdownMenuEntries: [
            const DropdownMenuEntry<MahkemeTuru?>(value: null, label: 'Alt sınır uygulama'),
            for (final m in MahkemeTuru.values) DropdownMenuEntry<MahkemeTuru?>(value: m, label: m.ad),
          ],
        ),
        _TarihAlani(etiket: 'Hüküm tarihi', tarih: _tarih, degisti: (t) => setState(() => _tarih = t)),
        FilledButton(
          key: const Key('ucret-hesapla'),
          onPressed: () {
            final v = tutarCoz(_deger.text);
            if (v == null) return;
            setState(() => _sonuc = AvukatlikUcretTarifesi.gecerli(_tarih).hesapla(deger: Para.tl(v), mahkeme: _mahkeme));
          },
          child: const Text('Hesapla'),
        ),
      ],
      sonuc: s == null
          ? null
          : Column(
              key: const Key('ucret-sonuc'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${s.tarife.ad} (RG ${s.tarife.resmiGazete})', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final k in s.kalemler) _Satir('${k.aralik} · %${k.oran}', k.ucret.bicimli),
                const Divider(),
                _Satir('Nispi ücret', s.nispi.bicimli),
                _Satir('Uygulanacak ücret', s.sonuc.bicimli, vurgulu: true),
                Text(s.aciklama, style: const TextStyle(color: Renkler.metinIkincil)),
                const SizedBox(height: 8),
                const DurumRozeti('Tarife verisi avukat onayı bekliyor', RozetTuru.uyari),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------------------- Makbuz

class _MakbuzHesabi extends StatefulWidget {
  const _MakbuzHesabi();

  @override
  State<_MakbuzHesabi> createState() => _MakbuzHesabiState();
}

class _MakbuzHesabiState extends State<_MakbuzHesabi> {
  final _tutar = TextEditingController();
  bool _nettenMi = false;
  bool _stopaj = true;
  MakbuzHesabi? _sonuc;

  @override
  void dispose() {
    _tutar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuc;
    return _HesapSayfasi(
      baslik: 'Serbest meslek makbuzu',
      aciklama: 'KDV %20; müvekkil tevkifat sorumlusuysa (şirket, kamu kurumu) %20 gelir vergisi stopajı kesilir.',
      form: [
        TextField(
          key: const Key('makbuz-tutar'),
          controller: _tutar,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _nettenMi ? 'Ele geçecek net ücret (TL)' : 'Brüt ücret (TL)'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Netten brüte hesapla'),
          value: _nettenMi,
          onChanged: (v) => setState(() => _nettenMi = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Müvekkil stopaj yapacak (tevkifat sorumlusu)'),
          value: _stopaj,
          onChanged: (v) => setState(() => _stopaj = v),
        ),
        FilledButton(
          key: const Key('makbuz-hesapla'),
          onPressed: () {
            final v = tutarCoz(_tutar.text);
            if (v == null) return;
            setState(() => _sonuc = _nettenMi
                ? MakbuzHesabi.nettenHesapla(Para.tl(v), stopajVar: _stopaj)
                : MakbuzHesabi.bruttenHesapla(Para.tl(v), stopajVar: _stopaj));
          },
          child: const Text('Hesapla'),
        ),
      ],
      sonuc: s == null
          ? null
          : Column(
              key: const Key('makbuz-sonuc'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Satir('Brüt ücret', s.brut.bicimli),
                _Satir('KDV (%20)', s.kdv.bicimli),
                _Satir('Gelir vergisi stopajı', s.stopaj.bicimli),
                const Divider(),
                _Satir('Müvekkilin ödeyeceği', s.tahsilEdilecek.bicimli, vurgulu: true),
                _Satir('Net ücret (KDV hariç)', s.netUcret.bicimli),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------------------- İşçilik alacakları

class _IscilikHesabi extends StatefulWidget {
  const _IscilikHesabi();

  @override
  State<_IscilikHesabi> createState() => _IscilikHesabiState();
}

class _IscilikHesabiState extends State<_IscilikHesabi> {
  final _form = GlobalKey<FormState>();
  final _giydirilmis = TextEditingController();
  final _ciplak = TextEditingController();
  final _izinGun = TextEditingController(text: '0');
  Tarih _giris = Tarih.from(DateTime.now()).yilEkle(-5);
  Tarih _cikis = Tarih.from(DateTime.now());
  bool _kidemHakki = true;
  bool _ihbarHakki = true;
  KidemSonucu? _kidem;
  IhbarSonucu? _ihbar;
  IzinSonucu? _izin;
  HizmetSuresi? _sure;
  String? _hata;

  @override
  void dispose() {
    _giydirilmis.dispose();
    _ciplak.dispose();
    _izinGun.dispose();
    super.dispose();
  }

  void _hesapla() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _hata = null;
      _kidem = null;
      _ihbar = null;
      _izin = null;
      try {
        final giydirilmis = Para.tl(tutarCoz(_giydirilmis.text)!);
        final ciplak = tutarCoz(_ciplak.text);
        _sure = HizmetSuresi.hesapla(_giris, _cikis);
        if (_kidemHakki && _sure!.yil >= 1) {
          _kidem = IscilikHesabi.kidem(giris: _giris, cikis: _cikis, giydirilmisBrutUcret: giydirilmis);
        }
        if (_ihbarHakki) _ihbar = IscilikHesabi.ihbar(giris: _giris, cikis: _cikis, giydirilmisBrutUcret: giydirilmis);
        final gun = int.tryParse(_izinGun.text.trim()) ?? 0;
        if (gun > 0) {
          _izin = IscilikHesabi.izinUcreti(kullanilmayanGun: gun, ciplakBrutUcret: Para.tl(ciplak ?? giydirilmis.tutar));
        }
      } on ArgumentError catch (e) {
        _hata = '${e.message}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sure = _sure;
    final k = _kidem;
    final i = _ihbar;
    final z = _izin;
    var toplam = Para.sifir;
    for (final p in [k?.brut, i?.brut, z?.brut]) {
      if (p != null) toplam = toplam + p;
    }
    return Form(
      key: _form,
      child: _HesapSayfasi(
        baslik: 'İşçilik alacakları',
        aciklama: 'Kıdem (1475 s.K. m.14, çıkış tarihindeki tavanla), ihbar (4857 s.K. m.17) ve kullanılmayan yıllık izin '
            '(m.59). Tutarlar brüttür; ihbar ve izin ücretinden gelir vergisi bordroya göre ayrıca kesilir. '
            'Tavan tablosu avukat onayı bekliyor: sonuçlar taslaktır.',
        form: [
          TextFormField(
            key: const Key('iscilik-giydirilmis'),
            controller: _giydirilmis,
            decoration: const InputDecoration(labelText: 'Giydirilmiş aylık brüt ücret (TL)'),
            keyboardType: TextInputType.number,
            validator: _tutarDogrula,
          ),
          TextFormField(
            key: const Key('iscilik-ciplak'),
            controller: _ciplak,
            decoration: const InputDecoration(labelText: 'Çıplak aylık brüt ücret (TL, izin için; boşsa giydirilmiş)'),
            keyboardType: TextInputType.number,
            validator: (d) => (d ?? '').trim().isEmpty ? null : _tutarDogrula(d),
          ),
          _TarihAlani(etiket: 'İşe giriş', tarih: _giris, degisti: (t) => setState(() => _giris = t)),
          _TarihAlani(etiket: 'İşten çıkış', tarih: _cikis, degisti: (t) => setState(() => _cikis = t)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kıdem tazminatına hak kazanıyor'),
            value: _kidemHakki,
            onChanged: (v) => setState(() => _kidemHakki = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('İhbar süresine uyulmadan fesih (ihbar tazminatı)'),
            value: _ihbarHakki,
            onChanged: (v) => setState(() => _ihbarHakki = v),
          ),
          TextFormField(
            key: const Key('iscilik-izin'),
            controller: _izinGun,
            decoration: const InputDecoration(labelText: 'Kullanılmayan yıllık izin (gün)'),
            keyboardType: TextInputType.number,
            validator: (d) => int.tryParse((d ?? '').trim()) == null ? 'Gün sayısı girin.' : null,
          ),
          const SizedBox(height: 12),
          FilledButton(key: const Key('iscilik-hesapla'), onPressed: _hesapla, child: const Text('Hesapla')),
          if (_hata != null) Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
        ],
        sonuc: sure == null || _hata != null
            ? null
            : Column(
                key: const Key('iscilik-sonuc'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Satir('Hizmet süresi', '$sure'),
                  if (k != null) ...[
                    _Satir('Kıdem esas ücret${k.tavanUygulandi ? ' (tavan)' : ''}', k.esasUcret.bicimli),
                    _Satir('Kıdem tazminatı (brüt)', k.brut.bicimli),
                    _Satir('Damga vergisi', '-${k.damgaVergisi.bicimli}'),
                    _Satir('Kıdem tazminatı (net, GV istisna)', k.net.bicimli),
                  ] else if (_kidemHakki)
                    const _Satir('Kıdem tazminatı', 'Bir yıldan az: yok'),
                  if (i != null) _Satir('İhbar tazminatı (${i.hafta} hafta, brüt)', i.brut.bicimli),
                  if (z != null) _Satir('Yıllık izin ücreti (${z.gun} gün, brüt)', z.brut.bicimli),
                  const Divider(),
                  _Satir('Toplam (brüt)', toplam.bicimli, vurgulu: true),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: DurumRozeti('Taslak: tavan tablosu onay bekliyor', RozetTuru.uyari),
                  ),
                ],
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- Döviz

class _DovizHesabi extends StatefulWidget {
  const _DovizHesabi();

  @override
  State<_DovizHesabi> createState() => _DovizHesabiState();
}

class _DovizHesabiState extends State<_DovizHesabi> {
  final _form = GlobalKey<FormState>();
  final _tutar = TextEditingController();
  final _vadeKuru = TextEditingController();
  final _odemeKuru = TextEditingController();
  final _oran = TextEditingController(text: '0');
  String _birim = 'USD';
  bool _temerrut = true;
  Tarih _vade = Tarih.from(DateTime.now()).gunEkle(-90);
  Tarih _odeme = Tarih.from(DateTime.now());
  (Para, String)? _karsilik;
  Para? _faiz;
  String? _hata;

  @override
  void dispose() {
    _tutar.dispose();
    _vadeKuru.dispose();
    _odemeKuru.dispose();
    _oran.dispose();
    super.dispose();
  }

  void _hesapla() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _hata = null;
      try {
        final borc = Para.tl(tutarCoz(_tutar.text)!, birim: _birim);
        final odemeKuru = tutarCoz(_odemeKuru.text)!;
        final vadeKuru = tutarCoz(_vadeKuru.text) ?? odemeKuru;
        _faiz = DovizHesabi.temerrutFaizi(
            dovizTutari: borc, yillikOran: tutarCoz(_oran.text) ?? 0, baslangic: _vade, bitis: _odeme);
        _karsilik = DovizHesabi.borcKarsiligi(
            dovizTutari: borc + _faiz!, vadeKuru: vadeKuru, odemeKuru: odemeKuru, temerrut: _temerrut);
      } on ArgumentError catch (e) {
        _karsilik = null;
        _hata = '${e.message}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _karsilik;
    final f = _faiz;
    return Form(
      key: _form,
      child: _HesapSayfasi(
        baslik: 'Yabancı para alacağı',
        aciklama: 'TBK m.99: borç ödeme günü kuruyla ödenir; temerrütte alacaklı vade ya da ödeme günü kurunu seçebilir. '
            'Faiz 3095 s.K. m.4/a uyarınca döviz cinsinden işler (devlet bankalarının bir yıllık mevduat faizi; '
            'oranı siz girersiniz). Kurlar TCMB döviz satış kurundan girilmelidir; uygulama kur çekmez.',
        form: [
          Row(children: [
            Expanded(
              child: TextFormField(
                key: const Key('doviz-tutar'),
                controller: _tutar,
                decoration: const InputDecoration(labelText: 'Anapara (döviz)'),
                keyboardType: TextInputType.number,
                validator: _tutarDogrula,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              key: const Key('doviz-birim'),
              value: _birim,
              items: [for (final b in const ['USD', 'EUR', 'GBP', 'CHF']) DropdownMenuItem(value: b, child: Text(b))],
              onChanged: (v) => setState(() => _birim = v ?? _birim),
            ),
          ]),
          TextFormField(
            key: const Key('doviz-odeme-kuru'),
            controller: _odemeKuru,
            decoration: const InputDecoration(labelText: 'Ödeme (hesap) günü kuru'),
            keyboardType: TextInputType.number,
            validator: _tutarDogrula,
          ),
          TextFormField(
            key: const Key('doviz-vade-kuru'),
            controller: _vadeKuru,
            decoration: const InputDecoration(labelText: 'Vade günü kuru (boşsa ödeme günü kuru)'),
            keyboardType: TextInputType.number,
            validator: (d) => (d ?? '').trim().isEmpty ? null : _tutarDogrula(d),
          ),
          TextFormField(
            key: const Key('doviz-oran'),
            controller: _oran,
            decoration: const InputDecoration(labelText: 'Yıllık faiz oranı (%)'),
            keyboardType: TextInputType.number,
            validator: _tutarDogrula,
          ),
          _TarihAlani(etiket: 'Vade (temerrüt) tarihi', tarih: _vade, degisti: (t) => setState(() => _vade = t)),
          _TarihAlani(etiket: 'Hesap tarihi', tarih: _odeme, degisti: (t) => setState(() => _odeme = t)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Borçlu temerrütte'),
            value: _temerrut,
            onChanged: (v) => setState(() => _temerrut = v),
          ),
          FilledButton(key: const Key('doviz-hesapla'), onPressed: _hesapla, child: const Text('Hesapla')),
          if (_hata != null) Text(_hata!, style: const TextStyle(color: Renkler.kritik)),
        ],
        sonuc: s == null || f == null
            ? null
            : Column(
                key: const Key('doviz-sonuc'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Satir('Faiz (${_vade.farkGun(_odeme)} gün)', f.bicimli),
                  _Satir('Seçilen kur', s.$2),
                  _Satir('Türk lirası karşılığı (anapara + faiz)', s.$1.bicimli, vurgulu: true),
                ],
              ),
      ),
    );
  }
}
