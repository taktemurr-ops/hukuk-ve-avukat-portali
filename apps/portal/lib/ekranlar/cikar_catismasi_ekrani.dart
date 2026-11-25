import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/cikar_raporu.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/sunucu_senkronu.dart';
import '../servisler/veri_deposu.dart';

/// Yeni iş öncesi çıkar çatışması taraması ve gerekçeli iş kabul kararı.
class CikarCatismasiEkrani extends StatefulWidget {
  const CikarCatismasiEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<CikarCatismasiEkrani> createState() => _CikarCatismasiEkraniState();
}

class _AdaySatiri {
  final ad = TextEditingController();
  final kimlikNo = TextEditingController();
  TarafSifati sifat = TarafSifati.karsiTaraf;

  void dispose() {
    ad.dispose();
    kimlikNo.dispose();
  }
}

class _CikarCatismasiEkraniState extends State<CikarCatismasiEkrani> {
  final List<_AdaySatiri> _satirlar = [_AdaySatiri()..sifat = TarafSifati.muvekkil, _AdaySatiri()];
  final _gerekce = TextEditingController();
  final _kosullar = TextEditingController();
  final _yonetici = TextEditingController();
  List<AdayTaraf> _adaylar = const [];
  CikarCatismasiRaporu? _rapor;
  KararTuru _karar = KararTuru.kabul;
  String? _hata;

  @override
  void dispose() {
    for (final s in _satirlar) {
      s.dispose();
    }
    _gerekce.dispose();
    _kosullar.dispose();
    _yonetici.dispose();
    super.dispose();
  }

  /// Sunucu bağlıyken kararlar sunucudan (yönetici onayı dahil).
  List<Map<String, dynamic>>? _sunucuKararlari;

  @override
  void initState() {
    super.initState();
    _kararlariYukle();
  }

  Future<void> _kararlariYukle() async {
    final u = widget.depo.uzak;
    if (u == null) return;
    try {
      final k = await u.isKabulKararlari();
      if (mounted) setState(() => _sunucuKararlari = k);
    } on Exception {
      // liste gösterilmez; tarama ve karar yine çalışır
    }
  }

