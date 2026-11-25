import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/api_istemcisi.dart';
import '../servisler/kimlik_servisi.dart';
import '../tema/tema.dart';

/// Dış avukat (anlaşmalı büro) portalı: kuruma açılmış işler, bütçe kullanımı, faturalar ve fatura yükleme.
/// Kurumun dosya, talep ve sözleşmeleri bu oturumda görünmez.
class DisAvukatPortaliEkrani extends StatefulWidget {
  const DisAvukatPortaliEkrani({super.key, required this.oturum, required this.api, required this.cikisYap});

  final Oturum oturum;
  final ApiIstemcisi api;
  final VoidCallback cikisYap;

  @override
  State<DisAvukatPortaliEkrani> createState() => _DisAvukatPortaliEkraniState();
}

class _DisAvukatPortaliEkraniState extends State<DisAvukatPortaliEkrani> {
  late Future<List<Map<String, dynamic>>> _isler = _yukle();

  Future<List<Map<String, dynamic>>> _yukle() async =>
      ((await widget.api.get('/dis-portal/isler')) as List).cast<Map<String, dynamic>>();

  void _yenile() => setState(() => _isler = _yukle());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.oturum.kurumAdi} · Dış avukat portalı'),
        actions: [
          IconButton(tooltip: 'Yenile', onPressed: _yenile, icon: const Icon(Icons.refresh)),
          TextButton(key: const Key('dis-portal-cikis'), onPressed: widget.cikisYap, child: const Text('Çıkış')),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _isler,
        builder: (context, d) {
          if (d.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (d.hasError) return Center(child: Text('Yüklenemedi: ${d.error}'));
          final isler = d.data!;
          if (isler.isEmpty) return const Center(child: Text('Size açılmış bir iş yok.'));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final i in isler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _IsKarti(api: widget.api, is_: i, degisti: _yenile),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IsKarti extends StatefulWidget {
  const _IsKarti({required this.api, required this.is_, required this.degisti});

  final ApiIstemcisi api;
  final Map<String, dynamic> is_;
  final VoidCallback degisti;

  @override
  State<_IsKarti> createState() => _IsKartiState();
}

class _IsKartiState extends State<_IsKarti> {
  Future<List<Map<String, dynamic>>>? _faturalar;

  String get _id => widget.is_['id'] as String;

  Future<List<Map<String, dynamic>>> _yukle() async =>
      ((await widget.api.get('/dis-portal/isler/$_id/faturalar')) as List).cast<Map<String, dynamic>>();

  static String _durum(String d) => switch (d) {
        'bekliyor' => 'Onay bekliyor',
        'onaylandi' => 'Onaylandı',
        'finansaGonderildi' => 'Ödemeye gönderildi',
        'reddedildi' => 'Reddedildi',
        _ => d,
      };

  Future<void> _faturaYukle() async {
    final eklendi = await showDialog<bool>(context: context, builder: (_) => _FaturaDiyalogu(api: widget.api, isId: _id));
    if (eklendi == true) {
      setState(() => _faturalar = _yukle());
      widget.degisti();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.is_;
    final butce = Para.kurus(i['butceKurus'] as int);
    final onaylanan = Para.kurus(i['onaylananKurus'] as int);
    final bekleyen = Para.kurus(i['bekleyenKurus'] as int);
    final kapali = i['kapali'] == true;
    final f = _faturalar;
    return Panel(
      baslik: i['konu'] as String,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 16, runSpacing: 8, children: [
          Text('Başlangıç: ${Tarih.parse(i['baslangic'] as String).turkceBicim}'),
          Text('Bütçe: ${butce.bicimli}'),
          Text('Onaylanan: ${onaylanan.bicimli}'),
          Text('Onay bekleyen: ${bekleyen.bicimli}'),
          Text('Kalan: ${(butce - onaylanan).bicimli}'),
          if (kapali) const DurumRozeti('Kapalı', RozetTuru.notr),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(
            key: Key('dis-faturalar-$_id'),
            onPressed: () => setState(() => _faturalar = _yukle()),
            child: const Text('Faturaları göster'),
          ),
          if (!kapali)
            FilledButton.tonal(
              key: Key('dis-fatura-yukle-$_id'),
              onPressed: _faturaYukle,
              child: const Text('Fatura yükle'),
            ),
        ]),
        if (f != null)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (context, d) {
              if (d.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              if (d.hasError) return Text('${d.error}', style: const TextStyle(color: Renkler.kritik));
              final liste = d.data!;
              if (liste.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Fatura yok.'));
              return Column(children: [
                for (final x in liste)
                  ListTile(
                    dense: true,
                    title: Text('${x['no']} · ${Para.kurus(x['tutarKurus'] as int).bicimli}'),
                    subtitle: Text([
                      Tarih.parse(x['tarih'] as String).turkceBicim,
                      _durum(x['durum'] as String),
                      if ((x['retGerekcesi'] as String?)?.isNotEmpty ?? false) 'Gerekçe: ${x['retGerekcesi']}',
                    ].join(' · ')),
                  ),
              ]);
            },
          ),
      ]),
    );
  }
}

class _FaturaDiyalogu extends StatefulWidget {
  const _FaturaDiyalogu({required this.api, required this.isId});

  final ApiIstemcisi api;
  final String isId;

  @override
  State<_FaturaDiyalogu> createState() => _FaturaDiyaloguState();
}

class _FaturaDiyaloguState extends State<_FaturaDiyalogu> {
  final _no = TextEditingController();
  final _tutar = TextEditingController();
  final _aciklama = TextEditingController();
  Tarih _tarih = Tarih.from(DateTime.now());
  String? _hata;
  bool _bekliyor = false;

  @override
  void dispose() {
    _no.dispose();
    _tutar.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final tutar = tutarCoz(_tutar.text);
    if (_no.text.trim().isEmpty || tutar == null || tutar <= 0) {
      setState(() => _hata = 'Fatura numarası ve pozitif bir tutar girin.');
      return;
    }
    setState(() => _bekliyor = true);
    try {
      await widget.api.post('/dis-portal/isler/${widget.isId}/faturalar', {
        'no': _no.text.trim(),
        'tarih': _tarih.isoBicim,
        'tutarKurus': Para.tl(tutar).kurus,
        'aciklama': _aciklama.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _bekliyor = false;
          _hata = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fatura yükle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('dis-fatura-no'), controller: _no, decoration: const InputDecoration(labelText: 'Fatura no')),
          TextField(
            key: const Key('dis-fatura-tutar'),
            controller: _tutar,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tutar (TL, KDV dahil)'),
          ),
          TextField(controller: _aciklama, decoration: const InputDecoration(labelText: 'Açıklama (dönem, hizmet)')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month),
            title: Text('Fatura tarihi: ${_tarih.turkceBicim}'),
            onTap: () async {
              final s = await showDatePicker(
                context: context,
                initialDate: DateTime(_tarih.yil, _tarih.ay, _tarih.gun),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (s != null) setState(() => _tarih = Tarih.from(s));
            },
          ),
          if (_hata != null) Text(_hata!, key: const Key('dis-fatura-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('dis-fatura-kaydet'),
          onPressed: _bekliyor ? null : _kaydet,
          child: const Text('Yükle'),
        ),
      ],
    );
  }
}
