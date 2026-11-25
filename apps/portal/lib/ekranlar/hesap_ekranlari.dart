import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

/// Kiracının abonelik, ekip ve güvenlik ayarları. Sunucu bağlanana kadar bellekte tutulur.
class HesapYonetimi extends ChangeNotifier {
  HesapYonetimi({required this.oturum, required this.depo, Tarih? bugun, DateTime Function()? saat})
      : _saat = saat ?? DateTime.now,
        abonelik = Abonelik.denemeBaslat(
            Paket.taslakPaketler[oturum.hesapTuru]!, bugun ?? Tarih.from(DateTime.now()).gunEkle(-3)),
        lisansKoltugu = switch (oturum.hesapTuru) {
          // Avukatlık bürosu sabit fiyatlıdır: avukat + iki büro personeli dahil.
          HesapTuru.avukatlikBurosu => 3,
          HesapTuru.hukukBurosu => 5,
          HesapTuru.kurumsal => 10,
        };

  final Oturum oturum;
  final BellekVeriDeposu depo;
  final DateTime Function() _saat;
  final Abonelik abonelik;
  int lisansKoltugu;
  final List<Davet> davetler = [];

  /// Kiracıdaki koltuk kullanan aktif kullanıcılar (demo: oturum sahibi + depo kullanıcıları).
  int get aktifKoltuk => depo.kullanicilar.length.clamp(1, 1 << 30);

  List<int>? _ikiAdimliSir;
  List<int>? _bekleyenSir;
  bool? _sunucuIkiAdimli;
  bool get ikiAdimliAcik => _sunucuIkiAdimli ?? _ikiAdimliSir != null;

  /// Sunucu bağlıyken iki adımlı doğrulamanın durumu sunucudan okunur.
  Future<void> ikiAdimliDurumuYukle() async {
    final u = depo.uzak;
    if (u == null) return;
    _sunucuIkiAdimli = await u.ikiAdimliAcikMi();
    notifyListeners();
  }

  /// Kurulumu başlatır: (sır, otpauth bağlantısı). Sunucu bağlıyken sır sunucuda üretilip şifreli saklanır.
  Future<(List<int>, String)> ikiAdimliKurulum() async {
    final u = depo.uzak;
    if (u == null) {
      final sir = ikiAdimliBaslat();
      return (sir, Totp.otpauthUri(yayinci: urunAdi, hesap: oturum.eposta, sir: sir));
    }
    final (anahtar, baglanti) = await u.ikiAdimliBaslat();
    return (Totp.base32Coz(anahtar), baglanti);
  }

  /// Açıksa kapatır, kapalıysa etkinleştirir; hata varsa mesajı döner.
  Future<String?> ikiAdimliOnayla(String kod) async {
    final u = depo.uzak;
    if (u == null) {
      final ok = ikiAdimliAcik ? ikiAdimliKapat(kod) : ikiAdimliEtkinlestir(kod);
      return ok ? null : 'Kod doğrulanamadı. Uygulamadaki güncel 6 haneli kodu girin.';
    }
    try {
      if (ikiAdimliAcik) {
        await u.ikiAdimliKapat(kod);
        _sunucuIkiAdimli = false;
      } else {
        await u.ikiAdimliEtkinlestir(kod);
        _sunucuIkiAdimli = true;
      }
      notifyListeners();
      return null;
    } on Exception catch (e) {
      return '$e';
    }
  }

  List<Davet> bekleyenDavetler() => davetler.where((d) => d.gecerliMi(_saat())).toList();

  /// Sunucu bağlıyken davetlerin sunucudaki kimlikleri (iptal için) ve kullanılan koltuk.
  final Map<Davet, String> _sunucuKimlikleri = {};
  int? _sunucuDolu;