  Future<void> _tara() async {
    final adaylar = [
      for (final s in _satirlar)
        if (s.ad.text.trim().isNotEmpty)
          AdayTaraf(ad: s.ad.text.trim(), sifat: s.sifat, kimlikNo: s.kimlikNo.text.trim().isEmpty ? null : s.kimlikNo.text.trim()),
    ];
    if (adaylar.isEmpty) {
      setState(() {
        _hata = 'En az bir taraf adı girin.';
        _rapor = null;
      });
      return;
    }
    try {
      final r = await widget.depo.cikarTara(adaylar);
      if (!mounted) return;
      setState(() {
        _hata = null;
        _adaylar = adaylar;
        _rapor = r;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _hata = 'Tarama yapılamadı: $e');
    }
  }

  void _temizle() {
    _hata = null;
    _rapor = null;
    _gerekce.clear();
    _kosullar.clear();
    _yonetici.clear();
    for (final s in _satirlar) {
      s.ad.clear();
      s.kimlikNo.clear();
    }
  }

  /// Sunucuda karar, sunucunun kendi taramasına dayanır; çatışmada kabul başka bir yöneticinin onayını bekler.
  Future<void> _sunucudaKaydet(UzakIslemler u) async {
    final g = _gerekce.text.trim();
    if (g.length < 10) {
      setState(() => _hata = 'Gerekçe en az 10 karakter olmalıdır.');
      return;
    }
    if (_karar == KararTuru.kosulluKabul && _kosullar.text.trim().isEmpty) {
      setState(() => _hata = 'Koşullu kabulde koşullar yazılmalıdır.');
      return;
    }
    try {
      final durum = await u.isKabulKarariKaydet(adaylar: _adaylar, tur: _karar, gerekce: g, kosullar: _kosullar.text);
      if (!mounted) return;
      setState(_temizle);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(durum == 'onayBekliyor'
              ? 'Karar kaydedildi; çatışma olduğu için başka bir yöneticinin onayı bekleniyor.'
              : 'Karar kaydedildi ve denetim kaydına işlendi.')));
      await _kararlariYukle();
    } on Exception catch (e) {
      if (mounted) setState(() => _hata = '$e');
    }
  }

  Future<void> _onayla(String id) async {
    try {
      await widget.depo.uzak!.isKabulOnayla(id);
      await _kararlariYukle();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İş kabulü onaylandı.')));
    } on Exception catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _kararKaydet() {
    final u = widget.depo.uzak;
    if (u != null) {
      _sunucudaKaydet(u);
      return;
    }
    final rapor = _rapor!;
    final karar = CikarCatismasiKarari(
      tur: _karar,
      gerekce: _gerekce.text,
      kararVeren: widget.oturum.adSoyad,
      yoneticiOnayi: _yonetici.text.trim().isEmpty ? null : _yonetici.text.trim(),
      kosullar: _kosullar.text.trim().isEmpty ? null : _kosullar.text.trim(),
    );
    final hata = karar.dogrula(rapor);
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    widget.depo.kararKaydet(KayitliKarar(adaylar: _adaylar, rapor: rapor, karar: karar, zaman: DateTime.now()));
    setState(() {
      _hata = null;
      _rapor = null;
      _gerekce.clear();
      _kosullar.clear();
      _yonetici.clear();
      for (final s in _satirlar) {
        s.ad.clear();
        s.kimlikNo.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Karar kaydedildi ve denetim kaydına işlendi.')));
  }

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    final rapor = _rapor;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Yeni işte yer alacak taraflar', style: metin.titleMedium),
        const SizedBox(height: 4),
        const Text('Müvekkil, karşı taraf ve bilinen ilişkili şirketleri girin. Gizli dosyaların adı gösterilmez.'),
        const SizedBox(height: 12),
        for (var i = 0; i < _satirlar.length; i++) _adaySatiri(i),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _satirlar.add(_AdaySatiri())),
              icon: const Icon(Icons.add),
              label: const Text('Taraf ekle'),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('cikar-tara'),
              onPressed: _tara,
              icon: const Icon(Icons.search),
              label: const Text('Tara'),
            ),
          ],
        ),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_hata!, key: const Key('cikar-hata'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (rapor != null) ...[
          const Divider(height: 32),
          Text('Sonuç', style: metin.titleMedium),
          const SizedBox(height: 8),
          CikarRaporuGorunumu(rapor: rapor),
          const Divider(height: 32),
          Text(rapor.kararGerekir ? 'Gerekçeli karar (zorunlu)' : 'Karar', style: metin.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<KararTuru>(
            segments: const [
              ButtonSegment(value: KararTuru.kabul, label: Text('Kabul')),
              ButtonSegment(value: KararTuru.kosulluKabul, label: Text('Koşullu kabul')),
              ButtonSegment(value: KararTuru.ret, label: Text('Ret')),
            ],
            selected: {_karar},
            onSelectionChanged: (s) => setState(() => _karar = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('cikar-gerekce'),
            controller: _gerekce,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Gerekçe', border: OutlineInputBorder()),
          ),
          if (_karar == KararTuru.kosulluKabul) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _kosullar,
              decoration: const InputDecoration(
                labelText: 'Koşullar (ör. etik duvar, yazılı muvafakat)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (rapor.catismaVar && _karar != KararTuru.ret && widget.depo.uzak != null) ...[
            const SizedBox(height: 12),
            const Text('Çatışma var: kabul kararı, karar verenden farklı bir yöneticinin onayından sonra geçerli olur.',
                key: Key('cikar-onay-bilgi')),
          ],
          if (rapor.catismaVar && _karar != KararTuru.ret && widget.depo.uzak == null) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('cikar-yonetici'),
              controller: _yonetici,
              decoration: const InputDecoration(
                labelText: 'Onaylayan yönetici / ortak',
                helperText: 'Çatışma varken kabul için karar verenden farklı bir yöneticinin onayı gerekir.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('cikar-karar-kaydet'),
            onPressed: _kararKaydet,
            child: const Text('Kararı kaydet'),
          ),
        ],
        if (_sunucuKararlari != null && _sunucuKararlari!.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Son kararlar', style: metin.titleMedium),
          for (final k in _sunucuKararlari!.take(10))
            ListTile(
              key: Key('karar-${k['id']}'),
              dense: true,
              leading: Icon(k['tur'] == 'ret'
                  ? Icons.block
                  : k['durum'] == 'onayBekliyor'
                      ? Icons.hourglass_top
                      : Icons.check_circle_outline),
              title: Text([for (final a in (k['adaylar'] as List? ?? const [])) (a as Map)['ad']].join(', ')),
              subtitle: Text('${k['tur']} · ${widget.depo.kullaniciAdi('${k['kararVeren']}')} · ${k['gerekce']}'
                  '${k['durum'] == 'onayBekliyor' ? ' · yönetici onayı bekliyor' : k['onaylayan'] != null ? ' · onaylayan ${widget.depo.kullaniciAdi('${k['onaylayan']}')}' : ''}'),
              trailing: k['durum'] == 'onayBekliyor' &&
                      k['kararVeren'] != widget.oturum.kullaniciId &&
                      widget.oturum.roller.any((r) => const {Rol.buroSahibi, Rol.yoneticiOrtak, Rol.hukukDirektoru}.contains(r))
                  ? FilledButton(
                      key: Key('karar-onayla-${k['id']}'), onPressed: () => _onayla('${k['id']}'), child: const Text('Onayla'))
                  : null,
            ),
        ],
        if (widget.depo.uzak == null && widget.depo.kararlar.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Son kararlar', style: metin.titleMedium),
          for (final k in widget.depo.kararlar.reversed.take(5))
            ListTile(
              dense: true,
              leading: Icon(k.karar.tur == KararTuru.ret ? Icons.block : Icons.check_circle_outline),
              title: Text(k.adaylar.map((a) => a.ad).join(', ')),
              subtitle: Text('${k.karar.tur.name} · ${k.karar.kararVeren} · ${k.karar.gerekce}'),
            ),
        ],
      ],
    );
  }

  Widget _adaySatiri(int i) {
    final s = _satirlar[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              key: Key('aday-ad-$i'),
              controller: s.ad,
              decoration: const InputDecoration(labelText: 'Ad soyad / unvan'),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: s.kimlikNo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'TCKN / VKN (varsa)'),
            ),
          ),
          SegmentedButton<TarafSifati>(
            segments: const [
              ButtonSegment(value: TarafSifati.muvekkil, label: Text('Müvekkil')),
              ButtonSegment(value: TarafSifati.karsiTaraf, label: Text('Karşı taraf')),
            ],
            selected: {s.sifat == TarafSifati.diger ? TarafSifati.karsiTaraf : s.sifat},
            onSelectionChanged: (secim) => setState(() => s.sifat = secim.first),
          ),
        ],
      ),
    );
  }
}
