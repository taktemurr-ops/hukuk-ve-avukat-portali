import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../tema/tema.dart';
import 'sure_hesaplama_ekrani.dart';

/// Süre, faiz, harç, vekâlet ücreti ve serbest meslek makbuzu hesapları.
class HesaplamalarEkrani extends StatelessWidget {
  const HesaplamalarEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 5,
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
