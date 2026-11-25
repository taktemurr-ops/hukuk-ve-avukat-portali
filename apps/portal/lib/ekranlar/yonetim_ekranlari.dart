import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/dosya_secici.dart';
import '../servisler/sunucu_senkronu.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

// ============================================================================= Veri aktarımı

/// Excel'den "CSV (noktalı virgülle ayrılmış)" olarak kaydedilen veya kopyalanan
/// müvekkil listesini önizleyip aktarır.
class VeriAktarimEkrani extends StatefulWidget {
  const VeriAktarimEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<VeriAktarimEkrani> createState() => _VeriAktarimEkraniState();
}

class _VeriAktarimEkraniState extends State<VeriAktarimEkrani> {
  final _metin = TextEditingController();
  AktarimOnizlemesi? _onizleme;
  bool _bekliyor = false;

  static const _ornek = 'Adı Soyadı;TCKN/VKN;E-posta;Telefon;Adres\n'
      'Zeynep Aydın;;zeynep@ornek.com;0532 000 00 00;Kadıköy İstanbul\n'
      'Yeni Şirket A.Ş.;1234567890;hukuk@yenisirket.com.tr;;Ankara';

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _onizle() {
    setState(() => _onizleme = KisiAktarimi.onizle(csv: _metin.text, mevcut: widget.depo.kisiler));
  }

  /// .xlsx sunucuda (belge servisi) okunur; .csv/.txt cihazda çözülür. Sonuç metin alanına yazılıp önizlenir.
  Future<void> _dosyadanYukle() async {
    final f = await dosyaSecici(const ['xlsx', 'csv', 'txt']);
    if (f == null || !mounted) return;
    String? hata;
    String? metin;
    if (f.ad.toLowerCase().endsWith('.xlsx')) {
      final u = widget.depo.uzak;
      if (u == null) {
        hata = 'Excel dosyası sunucu bağlantısıyla okunur. Bu modda dosyayı CSV olarak kaydedip yükleyin.';
      } else {
        setState(() => _bekliyor = true);
        try {
          metin = csvYaz(await u.tabloOku(f.ad, f.icerik));
        } on Exception catch (e) {
          hata = '$e';
        }
      }
    } else {
      metin = csvCoz(f.icerik);
    }
    if (!mounted) return;
    setState(() => _bekliyor = false);
    if (hata != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
      return;
    }
    _metin.text = metin!;
    _onizle();
  }