  /// Sunucudan davet listesi ve koltuk durumu (yalnızca yöneticiler görür; diğerlerinde liste boş kalır).
  Future<void> sunucudanYukle() async {
    final u = depo.uzak;
    if (u == null) return;
    final (lisans, dolu) = await u.koltuklar();
    final liste = await u.davetler();
    lisansKoltugu = lisans;
    _sunucuDolu = dolu;
    davetler.clear();
    _sunucuKimlikleri.clear();
    for (final j in liste) {
      if (j['durum'] != 'bekliyor') continue;
      final olusturma = DateTime.parse(j['olusturma'] as String).toLocal();
      final d = Davet(
        kod: '',
        kiraciId: oturum.kiraciId,
        eposta: j['eposta'] as String,
        roller: {
          for (final r in (j['roller'] as List? ?? const []))
            ...Rol.values.where((x) => x.name == r),
        },
        davetEden: '',
        olusturma: olusturma,
        gecerlilik: DateTime.parse(j['sonGecerlilik'] as String).toLocal().difference(olusturma),
      );
      davetler.add(d);
      _sunucuKimlikleri[d] = j['id'] as String;
    }
    notifyListeners();
  }

  /// Koltuk özeti: sunucu bağlıyken sunucunun saydığı (aktif kullanıcı + bekleyen davet).
  int get doluKoltuk => _sunucuDolu ?? aktifKoltuk + bekleyenDavetler().where((d) => d.koltukTuketir()).length;

  /// Sunucu bağlıyken davet sunucuda oluşur; dönen değer (hata, davet kodu). Kod yalnızca bir kez gösterilir.
  Future<(String?, String?)> davetGonder(String eposta, Set<Rol> roller) async {
    final u = depo.uzak;
    if (u == null) return (davetEt(eposta, roller), null);
    final epostaHatasi = Dogrulayicilar.eposta(eposta);
    if (epostaHatasi != null) return (epostaHatasi, null);
    if (roller.isEmpty) return ('En az bir rol seçilmelidir.', null);
    try {
      final kod = await u.davetEt(eposta, roller);
      await sunucudanYukle();
      return (null, kod);
    } on Exception catch (e) {
      return ('$e', null);
    }
  }

  Future<String?> davetIptalEt(Davet d) async {
    final u = depo.uzak;
    final id = _sunucuKimlikleri[d];
    if (u == null || id == null) {
      davetIptal(d);
      return null;
    }
    try {
      await u.davetIptal(id);
      await sunucudanYukle();
      return null;
    } on Exception catch (e) {
      return '$e';
    }
  }

  /// Yeni davet; koltuk yetmezse hata mesajı döner.
  String? davetEt(String eposta, Set<Rol> roller) {
    final epostaHatasi = Dogrulayicilar.eposta(eposta);
    if (epostaHatasi != null) return epostaHatasi;
    final e = eposta.trim().toLowerCase();
    if (bekleyenDavetler().any((d) => d.eposta == e)) return 'Bu adrese bekleyen bir davet zaten var.';
    final hata = koltukKontrolu(
      lisansKoltugu: lisansKoltugu,
      koltukKullananAktifKullanici: aktifKoltuk,
      koltukTuketenBekleyenDavet: bekleyenDavetler().where((d) => d.koltukTuketir()).length,
      yeniRoller: roller,
    );
    if (hata != null) return hata;
    final d = Davet(
      kod: Davet.kodUret(),
      kiraciId: oturum.kiraciId,
      eposta: e,
      roller: roller,
      davetEden: oturum.kullaniciId,
      olusturma: _saat(),
    );
    davetler.add(d);
    depo.okumaKaydet(DenetimIslemi.rolVerme, 'davet', e, roller.map((r) => r.ad).join(', '));
    notifyListeners();
    return null;
  }

