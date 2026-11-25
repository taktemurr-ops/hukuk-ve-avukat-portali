import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import 'formlar.dart';

/// Vekâletnameler ve işlem öncesi yetki kontrolü.
class VekaletlerEkrani extends StatefulWidget {
  const VekaletlerEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<VekaletlerEkrani> createState() => _VekaletlerEkraniState();
}

class _VekaletlerEkraniState extends State<VekaletlerEkrani> {
  OzelYetki? _islem;
  VekaletKontrolSonucu? _sonuc;
  String? _seciliId;

  void _kontrolEt(Vekaletname v, String dosyaId) {
    setState(() {
      _seciliId = v.id;
      _sonuc = VekaletKontrolu.kontrolEt(
        vekaletnameler: widget.depo.vekaletnameler,
        muvekkilId: v.muvekkilId,
        avukatId: widget.oturum.kullaniciId,
        dosyaId: dosyaId,
        tarih: Tarih.from(DateTime.now()),
        gerekenYetki: _islem,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    final renkler = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('vekalet-yeni'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<bool>(builder: (_) => VekaletnameFormu(depo: widget.depo, oturum: widget.oturum)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Yeni vekâletname'),
      ),
      body: ListenableBuilder(listenable: widget.depo, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('İşlem öncesi yetki kontrolü', style: metin.titleMedium),
        const SizedBox(height: 4),
        const Text('Feragat, sulh, tahsilat gibi işlemlerden önce vekâletnamede özel yetki olup olmadığını kontrol edin.'),
        const SizedBox(height: 8),
        DropdownMenu<OzelYetki?>(
          key: const Key('vekalet-islem'),
          label: const Text('Yapılacak işlem'),
          expandedInsets: EdgeInsets.zero,
          initialSelection: _islem,
          onSelected: (y) => setState(() {
            _islem = y;
            _sonuc = null;
          }),
          dropdownMenuEntries: [
            const DropdownMenuEntry<OzelYetki?>(value: null, label: 'Olağan işlem (özel yetki gerekmez)'),
            for (final y in OzelYetki.values) DropdownMenuEntry<OzelYetki?>(value: y, label: y.ad),
          ],
        ),
        const SizedBox(height: 16),
        for (final v in widget.depo.vekaletnameler) _vekaletKarti(v, metin, renkler),
        const SizedBox(height: 72),
      ],
    )),
    );
  }

  Widget _vekaletKarti(Vekaletname v, TextTheme metin, ColorScheme renkler) {
    final muvekkil = widget.depo.kisi(v.muvekkilId);
    final dosyaId = v.genel
        ? widget.depo.dosyaKayitlari
                .where((d) => d.kisiId == v.muvekkilId)
                .map((d) => d.dosyaId)
                .firstOrNull ??
            '-'
        : v.dosyalar.first;
    final sonuc = _seciliId == v.id ? _sonuc : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(muvekkil?.ad ?? v.muvekkilId, style: metin.titleMedium),
            Text(
              '${v.genel ? 'Genel' : 'Özel'} vekâletname · ${v.noter ?? '-'} · '
              'Yevmiye ${v.yevmiyeNo ?? '-'} · ${v.duzenlemeTarihi.turkceBicim}',
            ),
            if (v.asilEvrakYeri != null) Text('Asıl evrak: ${v.asilEvrakYeri}', style: metin.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: v.ozelYetkiler.isEmpty
                  ? [const Chip(label: Text('Özel yetki yok'))]
                  : [for (final y in v.ozelYetkiler) Chip(label: Text(y.ad))],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Dosya: $dosyaId', style: metin.bodySmall),
                const Spacer(),
                if (v.ozelYetkiler.contains(OzelYetki.tevkil) && v.durum == VekaletDurumu.gecerli) ...[
                  TextButton(
                    key: Key('yetki-belgesi-${v.id}'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => YetkiBelgesiEkrani(depo: widget.depo, oturum: widget.oturum, vekaletname: v))),
                    child: const Text('Yetki belgesi'),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton(
                  key: Key('vekalet-kontrol-${v.id}'),
                  onPressed: () => _kontrolEt(v, dosyaId),
                  child: const Text('Kontrol et'),
                ),
              ],
            ),
            if (sonuc != null)
              ListTile(
                key: Key('vekalet-sonuc-${v.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  sonuc.uygun ? Icons.check_circle : Icons.cancel,
                  color: sonuc.uygun ? renkler.primary : renkler.error,
                ),
                title: Text(sonuc.uygun ? 'Uygun' : 'Uygun değil'),
                subtitle: sonuc.neden == null ? null : Text(sonuc.neden!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Yetki belgesi (tevkil): vekâletnamede tevkil yetkisi olan avukat, sahip olduğu özel yetkilerden seçtiklerini
/// başka bir avukata devreder. Kurallar çekirdekte; metin taslak şablondur (avukat kontrol edecek).
class YetkiBelgesiEkrani extends StatefulWidget {
  const YetkiBelgesiEkrani({super.key, required this.depo, required this.oturum, required this.vekaletname});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final Vekaletname vekaletname;

  @override
  State<YetkiBelgesiEkrani> createState() => _YetkiBelgesiEkraniState();
}

class _YetkiBelgesiEkraniState extends State<YetkiBelgesiEkrani> {
  final _c = {for (final a in ['alanAd', 'alanBaro', 'alanSicil', 'verenBaro', 'verenSicil', 'kapsam']) a: TextEditingController()};
  final Set<OzelYetki> _yetkiler = {};
  String? _dosyaId;
  bool _pdf = true; // yetki belgesi genellikle imzalanıp gönderilir
  bool _bekliyor = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(String a) => _c[a]!.text.trim().isEmpty ? null : _c[a]!.text.trim();

  /// (metin, hata); hata kural ihlalidir (ör. vekâletnamede olmayan yetki).
  (SablonCiktisi?, String?) _uret() {
    final v = widget.vekaletname;
    try {
      final alt = VekaletKontrolu.yetkiBelgesiVer(
        vekaletname: v,
        verenAvukat: v.avukatlar.contains(widget.oturum.kullaniciId) ? widget.oturum.kullaniciId : v.avukatlar.first,
        alanAvukat: _t('alanAd') ?? '-',
        tarih: Tarih.from(DateTime.now()),
        dosyalar: {if (_dosyaId != null) _dosyaId!},
        devredilenYetkiler: _yetkiler,
      );
      final veren = v.avukatlar.contains(widget.oturum.kullaniciId) ? widget.oturum.adSoyad : widget.depo.kullaniciAdi(v.avukatlar.first);
      return (
        BelgeSablonu.yetkiBelgesi.uygula(VekaletKontrolu.yetkiBelgesiVerisi(
          vekaletname: v,
          alt: alt,
          muvekkilAdi: widget.depo.kisi(v.muvekkilId)?.ad ?? v.muvekkilId,
          verenAdi: veren,
          alanAdi: _t('alanAd') ?? '',
          verenBaro: _t('verenBaro'),
          verenSicil: _t('verenSicil'),
          alanBaro: _t('alanBaro'),
          alanSicil: _t('alanSicil'),
          kapsamAciklama: _t('kapsam'),
          bugun: Tarih.from(DateTime.now()),
        )),
        null,
      );
    } on StateError catch (e) {
      return (null, e.message);
    }
  }

  Future<void> _kaydet(SablonCiktisi c) async {
    final dosyaId = _dosyaId!;
    final ad = 'Yetki belgesi - ${_t('alanAd')}';
    setState(() => _bekliyor = true);
    final h = await widget.depo.sunucudaVeyaYerelde(
      sunucuda: (u) => u.wordBelgeKaydet(dosyaId: dosyaId, ad: ad, metin: c.metin, tur: BelgeTuru.vekaletname, pdf: _pdf),
      yerelde: () {
        widget.depo.belgeOlustur(
            dosyaId: dosyaId, ad: ad, metin: c.metin, yukleyen: widget.oturum.kullaniciId, tur: BelgeTuru.vekaletname);
        return null;
      },
    );
    if (!mounted) return;
    setState(() => _bekliyor = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(h ??
            (widget.depo.uzak == null
                ? 'Yetki belgesi dosyaya kaydedildi.'
                : 'Yetki belgesi ${_pdf ? 'PDF' : 'Word'} olarak dosyaya kaydedildi.'))));
    if (h == null) Navigator.of(context).pop();
  }

  Widget _alan(String a, String etiket, {double genislik = 260}) => SizedBox(
        width: genislik,
        child: TextField(
          key: Key('yb-$a'),
          controller: _c[a],
          decoration: InputDecoration(labelText: etiket),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.vekaletname;
    final (cikti, hata) = _uret();
    final dosyalar = [
      for (final d in widget.depo.dosyaKayitlari.where((d) => d.kisiId == v.muvekkilId && !d.kapali))
        if (v.genel || v.dosyalar.contains(d.dosyaId)) d,
    ];
    final eksik = cikti?.eksikAlanlar ?? const <String>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Yetki belgesi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.depo.kisi(v.muvekkilId)?.ad ?? ''} · ${v.noter ?? '-'} · ${v.duzenlemeTarihi.turkceBicim}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _alan('alanAd', 'Yetki verilen avukat (Av. Ad Soyad)'),
          _alan('alanBaro', 'Barosu', genislik: 160),
          _alan('alanSicil', 'Baro sicil no', genislik: 160),
          _alan('verenBaro', 'Sizin baronuz (isteğe bağlı)', genislik: 200),
          _alan('verenSicil', 'Sizin sicil no (isteğe bağlı)', genislik: 200),
        ]),
        const SizedBox(height: 12),
        _alan('kapsam', 'Kapsam (ör. 27.11.2026 tarihli duruşma)', genislik: 600),
        const SizedBox(height: 16),
        Text('Devredilecek özel yetkiler (yalnızca vekâletnamede olanlar)', style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 6, children: [
          for (final y in v.ozelYetkiler)
            FilterChip(
              key: Key('yb-yetki-${y.name}'),
              label: Text(y.ad),
              selected: _yetkiler.contains(y),
              onSelected: (s) => setState(() {
                if (s) {
                  _yetkiler.add(y);
                } else {
                  _yetkiler.remove(y);
                }
              }),
            ),
        ]),
        const SizedBox(height: 12),
        DropdownMenu<String?>(
          key: const Key('yb-dosya'),
          label: const Text('Kaydedilecek dosya'),
          initialSelection: _dosyaId,
          onSelected: (d) => setState(() => _dosyaId = d),
          dropdownMenuEntries: [
            const DropdownMenuEntry<String?>(value: null, label: 'Seçilmedi'),
            for (final d in dosyalar) DropdownMenuEntry<String?>(value: d.dosyaId, label: d.dosyaAdi),
          ],
        ),
        const SizedBox(height: 16),
        if (hata != null)
          Text(hata, key: const Key('yb-hata'), style: TextStyle(color: Theme.of(context).colorScheme.error))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(cikti!.metin, key: const Key('yb-metin')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            eksik.isEmpty
                ? 'Şablon taslaktır; metni avukat kontrol etmelidir. Baro pulunu unutmayın.'
                : 'Eksik: ${eksik.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.depo.uzak != null) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Word')),
                ButtonSegment(value: true, label: Text('PDF')),
              ],
              selected: {_pdf},
              onSelectionChanged: (s) => setState(() => _pdf = s.first),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('yb-kaydet'),
            onPressed: eksik.isNotEmpty || _dosyaId == null || _bekliyor ? null : () => _kaydet(cikti),
            icon: const Icon(Icons.save_alt),
            label: Text(widget.depo.uzak == null ? 'Dosyaya kaydet' : '${_pdf ? 'PDF' : 'Word'} olarak dosyaya kaydet'),
          ),
        ],
      ]),
    );
  }
}