  Future<void> _aktar() async {
    final o = _onizleme!;
    setState(() => _bekliyor = true);
    final (n, hata) = await widget.depo.kisileriAktar(o);
    if (!mounted) return;
    setState(() => _bekliyor = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hata ??
          '$n kişi aktarıldı. Okunan ${o.satirlar.length}, mükerrer ${o.sayi(SatirDurumu.mukerrer)}, '
              'hatalı ${o.sayi(SatirDurumu.hatali)}.'),
    ));
    if (hata != null) return;
    setState(() {
      _onizleme = null;
      _metin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _onizleme;
    return Scaffold(
      appBar: AppBar(title: const Text('Veri aktarımı · Müvekkil ve taraflar')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Excel dosyasını (.xlsx, ilk sayfa) ya da CSV\'yi yükleyin, veya hücreleri kopyalayıp buraya yapıştırın. '
            'İlk satır başlık olmalıdır. Hiçbir kayıt önizlemeden önce eklenmez.',
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('aktarim-dosya'),
              onPressed: _bekliyor ? null : _dosyadanYukle,
              icon: const Icon(Icons.upload_file),
              label: const Text('Dosyadan yükle (.xlsx, .csv)'),
            ),
            TextButton(
              onPressed: () => setState(() => _metin.text = _ornek),
              child: const Text('Örnek veriyle doldur'),
            ),
          ]),
          TextField(
            key: const Key('aktarim-metin'),
            controller: _metin,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Adı Soyadı;TCKN/VKN;E-posta;Telefon;Adres'),
            onChanged: (_) {
              if (_onizleme != null) setState(() => _onizleme = null);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('aktarim-onizle'),
              onPressed: _onizle,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Önizle'),
            ),
          ),
          if (o != null) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                DurumRozeti('Okunan ${o.satirlar.length}', RozetTuru.notr),
                DurumRozeti('Aktarılacak ${o.sayi(SatirDurumu.aktarilacak)}', RozetTuru.onay),
                DurumRozeti('Mükerrer ${o.sayi(SatirDurumu.mukerrer)}', RozetTuru.uyari),
                DurumRozeti('Hatalı ${o.sayi(SatirDurumu.hatali)}', RozetTuru.kritik),
                DurumRozeti(o.mutabik ? 'Sayım mutabık' : 'Sayım tutmuyor', o.mutabik ? RozetTuru.onay : RozetTuru.kritik),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Eşlenen sütunlar: ${o.esleme.entries.map((e) => '${e.key.ad} ← "${o.basliklar[e.value]}"').join(', ')}',
              style: const TextStyle(color: Renkler.metinIkincil),
            ),
            const SizedBox(height: 12),
            for (final s in o.satirlar)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('aktarim-satir-${s.satirNo}'),
                  leading: Text('${s.satirNo}', style: const TextStyle(color: Renkler.metinIkincil)),
                  title: Text(s.deger(KisiAlani.ad).isEmpty ? '(ad yok)' : s.deger(KisiAlani.ad)),
                  subtitle: Text([
                    s.tur == KisiTuru.gercek ? 'Gerçek kişi' : 'Tüzel kişi',
                    if (s.deger(KisiAlani.kimlikNo).isNotEmpty) s.deger(KisiAlani.kimlikNo),
                    ...s.hatalar,
                    if (s.mukerrerAciklama != null) s.mukerrerAciklama!,
                    ...s.uyarilar,
                  ].join(' · ')),
                  trailing: switch (s.durum) {
                    SatirDurumu.aktarilacak => const DurumRozeti('Aktarılacak', RozetTuru.onay),
                    SatirDurumu.mukerrer => const DurumRozeti('Atlanacak', RozetTuru.uyari),
                    SatirDurumu.hatali => const DurumRozeti('Hatalı', RozetTuru.kritik),
                  },
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('aktarim-aktar'),
                onPressed: _bekliyor || o.sayi(SatirDurumu.aktarilacak) == 0 ? null : _aktar,
                child: Text('${o.sayi(SatirDurumu.aktarilacak)} kişiyi aktar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================= UYAP dosya listesi aktarımı

/// UYAP Avukat Portalı'ndan (ya da başka programdan) Excel/CSV olarak alınan dosya listesini aktarır.
/// Mahkeme + esas no ile mükerrer kontrolü yapılır; hiçbir dosya önizlemeden önce açılmaz.
class DosyaAktarimEkrani extends StatefulWidget {
  const DosyaAktarimEkrani({super.key, required this.depo, required this.kullaniciId});

  final BellekVeriDeposu depo;
  final String kullaniciId;

  @override
  State<DosyaAktarimEkrani> createState() => _DosyaAktarimEkraniState();
}

class _DosyaAktarimEkraniState extends State<DosyaAktarimEkrani> {
  final _metin = TextEditingController();
  DosyaAktarimOnizlemesi? _onizleme;
  late String _sorumlu = widget.kullaniciId;
  bool _bekliyor = false;

  static const _ornek = 'Birim Adı;Dosya No;Dosya Türü;Davacı;Davalı;Açılış Tarihi;Dosya Durumu\n'
      'İstanbul 3. İş Mahkemesi;2026/210;Hukuk;Zeynep Aydın;Mavi Lojistik A.Ş.;12.03.2026;Açık\n'
      'İstanbul 8. İcra Dairesi;2026/15873 E;İcra;ABC Gıda;Yıldız Ltd.;02.04.2026;Açık';

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _onizle() => setState(() => _onizleme =
      DosyaAktarimi.onizle(tablo: CsvAyristirici.ayristir(_metin.text), mevcut: widget.depo.tumDosyalar));

  Future<void> _dosyadanYukle() async {
    final f = await dosyaSecici(const ['xlsx', 'csv', 'txt']);
    if (f == null || !mounted) return;
    String? hata;
    if (f.ad.toLowerCase().endsWith('.xlsx')) {
      final u = widget.depo.uzak;
      if (u == null) {
        hata = 'Excel dosyası sunucu bağlantısıyla okunur. Bu modda dosyayı CSV olarak kaydedip yükleyin.';
      } else {
        setState(() => _bekliyor = true);
        try {
          _metin.text = csvYaz(await u.tabloOku(f.ad, f.icerik));
        } on Exception catch (e) {
          hata = '$e';
        }
      }
    } else {
      _metin.text = csvCoz(f.icerik);
    }
    if (!mounted) return;
    setState(() => _bekliyor = false);
    if (hata != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
      return;
    }
    _onizle();
  }

  Future<void> _aktar() async {
    final o = _onizleme!;
    setState(() => _bekliyor = true);
    final (n, atla, hata) = await widget.depo.dosyalariAktar(o, sorumlu: _sorumlu);
    if (!mounted) return;
    setState(() => _bekliyor = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hata ?? '$n dosya açıldı${atla > 0 ? ', $atla dosya zaten kayıtlı olduğu için atlandı' : ''}.'),
    ));
    if (hata == null) {
      setState(() {
        _onizleme = null;
        _metin.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _onizleme;
    final kullanicilar = widget.depo.kullanicilar;
    return Scaffold(
      appBar: AppBar(title: const Text('Veri aktarımı · UYAP dosya listesi')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('UYAP Avukat Portalı\'ndaki dosya listesini Excel olarak indirip yükleyin ya da başka bir programın '
            'listesini kullanın. Mahkeme/birim ve esas no sütunları zorunludur; aynı mahkeme ve esas no ile kayıtlı dosya '
            'atlanır. Sütun adları UYAP sürümüne göre değişebilir: eşlemeyi önizlemede kontrol edin.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('dosya-aktarim-dosya'),
            onPressed: _bekliyor ? null : _dosyadanYukle,
            icon: const Icon(Icons.upload_file),
            label: const Text('Dosyadan yükle (.xlsx, .csv)'),
          ),
          TextButton(onPressed: () => setState(() => _metin.text = _ornek), child: const Text('Örnek veriyle doldur')),
        ]),
        TextField(
          key: const Key('dosya-aktarim-metin'),
          controller: _metin,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Birim Adı;Dosya No;Davacı;Davalı'),
          onChanged: (_) {
            if (_onizleme != null) setState(() => _onizleme = null);
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownMenu<String>(
            key: const Key('dosya-aktarim-sorumlu'),
            label: const Text('Sorumlu avukat'),
            initialSelection: _sorumlu,
            onSelected: (v) => setState(() => _sorumlu = v ?? _sorumlu),
            dropdownMenuEntries: [
              for (final k in (kullanicilar.isEmpty ? {widget.kullaniciId: widget.kullaniciId} : kullanicilar).entries)
                DropdownMenuEntry(value: k.key, label: k.value),
            ],
          ),
          FilledButton.tonal(key: const Key('dosya-aktarim-onizle'), onPressed: _onizle, child: const Text('Önizle')),
        ]),
        if (o != null) ...[
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 8, children: [
            DurumRozeti('Okunan ${o.satirlar.length}', RozetTuru.notr),
            DurumRozeti('Açılacak ${o.sayi(SatirDurumu.aktarilacak)}', RozetTuru.onay),
            DurumRozeti('Mükerrer ${o.sayi(SatirDurumu.mukerrer)}', RozetTuru.uyari),
            DurumRozeti('Hatalı ${o.sayi(SatirDurumu.hatali)}', RozetTuru.kritik),
          ]),
          const SizedBox(height: 8),
          Text('Eşlenen sütunlar: ${o.esleme.entries.map((e) => '${e.key.ad} ← "${o.basliklar[e.value]}"').join(', ')}',
              style: const TextStyle(color: Renkler.metinIkincil)),
          const SizedBox(height: 12),
          for (final s in o.satirlar)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: Key('dosya-aktarim-satir-${s.satirNo}'),
                leading: Text('${s.satirNo}', style: const TextStyle(color: Renkler.metinIkincil)),
                title: Text(s.baslik.isEmpty ? '(başlık yok)' : s.baslik),
                subtitle: Text([
                  s.mahkeme.isEmpty ? '(mahkeme yok)' : s.mahkeme,
                  s.esasNo ?? s.deger(DosyaAlani.esasNo),
                  s.tur.ad,
                  ...s.hatalar,
                  if (s.mukerrerAciklama != null) s.mukerrerAciklama!,
                  ...s.uyarilar,
                ].join(' · ')),
                trailing: switch (s.durum) {
                  SatirDurumu.aktarilacak => const DurumRozeti('Açılacak', RozetTuru.onay),
                  SatirDurumu.mukerrer => const DurumRozeti('Atlanacak', RozetTuru.uyari),
                  SatirDurumu.hatali => const DurumRozeti('Hatalı', RozetTuru.kritik),
                },
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('dosya-aktarim-aktar'),
              onPressed: _bekliyor || o.sayi(SatirDurumu.aktarilacak) == 0 ? null : _aktar,
              child: Text('${o.sayi(SatirDurumu.aktarilacak)} dosyayı aç'),
            ),
          ),
        ],
      ]),
    );
  }
}