  void davetIptal(Davet d) {
    final i = davetler.indexOf(d);
    if (i < 0) return;
    davetler[i] = Davet(
      kod: d.kod,
      kiraciId: d.kiraciId,
      eposta: d.eposta,
      roller: d.roller,
      davetEden: d.davetEden,
      olusturma: d.olusturma,
      iptal: true,
    );
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'davet', d.eposta, 'Davet iptal edildi');
    notifyListeners();
  }

  /// 2FA kurulumu: sır üretilir, kullanıcı uygulamadan ilk kodu girince etkinleşir.
  List<int> ikiAdimliBaslat() => _bekleyenSir = Totp.sirUret();

  bool ikiAdimliEtkinlestir(String kod) {
    final sir = _bekleyenSir;
    if (sir == null || !Totp.dogrula(sir, kod.trim(), _saat())) return false;
    _ikiAdimliSir = sir;
    _bekleyenSir = null;
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'guvenlik', oturum.kullaniciId, 'İki adımlı doğrulama açıldı');
    notifyListeners();
    return true;
  }

  bool ikiAdimliKapat(String kod) {
    final sir = _ikiAdimliSir;
    if (sir == null || !Totp.dogrula(sir, kod.trim(), _saat())) return false;
    _ikiAdimliSir = null;
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'guvenlik', oturum.kullaniciId, 'İki adımlı doğrulama kapatıldı');
    notifyListeners();
    return true;
  }

  void iptalEt() {
    abonelik.iptalEt();
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'abonelik', oturum.kiraciId, 'Dönem sonunda iptal talebi');
    notifyListeners();
  }

  void donemSec(OdemeDonemi donem) {
    abonelik.donem = donem;
    notifyListeners();
  }

  /// Ödeme sağlayıcısı (yurt içi, sunucu tarafında) bağlanana kadar ödeme sonucu buradan işlenir.
  void odemeSonucu({required bool basarili}) {
    final bugun = Tarih.from(_saat());
    if (basarili) {
      abonelik.odemeAlindi(bugun);
    } else {
      abonelik.odemeBasarisiz(bugun);
    }
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'abonelik', oturum.kiraciId,
        basarili ? 'Ödeme alındı' : 'Ödeme başarısız');
    notifyListeners();
  }

  String? koltukGuncelle(int yeni) {
    if (yeni < aktifKoltuk) return 'Aktif kullanıcı sayısının ($aktifKoltuk) altına inilemez.';
    if (abonelik.paket.fiyatTuru == FiyatTuru.koltukBasi) {
      abonelik.koltukDegistir(yeni, Tarih.from(_saat()));
    }
    lisansKoltugu = yeni;
    notifyListeners();
    return null;
  }
}

RozetTuru _durumRozeti(AbonelikDurumu d) => switch (d) {
      AbonelikDurumu.aktif => RozetTuru.onay,
      AbonelikDurumu.deneme => RozetTuru.devam,
      AbonelikDurumu.odemeBekliyor => RozetTuru.uyari,
      AbonelikDurumu.askida || AbonelikDurumu.iptal => RozetTuru.kritik,
    };

class AbonelikEkrani extends StatelessWidget {
  const AbonelikEkrani({super.key, required this.yonetim});

