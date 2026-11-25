import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/cikar_raporu.dart';
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
      sunucuda: (u) => u.kisiEkle(tur: _tur, ad: _ad.text, kimlikNo: _kimlikNo.text, eposta: _eposta.text),
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
