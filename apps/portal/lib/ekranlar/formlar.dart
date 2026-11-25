import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/cikar_raporu.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

// ============================================================================= Dosya açma

class DosyaFormu extends StatefulWidget {
  const DosyaFormu({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<DosyaFormu> createState() => _DosyaFormuState();
}

class _DosyaFormuState extends State<DosyaFormu> {
  final _form = GlobalKey<FormState>();
  final _baslik = TextEditingController();
  final _mahkeme = TextEditingController();
  final _esas = TextEditingController();
  DosyaTuru _tur = DosyaTuru.hukuk;
  String? _muvekkil;
  String? _karsiTaraf;
  late String _sorumlu = widget.oturum.kullaniciId;
  String? _yedek;
  bool _gizli = false;
  GorevSablonu? _sablon;
  CikarCatismasiRaporu? _rapor;

  @override
  void dispose() {
    _baslik.dispose();
    _mahkeme.dispose();
    _esas.dispose();
    super.dispose();
  }

  void _tarafDegisti() {
    final adaylar = [
      if (_muvekkil != null) AdayTaraf(ad: widget.depo.kisi(_muvekkil!)!.ad, kimlikNo: widget.depo.kisi(_muvekkil!)!.kimlikNo, sifat: TarafSifati.muvekkil),
      if (_karsiTaraf != null)
        AdayTaraf(ad: widget.depo.kisi(_karsiTaraf!)!.ad, kimlikNo: widget.depo.kisi(_karsiTaraf!)!.kimlikNo, sifat: TarafSifati.karsiTaraf),
    ];
    setState(() => _rapor = adaylar.isEmpty ? null : widget.depo.tarayici.tara(adaylar));
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    if (_rapor?.catismaVar ?? false) return;
    final uzak = widget.depo.uzak;
    if (uzak != null) {
      try {
        await uzak.dosyaAc(
          tur: _tur,
          baslik: _baslik.text,
          sorumlu: _sorumlu,
          yedekSorumlu: _yedek,
          gizli: _gizli,
          muvekkilId: _muvekkil,
          karsiTarafId: _karsiTaraf,
        );
        if (mounted) Navigator.of(context).pop(true);
      } on Exception catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    widget.depo.dosyaAc(
      tur: _tur,
      baslik: _baslik.text,
      sorumlu: _sorumlu,
      yedekSorumlu: _yedek,
      muvekkilId: _muvekkil,
      karsiTarafId: _karsiTaraf,
      mahkeme: _mahkeme.text,
      esasNo: _esas.text,
      gizli: _gizli,
      sablon: _sablon,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final kisiler = widget.depo.kisiler;
    final kullanicilar = widget.depo.kullanicilar;
    final rapor = _rapor;
    final engelli = rapor?.catismaVar ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni dosya')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            DropdownMenu<DosyaTuru>(
              label: const Text('Dosya türü'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _tur,
              onSelected: (t) => setState(() => _tur = t ?? _tur),
              dropdownMenuEntries: [for (final t in DosyaTuru.values) DropdownMenuEntry(value: t, label: t.ad)],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('dosya-baslik'),
              controller: _baslik,
              decoration: const InputDecoration(labelText: 'Dosya başlığı (ör. Kara - İşe iade)'),
              validator: (d) => Dogrulayicilar.zorunlu(d, alan: 'Başlık'),
            ),
            const SizedBox(height: 12),
            DropdownMenu<String?>(
              key: const Key('dosya-muvekkil'),
              label: const Text('Müvekkil'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _muvekkil,
              onSelected: (k) {
                _muvekkil = k;
                _tarafDegisti();
              },
              dropdownMenuEntries: [
                const DropdownMenuEntry<String?>(value: null, label: '(seçilmedi)'),
                for (final k in kisiler) DropdownMenuEntry<String?>(value: k.id, label: k.ad),
              ],
            ),
            const SizedBox(height: 12),
            DropdownMenu<String?>(
              key: const Key('dosya-karsi-taraf'),
              label: const Text('Karşı taraf'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _karsiTaraf,
              onSelected: (k) {
                _karsiTaraf = k;
                _tarafDegisti();
              },
              dropdownMenuEntries: [
                const DropdownMenuEntry<String?>(value: null, label: '(seçilmedi)'),
                for (final k in kisiler) DropdownMenuEntry<String?>(value: k.id, label: k.ad),
              ],
            ),
            if (rapor != null) ...[
              const SizedBox(height: 12),
              Text('Çıkar çatışması ön kontrolü', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              CikarRaporuGorunumu(rapor: rapor),
              if (engelli)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: DurumRozeti('Çatışma var: dosya açılmadan önce "Çıkar çatışması" ekranında gerekçeli karar verilmeli',
                      RozetTuru.kritik, key: Key('dosya-catisma')),
                ),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _mahkeme, decoration: const InputDecoration(labelText: 'Mahkeme / icra dairesi')),
            const SizedBox(height: 12),
            TextFormField(controller: _esas, decoration: const InputDecoration(labelText: 'Esas no')),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              label: const Text('Asıl sorumlu'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _sorumlu,
              onSelected: (k) => setState(() => _sorumlu = k ?? _sorumlu),
              dropdownMenuEntries: [
                for (final e in kullanicilar.entries) DropdownMenuEntry(value: e.key, label: e.value),
              ],
            ),
            const SizedBox(height: 12),
            DropdownMenu<String?>(
              label: const Text('Yedek sorumlu'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _yedek,
              onSelected: (k) => setState(() => _yedek = k),
              dropdownMenuEntries: [
                const DropdownMenuEntry<String?>(value: null, label: '(atanmadı)'),
                for (final e in kullanicilar.entries) DropdownMenuEntry<String?>(value: e.key, label: e.value),
              ],
            ),
            if (_yedek != null && _yedek == _sorumlu)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Yedek sorumlu asıl sorumludan farklı olmalı.', style: TextStyle(color: Renkler.kritik)),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gizli dosya'),
              subtitle: const Text('Yalnızca dosya ekibi ve yöneticiler görür; aramada ve raporlarda da gizlenir.'),
              value: _gizli,
              onChanged: (v) => setState(() => _gizli = v),
            ),
            const SizedBox(height: 4),
            Text('Görev şablonu', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Yok'), selected: _sablon == null, onSelected: (_) => setState(() => _sablon = null)),
                for (final s in const [GorevSablonu.isDavasiAcilisi, GorevSablonu.icraTakibiBaslatma])
                  ChoiceChip(label: Text(s.ad), selected: _sablon == s, onSelected: (_) => setState(() => _sablon = s)),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('dosya-kaydet'),
              onPressed: engelli || (_yedek != null && _yedek == _sorumlu) ? null : _kaydet,
              child: const Text('Dosyayı aç'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================= Duruşma

class DurusmaDiyalogu extends StatefulWidget {
  const DurusmaDiyalogu({super.key});

  @override
  State<DurusmaDiyalogu> createState() => _DurusmaDiyaloguState();
}

class _DurusmaDiyaloguState extends State<DurusmaDiyalogu> {
  final _yer = TextEditingController();
  late DateTime _zaman = () {
    final y = DateTime.now().add(const Duration(days: 1));
    return DateTime(y.year, y.month, y.day, 10);
  }();
  String _tur = 'Duruşma';
  String? _hata;

  @override
  void dispose() {
    _yer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Duruşma / etkinlik ekle'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Duruşma', label: Text('Duruşma')),
                ButtonSegment(value: 'Keşif', label: Text('Keşif')),
                ButtonSegment(value: 'Bilirkişi incelemesi', label: Text('Bilirkişi')),
              ],
              selected: {_tur},
              onSelectionChanged: (v) => setState(() => _tur = v.first),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(tarihSaat(_zaman)),
              onTap: () async {
                final g = await showDatePicker(
                  context: context,
                  initialDate: _zaman,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (g == null || !context.mounted) return;
                final s = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_zaman));
                if (s == null) return;
                setState(() => _zaman = DateTime(g.year, g.month, g.day, s.hour, s.minute));
              },
            ),
            TextField(
              key: const Key('durusma-yer'),
              controller: _yer,
              decoration: InputDecoration(labelText: 'Yer (adliye / salon)', errorText: _hata),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('durusma-kaydet'),
          onPressed: () {
            if (_yer.text.trim().isEmpty) {
              setState(() => _hata = 'Yer zorunludur.');
              return;
            }
            Navigator.pop(context, (_zaman, _yer.text.trim(), _tur));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}

// ============================================================================= Vekâletname

class VekaletnameFormu extends StatefulWidget {
  const VekaletnameFormu({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<VekaletnameFormu> createState() => _VekaletnameFormuState();
}

class _VekaletnameFormuState extends State<VekaletnameFormu> {
  final _noter = TextEditingController();
  final _yevmiye = TextEditingController();
  final _evrakYeri = TextEditingController();
  String? _muvekkil;
  Tarih _tarih = Tarih.from(DateTime.now());
  bool _genel = true;
  final Set<OzelYetki> _yetkiler = {};
  String? _hata;

  @override
  void dispose() {
    _noter.dispose();
    _yevmiye.dispose();
    _evrakYeri.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final muvekkil = _muvekkil;
    if (muvekkil == null) {
      setState(() => _hata = 'Müvekkil seçin.');
      return;
    }
    final noter = _noter.text.trim().isEmpty ? null : _noter.text.trim();
    final yevmiye = _yevmiye.text.trim().isEmpty ? null : _yevmiye.text.trim();
    final evrakYeri = _evrakYeri.text.trim().isEmpty ? null : _evrakYeri.text.trim();
    final yetkiler = {..._yetkiler};
    final hata = await widget.depo.sunucudaVeyaYerelde(
      sunucuda: (u) => u.vekaletnameEkle(
        muvekkilId: muvekkil,
        avukatlar: {widget.oturum.kullaniciId},
        duzenlemeTarihi: _tarih,
        noter: noter,
        yevmiyeNo: yevmiye,
        genel: _genel,
        ozelYetkiler: yetkiler,
        asilEvrakYeri: evrakYeri,
      ),
      yerelde: () {
        widget.depo.vekaletnameEkle(
          muvekkilId: muvekkil,
          avukatlar: {widget.oturum.kullaniciId},
          duzenlemeTarihi: _tarih,
          noter: noter,
          yevmiyeNo: yevmiye,
          genel: _genel,
          ozelYetkiler: yetkiler,
          asilEvrakYeri: evrakYeri,
        );
        return null;
      },
    );
    if (!mounted) return;
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni vekâletname')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownMenu<String>(
            key: const Key('vekalet-muvekkil'),
            label: const Text('Müvekkil'),
            expandedInsets: EdgeInsets.zero,
            errorText: _hata,
            onSelected: (k) => setState(() {
              _muvekkil = k;
              _hata = null;
            }),
            dropdownMenuEntries: [
              for (final k in widget.depo.kisiler) DropdownMenuEntry(value: k.id, label: k.ad),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('vekalet-noter'),
            controller: _noter,
            decoration: const InputDecoration(labelText: 'Noter (ör. Kadıköy 5. Noterliği)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _yevmiye, decoration: const InputDecoration(labelText: 'Yevmiye no')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month),
            title: Text('Düzenleme tarihi: ${_tarih.turkceBicim}'),
            onTap: () async {
              final s = await showDatePicker(
                context: context,
                initialDate: DateTime(_tarih.yil, _tarih.ay, _tarih.gun),
                firstDate: DateTime(1990),
                lastDate: DateTime.now(),
              );
              if (s != null) setState(() => _tarih = Tarih.from(s));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Genel vekâletname'),
            subtitle: const Text('Kapalıysa yalnızca seçilen dosyalarda geçerli (özel vekâlet).'),
            value: _genel,
            onChanged: (v) => setState(() => _genel = v),
          ),
          const SizedBox(height: 8),
          Text('Açıkça verilmiş özel yetkiler', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final y in OzelYetki.values)
                FilterChip(
                  key: Key('yetki-${y.name}'),
                  label: Text(y.ad),
                  selected: _yetkiler.contains(y),
                  onSelected: (s) => setState(() => s ? _yetkiler.add(y) : _yetkiler.remove(y)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _evrakYeri,
            decoration: const InputDecoration(labelText: 'Asıl evrakın fiziksel yeri (ör. Arşiv dolabı 2, klasör 7)'),
          ),
          const SizedBox(height: 20),
          FilledButton(key: const Key('vekalet-kaydet'), onPressed: _kaydet, child: const Text('Kaydet')),
        ],
      ),
    );
  }
}