// ============================================================================= Denetim kaydı

/// Sunucu bağlıyken sunucudaki zincir (yalnızca yöneticiler), değilse bu cihazdaki yerel zincir gösterilir.
class DenetimKaydiEkrani extends StatefulWidget {
  const DenetimKaydiEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<DenetimKaydiEkrani> createState() => _DenetimKaydiEkraniState();
}

class _DenetimKaydiEkraniState extends State<DenetimKaydiEkrani> {
  Future<(List<SunucuDenetimOlayi>, int?)>? _sunucu;

  @override
  void initState() {
    super.initState();
    _sunucu = widget.depo.uzak?.denetimGetir();
  }

  Widget _durum(int? bozuk, int adet, {bool sunucu = false}) => Panel(
        child: Row(
          children: [
            Icon(bozuk == null ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
                color: bozuk == null ? Renkler.yesil : Renkler.kritik, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                bozuk == null
                    ? sunucu
                        ? 'Sunucudaki kayıt zinciri baştan sona doğrulandı; hiçbir olay sonradan değiştirilmemiş veya silinmemiş. '
                            'Son $adet olay gösteriliyor.'
                        : 'Kayıt zinciri sağlam: $adet olay, hiçbiri sonradan değiştirilmemiş veya silinmemiş.'
                    : 'Kayıt zinciri $bozuk. olayda kırılmış! Bu durum yöneticiye ve güvenlik ekibine bildirilmelidir.',
                key: const Key('denetim-durum'),
              ),
            ),
          ],
        ),
      );

  Widget _satir(int sira, String baslik, String alt, String ozet) => ListTile(
        dense: true,
        leading: Text('#$sira', style: const TextStyle(color: Renkler.metinIkincil)),
        title: Text(baslik),
        subtitle: Text(alt),
        trailing: Text(ozet.substring(0, 8), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final depo = widget.depo;
    final sunucu = _sunucu;
    return Scaffold(
      appBar: AppBar(title: const Text('Denetim kaydı')),
      body: sunucu == null
          ? () {
              final olaylar = depo.denetim.olaylar.reversed.toList();
              return ListView(padding: const EdgeInsets.all(24), children: [
                _durum(depo.denetim.dogrula(), olaylar.length),
                const SizedBox(height: 16),
                for (final o in olaylar)
                  _satir(o.sira, '${o.islem.ad} · ${o.nesneTuru} ${o.nesneId}',
                      '${tarihSaat(o.zaman.toLocal())} · ${depo.kullaniciAdi(o.kullaniciId)}'
                          '${o.aciklama.isNotEmpty ? ' · ${o.aciklama}' : ''}',
                      o.ozet),
              ]);
            }()
          : FutureBuilder(
              future: sunucu,
              builder: (context, s) {
                if (s.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${s.error}', key: const Key('denetim-hata')),
                  );
                }
                final v = s.data;
                if (v == null) return const Center(child: CircularProgressIndicator());
                final (olaylar, bozuk) = v;
                return ListView(padding: const EdgeInsets.all(24), children: [
                  _durum(bozuk, olaylar.length, sunucu: true),
                  const SizedBox(height: 16),
                  for (final o in olaylar)
                    _satir(o.sira, '${o.islemAdi} · ${o.nesneTuru} ${o.nesneId}',
                        '${tarihSaat(o.zaman.toLocal())} · ${o.kullanici.isEmpty ? 'sistem' : depo.kullaniciAdi(o.kullanici)}'
                            '${o.aciklama.isNotEmpty ? ' · ${o.aciklama}' : ''}',
                        o.ozet),
                ]);
              },
            ),
    );
  }
}