  final HesapYonetimi yonetim;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abonelik ve ödeme')),
      body: ListenableBuilder(
        listenable: yonetim,
        builder: (context, _) {
          final a = yonetim.abonelik;
          final paket = a.paket;
          final teklif = paket.fiyatTuru == FiyatTuru.teklif;
          final koltuk = paket.fiyatTuru == FiyatTuru.koltukBasi ? yonetim.lisansKoltugu : 1;
          final fatura =
              FaturaTutari.hesapla(teklif ? Para.sifir : paket.donemTutari(a.donem, ucretliKoltuk: koltuk));
          final bugun = Tarih.from(DateTime.now());
          final kalan = bugun.farkGun(a.donemSonu);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Panel(
                baslik: paket.hesapTuru.ad,
                sag: DurumRozeti(a.durum.ad, _durumRozeti(a.durum)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.durum == AbonelikDurumu.deneme
                          ? 'Ücretsiz deneme ${uzunTarih(a.donemSonu)} tarihinde bitiyor ($kalan gün).'
                          : 'Dönem sonu: ${uzunTarih(a.donemSonu)}'
                              '${a.donemSonundaIptal ? ' — bu tarihte iptal edilecek' : ''}',
                      key: const Key('abonelik-durum'),
                    ),
                    if (!a.yazilabilir) ...[
                      const SizedBox(height: 8),
                      const Text('Hesabınız salt okunur. Verileriniz korunuyor; ödeme yapınca kaldığınız yerden devam edersiniz.',
                          style: TextStyle(color: Renkler.kritik)),
                    ],
                    if (a.durum == AbonelikDurumu.odemeBekliyor && a.sonrakiDeneme(bugun) != null) ...[
                      const SizedBox(height: 8),
                      Text('Ödeme alınamadı. Kartınız ${uzunTarih(a.sonrakiDeneme(bugun)!)} tarihinde yeniden denenecek.',
                          style: const TextStyle(color: Renkler.uyari)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (teklif)
                const Panel(
                  baslik: 'Kurumsal sözleşme',
                  child: Text('Kurumsal paket teklif usulüdür. Fiyat, kullanıcı sayısı ve modüller satış ekibiyle '
                      'yapılan sözleşmeye göre belirlenir; faturalar sözleşme dönemine göre kesilir.'),
                )
              else
                Panel(
                  baslik: 'Ödeme planı',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<OdemeDonemi>(
                        key: const Key('odeme-donemi'),
                        segments: const [
                          ButtonSegment(value: OdemeDonemi.aylik, label: Text('Aylık')),
                          ButtonSegment(value: OdemeDonemi.yillik, label: Text('Yıllık (2 ay hediye)')),
                        ],
                        selected: {a.donem},
                        onSelectionChanged: (s) => yonetim.donemSec(s.first),
                      ),
                      const SizedBox(height: 16),
                      if (paket.fiyatTuru == FiyatTuru.koltukBasi)
                        Row(
                          children: [
                            const Expanded(child: Text('Ücretli kullanıcı (koltuk)')),
                            IconButton(
                              key: const Key('koltuk-azalt'),
                              tooltip: 'Koltuk azalt',
                              onPressed: () => _mesaj(context, yonetim.koltukGuncelle(yonetim.lisansKoltugu - 1)),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${yonetim.lisansKoltugu}', key: const Key('koltuk-sayisi'),
                                style: Theme.of(context).textTheme.titleMedium),
                            IconButton(
                              key: const Key('koltuk-artir'),
                              tooltip: 'Koltuk artır',
                              onPressed: () => _mesaj(context, yonetim.koltukGuncelle(yonetim.lisansKoltugu + 1)),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      const Divider(height: 24),
                      _Satir('Tutar (KDV hariç)', fatura.matrah.bicimli),
                      _Satir('KDV %20', fatura.kdv.bicimli),
                      _Satir('Toplam', fatura.toplam.bicimli, kalin: true, anahtar: 'fatura-toplam'),
                      const SizedBox(height: 4),
                      Text('Fiyatlar taslaktır; lansmanda kesinleşecektir.',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('odeme-yap'),
                            onPressed: () => _odemeOnay(context, fatura.toplam),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Güvenli ödeme'),
                          ),
                          if (a.durum == AbonelikDurumu.aktif && !a.donemSonundaIptal)
                            OutlinedButton(
                              key: const Key('abonelik-iptal'),
                              onPressed: () => _iptalOnay(context),
                              child: const Text('Aboneliği iptal et'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Panel(
                baslik: 'Ödeme ve fatura',
                child: Text('Kart bilgileriniz bizim sunucularımızda saklanmaz; ödeme Türkiye\'de lisanslı bir ödeme '
                    'kuruluşunun güvenli sayfasında alınır. Her tahsilat için e-Arşiv/e-Fatura otomatik düzenlenir.'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mesaj(BuildContext context, String? hata) {
    if (hata != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
  }

  Future<void> _odemeOnay(BuildContext context, Para toplam) async {
    final sonuc = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ödeme (önizleme)'),
        content: Text('Canlı sürümde ödeme sağlayıcısının sayfası açılır. Önizlemede ${toplam.bicimli} '
            'tutarındaki ödemenin sonucunu seçin.'),
        actions: [
          TextButton(key: const Key('odeme-basarisiz'), onPressed: () => Navigator.pop(c, false), child: const Text('Başarısız')),
          FilledButton(key: const Key('odeme-basarili'), onPressed: () => Navigator.pop(c, true), child: const Text('Başarılı')),
        ],
      ),
    );
    if (sonuc != null) yonetim.odemeSonucu(basarili: sonuc);
  }

  Future<void> _iptalOnay(BuildContext context) async {
    final evet = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abonelik iptali'),
        content: Text('Aboneliğiniz ${uzunTarih(yonetim.abonelik.donemSonu)} tarihinde sona erecek. '
            'O güne kadar kullanmaya devam edersiniz; sonrasında verilerinizi salt okunur görüp dışa aktarabilirsiniz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(key: const Key('iptal-onay'), onPressed: () => Navigator.pop(c, true), child: const Text('İptal et')),
        ],
      ),
    );
    if (evet == true) yonetim.iptalEt();
  }
}

class _Satir extends StatelessWidget {
  const _Satir(this.etiket, this.deger, {this.kalin = false, this.anahtar});

  final String etiket;
  final String deger;
  final bool kalin;
  final String? anahtar;

  @override
  Widget build(BuildContext context) {
    final stil = kalin ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(etiket, style: stil)),
        Text(deger, key: anahtar == null ? null : Key(anahtar!), style: stil),
      ]),
    );
  }
}

class IkiAdimliEkrani extends StatefulWidget {
  const IkiAdimliEkrani({super.key, required this.yonetim});

  final HesapYonetimi yonetim;

  @override
  State<IkiAdimliEkrani> createState() => _IkiAdimliEkraniState();
}

class _IkiAdimliEkraniState extends State<IkiAdimliEkrani> {
  final _kod = TextEditingController();
  List<int>? _sir;
  String? _baglanti;
  String? _hata;

  @override
  void initState() {
    super.initState();
    widget.yonetim.ikiAdimliDurumuYukle().then((_) {}, onError: (Object _) {});
  }

  @override
  void dispose() {
    _kod.dispose();
    super.dispose();
  }

  Future<void> _onayla() async {
    final y = widget.yonetim;
    final hata = await y.ikiAdimliOnayla(_kod.text);
    if (!mounted) return;
    final ok = hata == null;
    setState(() {
      _hata = hata;
      if (ok) {
        _sir = null;
        _baglanti = null;
        _kod.clear();
      }
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(y.ikiAdimliAcik ? 'İki adımlı doğrulama açıldı.' : 'İki adımlı doğrulama kapatıldı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final y = widget.yonetim;
    final sir = _sir;
    final kodAlani = TextField(
      key: const Key('totp-kod'),
      controller: _kod,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: 'Doğrulama kodu', errorText: _hata),
      onSubmitted: (_) => _onayla(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('İki adımlı doğrulama')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Panel(
            baslik: 'Durum',
            sag: y.ikiAdimliAcik
                ? const DurumRozeti('Açık', RozetTuru.onay)
                : const DurumRozeti('Kapalı', RozetTuru.uyari),
            child: const Text('Girişte şifrenize ek olarak telefonunuzdaki doğrulayıcı uygulamanın ürettiği '
                '6 haneli kod istenir. Avukatlık sırrı içeren hesaplarda açık tutmanızı öneririz.'),
          ),
          const SizedBox(height: 20),
          if (y.ikiAdimliAcik)
            Panel(
              baslik: 'Kapatmak için kod girin',
              child: Column(children: [
                kodAlani,
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(key: const Key('totp-onayla'), onPressed: _onayla, child: const Text('Kapat')),
                ),
              ]),
            )
          else if (sir == null)
            FilledButton.icon(
              key: const Key('totp-baslat'),
              onPressed: () async {
                try {
                  final (sir, baglanti) = await y.ikiAdimliKurulum();
                  if (mounted) {
                    setState(() {
                      _sir = sir;
                      _baglanti = baglanti;
                    });
                  }
                } on Exception catch (e) {
                  if (mounted) setState(() => _hata = '$e');
                }
              },
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: const Text('Kurulumu başlat'),
            )
          else
            Panel(
              baslik: 'Doğrulayıcı uygulamaya ekleyin',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. Doğrulayıcı uygulamada "anahtar gir" seçeneğiyle aşağıdaki anahtarı ekleyin.'),
                  const SizedBox(height: 8),
                  SelectableText(
                    Totp.base32Kodla(sir).replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim(),
                    key: const Key('totp-anahtar'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: _baglanti ?? Totp.otpauthUri(yayinci: urunAdi, hesap: y.oturum.eposta, sir: sir))),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kurulum bağlantısını kopyala'),
                  ),
                  const SizedBox(height: 12),
                  const Text('2. Uygulamanın gösterdiği 6 haneli kodu girin.'),
                  kodAlani,
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(key: const Key('totp-onayla'), onPressed: _onayla, child: const Text('Etkinleştir')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class EkipEkrani extends StatelessWidget {
  const EkipEkrani({super.key, required this.yonetim});

  final HesapYonetimi yonetim;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ekip ve davetler')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('davet-yeni'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => _DavetDiyalogu(yonetim: yonetim)),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Davet et'),
      ),
      body: ListenableBuilder(
        listenable: yonetim,
        builder: (context, _) {
          final bekleyen = yonetim.bekleyenDavetler();
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Panel(
                baslik: 'Lisans koltukları',
                sag: Text('${yonetim.doluKoltuk} / ${yonetim.lisansKoltugu}', key: const Key('koltuk-ozet')),
                child: const Text('Talep eden çalışan, onaycı, müvekkil ve denetçi rolleri koltuk tüketmez.'),
              ),
              const SizedBox(height: 20),
              Panel(
                baslik: 'Kullanıcılar',
                child: Column(children: [
                  for (final e in yonetim.depo.kullanicilar.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                          backgroundColor: Renkler.yesil,
                          child: Text(basHarfler(e.value), style: const TextStyle(color: Colors.white, fontSize: 13))),
                      title: Text(e.value),
                      trailing: const DurumRozeti('Aktif', RozetTuru.onay),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              Panel(
                baslik: 'Bekleyen davetler',
                child: bekleyen.isEmpty
                    ? const Text('Bekleyen davet yok.')
                    : Column(children: [
                        for (final d in bekleyen)
                          ListTile(
                            key: Key('davet-${d.eposta}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(d.eposta),
                            subtitle: Text('${d.roller.map((r) => r.ad).join(', ')} · '
                                '${tarihSaat(d.olusturma.add(d.gecerlilik))} tarihine kadar geçerli'),
                            trailing: IconButton(
                              tooltip: 'Daveti iptal et',
                              onPressed: () async {
                                final h = await yonetim.davetIptalEt(d);
                                if (h != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
                                }
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                      ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DavetDiyalogu extends StatefulWidget {
  const _DavetDiyalogu({required this.yonetim});

  final HesapYonetimi yonetim;

  @override
  State<_DavetDiyalogu> createState() => _DavetDiyaloguState();
}

class _DavetDiyaloguState extends State<_DavetDiyalogu> {
  final _eposta = TextEditingController();
  final Set<Rol> _roller = {};
  String? _hata;

  /// Sunucuda oluşan davetin kodu: davet e-postası gönderimi bağlanana kadar yönetici bağlantıyı kendisi iletir.
  String? _kod;

  @override
  void dispose() {
    _eposta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roller = widget.yonetim.oturum.lisans.roller;
    final kod = _kod;
    if (kod != null) {
      return AlertDialog(
        title: const Text('Davet oluşturuldu'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Davet kodunu kişiye güvenli bir yoldan iletin (72 saat geçerli, bir kez kullanılır):'),
          const SizedBox(height: 8),
          SelectableText(kod, key: const Key('davet-kodu'), style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Kod yalnızca şimdi gösterilir; kaybolursa daveti iptal edip yenisini oluşturun.'),
        ]),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: kod)),
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Ekibe davet et'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('davet-eposta'),
                controller: _eposta,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-posta'),
              ),
              const SizedBox(height: 16),
              const Text('Roller'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in roller)
                    FilterChip(
                      key: Key('rol-${r.name}'),
                      label: Text(ucretsizRoller.contains(r) ? '${r.ad} (ücretsiz)' : r.ad),
                      selected: _roller.contains(r),
                      onSelected: (s) => setState(() => s ? _roller.add(r) : _roller.remove(r)),
                    ),
                ],
              ),
              if (_hata != null) ...[
                const SizedBox(height: 12),
                Text(_hata!, key: const Key('davet-hata'), style: const TextStyle(color: Renkler.kritik)),
              ],
              const SizedBox(height: 12),
              Text('Davet bağlantısı 72 saat geçerlidir. Kişi şifresini kendisi belirler.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('davet-gonder'),
          onPressed: () async {
            final (hata, kod) = await widget.yonetim.davetGonder(_eposta.text, Set.of(_roller));
            if (!mounted) return;
            if (hata != null) {
              setState(() => _hata = hata);
              return;
            }
            if (kod == null) {
              Navigator.pop(context);
              return;
            }
            setState(() => _kod = kod);
          },
          child: const Text('Davet gönder'),
        ),
      ],
    );
  }
}
