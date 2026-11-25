import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';

const _rolAdlari = {'sorumlu': 'Sorumlu avukat', 'yedek': 'Yedek avukat', 'stajyer': 'Stajyer'};
const _oncelikAdlari = {
  GorevOnceligi.dusuk: 'Düşük',
  GorevOnceligi.normal: 'Normal',
  GorevOnceligi.yuksek: 'Yüksek',
  GorevOnceligi.kritik: 'Kritik',
};

/// Büronun iş akışı şablonları. Dosya açılırken seçilen şablonun adımları görev olarak atanır
/// (başlangıçtan N gün sonra, role göre kişiye). Hazır şablonlar değiştirilemez, kopyalanabilir.
class GorevSablonlariEkrani extends StatelessWidget {
  const GorevSablonlariEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  Future<void> _duzenle(BuildContext context, String? id, GorevSablonu? s) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SablonDuzenleEkrani(depo: depo, id: id, sablon: s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Görev şablonları')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sablon-yeni'),
        onPressed: () => _duzenle(context, null, null),
        icon: const Icon(Icons.add),
        label: const Text('Yeni şablon'),
      ),
      body: ListenableBuilder(
        listenable: depo,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const Text('Dosya açarken seçilen şablonun adımları, açılış gününden itibaren belirtilen gün sonrasına '
                'görev olarak atanır. Şablonları yalnızca yöneticiler değiştirebilir.'),
            const SizedBox(height: 12),
            for (final (id, s) in depo.gorevSablonlari)
              Card(
                child: ListTile(
                  key: Key('sablon-${id ?? s.ad}'),
                  title: Text(s.ad),
                  subtitle: Text('${s.adimlar.length} adım · son adım ${s.adimlar.map((a) => a.gunSonra).reduce((a, b) => a > b ? a : b)}. gün'
                      '${id == null ? ' · hazır şablon' : ''}'),
                  trailing: id == null
                      ? TextButton(
                          onPressed: () => _duzenle(context, null, GorevSablonu(ad: '${s.ad} (kopya)', adimlar: s.adimlar)),
                          child: const Text('Kopyala'))
                      : const Icon(Icons.chevron_right),
                  onTap: id == null ? null : () => _duzenle(context, id, s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Adim {
  _Adim(SablonAdimi? a)
      : baslik = TextEditingController(text: a?.baslik ?? ''),
        gun = TextEditingController(text: '${a?.gunSonra ?? 0}'),
        rol = a?.rol ?? 'sorumlu',
        oncelik = a?.oncelik ?? GorevOnceligi.normal;

  final TextEditingController baslik;
  final TextEditingController gun;
  String rol;
  GorevOnceligi oncelik;
}

class SablonDuzenleEkrani extends StatefulWidget {
  const SablonDuzenleEkrani({super.key, required this.depo, this.id, this.sablon});

  final BellekVeriDeposu depo;

  /// Kayıtlı şablonun kimliği; yeni ya da kopya için null.
  final String? id;
  final GorevSablonu? sablon;

  @override
  State<SablonDuzenleEkrani> createState() => _SablonDuzenleEkraniState();
}

class _SablonDuzenleEkraniState extends State<SablonDuzenleEkrani> {
  late final _ad = TextEditingController(text: widget.sablon?.ad ?? '');
  late final List<_Adim> _adimlar = [for (final a in widget.sablon?.adimlar ?? const <SablonAdimi>[]) _Adim(a)];
  String? _hata;
  bool _bekliyor = false;

  @override
  void initState() {
    super.initState();
    if (_adimlar.isEmpty) _adimlar.add(_Adim(null));
  }

  @override
  void dispose() {
    _ad.dispose();
    for (final a in _adimlar) {
      a.baslik.dispose();
      a.gun.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    final GorevSablonu s;
    try {
      // Kurallar sunucuyla aynı yerden (çekirdek): ad, adım sayısı, başlık, gün, rol, öncelik.
      s = GorevSablonu.json({
        'ad': _ad.text,
        'adimlar': [
          for (final a in _adimlar)
            {'baslik': a.baslik.text, 'gunSonra': int.tryParse(a.gun.text.trim()), 'rol': a.rol, 'oncelik': a.oncelik.name},
        ],
      });
    } on FormatException catch (e) {
      setState(() => _hata = e.message);
      return;
    }
    setState(() {
      _hata = null;
      _bekliyor = true;
    });
    final h = await widget.depo.gorevSablonuKaydet(widget.id, s);
    if (!mounted) return;
    setState(() => _bekliyor = false);
    if (h != null) {
      setState(() => _hata = h);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _sil() async {
    final h = await widget.depo.gorevSablonuSil(widget.id!);
    if (!mounted) return;
    if (h != null) {
      setState(() => _hata = h);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Yeni şablon' : 'Şablonu düzenle'),
        actions: [
          if (widget.id != null)
            IconButton(key: const Key('sablon-sil'), tooltip: 'Şablonu kaldır', onPressed: _sil, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(key: const Key('sablon-ad'), controller: _ad, decoration: const InputDecoration(labelText: 'Şablon adı')),
        const SizedBox(height: 16),
        for (var i = 0; i < _adimlar.length; i++)
          Panel(
            baslik: '${i + 1}. adım',
            sag: IconButton(
              tooltip: 'Adımı kaldır',
              onPressed: _adimlar.length == 1 ? null : () => setState(() => _adimlar.removeAt(i)),
              icon: const Icon(Icons.close),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                  key: Key('adim-baslik-$i'),
                  controller: _adimlar[i].baslik,
                  decoration: const InputDecoration(labelText: 'Görev')),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: Key('adim-gun-$i'),
                    controller: _adimlar[i].gun,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Kaç gün sonra'),
                  ),
                ),
                DropdownMenu<String>(
                  label: const Text('Kime'),
                  initialSelection: _adimlar[i].rol,
                  onSelected: (v) => setState(() => _adimlar[i].rol = v ?? _adimlar[i].rol),
                  dropdownMenuEntries: [for (final r in _rolAdlari.entries) DropdownMenuEntry(value: r.key, label: r.value)],
                ),
                DropdownMenu<GorevOnceligi>(
                  label: const Text('Öncelik'),
                  initialSelection: _adimlar[i].oncelik,
                  onSelected: (v) => setState(() => _adimlar[i].oncelik = v ?? _adimlar[i].oncelik),
                  dropdownMenuEntries: [
                    for (final o in _oncelikAdlari.entries) DropdownMenuEntry(value: o.key, label: o.value),
                  ],
                ),
              ]),
            ]),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('adim-ekle'),
            onPressed: _adimlar.length >= 50 ? null : () => setState(() => _adimlar.add(_Adim(null))),
            icon: const Icon(Icons.add),
            label: const Text('Adım ekle'),
          ),
        ),
        if (_hata != null) ...[
          const SizedBox(height: 8),
          Text(_hata!, key: const Key('sablon-hata'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(key: const Key('sablon-kaydet'), onPressed: _bekliyor ? null : _kaydet, child: const Text('Kaydet')),
      ]),
    );
  }
}
