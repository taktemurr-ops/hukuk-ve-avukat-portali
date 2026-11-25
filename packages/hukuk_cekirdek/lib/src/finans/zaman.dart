import '../hesaplama/para.dart';
import '../takvim/tarih.dart';

enum ZamanDurumu {
  taslak('Taslak'),
  onaylandi('Onaylandı'),
  faturalandi('Faturalandı');

  const ZamanDurumu(this.ad);
  final String ad;
}

/// Bir avukatın bir dosyada harcadığı süre.
class ZamanKaydi {
  const ZamanKaydi({
    required this.id,
    required this.kullanici,
    required this.dosyaId,
    required this.tarih,
    required this.dakika,
    required this.aciklama,
    required this.saatlikUcret,
    this.faturalanabilir = true,
    this.durum = ZamanDurumu.taslak,
    this.onaylayan,
    this.faturaNo,
  });

  final String id;
  final String kullanici;
  final String dosyaId;
  final Tarih tarih;
  final int dakika;
  final String aciklama;
  final Para saatlikUcret;
  final bool faturalanabilir;
  final ZamanDurumu durum;
  final String? onaylayan;
  final String? faturaNo;

  /// Faturalanan süre: [birim] dakikaya yukarı yuvarlanır (varsayılan 6 dk = 0,1 saat).
  int faturaDakikasi({int birim = 6}) => faturalanabilir ? ((dakika + birim - 1) ~/ birim) * birim : 0;

  Para tutar({int birim = 6}) => saatlikUcret.carp(faturaDakikasi(birim: birim) / 60);

  ZamanKaydi _kopya({ZamanDurumu? durum, String? onaylayan, String? faturaNo}) => ZamanKaydi(
        id: id,
        kullanici: kullanici,
        dosyaId: dosyaId,
        tarih: tarih,
        dakika: dakika,
        aciklama: aciklama,
        saatlikUcret: saatlikUcret,
        faturalanabilir: faturalanabilir,
        durum: durum ?? this.durum,
        onaylayan: onaylayan ?? this.onaylayan,
        faturaNo: faturaNo ?? this.faturaNo,
      );
}

/// Kullanıcı bazında saatlik ücret; dosyaya özel ücret varsa o geçerlidir.
class SaatlikUcretTarifesi {
  const SaatlikUcretTarifesi({required this.kullanici, this.dosyaOzel = const {}, required this.varsayilan});

  final Map<String, Para> kullanici;

  /// dosyaId → (kullanıcı → ücret)
  final Map<String, Map<String, Para>> dosyaOzel;
  final Para varsayilan;

  Para ucret(String kullaniciId, String dosyaId) =>
      dosyaOzel[dosyaId]?[kullaniciId] ?? kullanici[kullaniciId] ?? varsayilan;
}

/// Duraklatılabilir kronometre. Zaman dışarıdan verilir (test edilebilirlik ve sunucu saati için).
class Kronometre {
  DateTime? _baslangic;
  Duration _birikmis = Duration.zero;

  bool get calisiyor => _baslangic != null;

  void baslat(DateTime simdi) => _baslangic ??= simdi;

  void duraklat(DateTime simdi) {
    final b = _baslangic;
    if (b == null) return;
    _birikmis += simdi.difference(b);
    _baslangic = null;
  }

  Duration gecen(DateTime simdi) {
    final b = _baslangic;
    return b == null ? _birikmis : _birikmis + simdi.difference(b);
  }

  /// Durdurur, sıfırlar ve geçen süreyi yukarı yuvarlanmış dakika olarak döner (en az 1).
  int bitir(DateTime simdi) {
    final saniye = gecen(simdi).inSeconds;
    _baslangic = null;
    _birikmis = Duration.zero;
    final dk = (saniye + 59) ~/ 60;
    return dk < 1 ? 1 : dk;
  }
}

class FaturaKalemi {
  const FaturaKalemi(this.kayit, this.tutar);
  final ZamanKaydi kayit;
  final Para tutar;
}

class ZamanFaturaTaslagi {
  const ZamanFaturaTaslagi({required this.no, required this.dosyaId, required this.kalemler});

  final String no;
  final String dosyaId;
  final List<FaturaKalemi> kalemler;

  Para get toplam => kalemler.fold(Para.sifir, (a, b) => a + b.tutar);
  int get toplamDakika => kalemler.fold(0, (a, b) => a + b.kayit.faturaDakikasi());
}

/// Zaman kayıtları ve kuralları.
class ZamanDefteri {
  ZamanDefteri({required this.tarife, this.yuvarlamaBirimi = 6});

  final SaatlikUcretTarifesi tarife;
  final int yuvarlamaBirimi;
  final List<ZamanKaydi> _kayitlar = [];
  int _sira = 0;
  int _faturaSira = 0;

  List<ZamanKaydi> get kayitlar => List.unmodifiable(_kayitlar);

  /// Sunucudan gelen kayıtlarla önbelleği değiştirir (kurallar sunucuda uygulanmıştır).
  void yukle(Iterable<ZamanKaydi> kayitlar) {
    _kayitlar
      ..clear()
      ..addAll(kayitlar);
  }

  ZamanKaydi? kayit(String id) {
    for (final k in _kayitlar) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Yeni kayıt. Gelecek tarih, 1–1440 dk dışı süre, kısa açıklama ve aynı gün 24 saati aşan toplam reddedilir.
  ZamanKaydi ekle({
    required String kullanici,
    required String dosyaId,
    required Tarih tarih,
    required int dakika,
    required String aciklama,
    required Tarih bugun,
    bool faturalanabilir = true,
  }) {
    if (tarih.isAfter(bugun)) throw ArgumentError('İleri tarihli zaman kaydı girilemez.');
    if (dakika < 1 || dakika > 1440) throw ArgumentError('Süre 1 dakika ile 24 saat arasında olmalıdır.');
    if (aciklama.trim().length < 5) throw ArgumentError('Yapılan işi kısaca açıklayın.');
    final gunToplami = _kayitlar
        .where((k) => k.kullanici == kullanici && k.tarih == tarih)
        .fold<int>(0, (a, k) => a + k.dakika);
    if (gunToplami + dakika > 1440) throw ArgumentError('Bir gün için toplam 24 saat aşılamaz.');
    _sira++;
    final k = ZamanKaydi(
      id: 'z$_sira',
      kullanici: kullanici,
      dosyaId: dosyaId,
      tarih: tarih,
      dakika: dakika,
      aciklama: aciklama.trim(),
      saatlikUcret: tarife.ucret(kullanici, dosyaId),
      faturalanabilir: faturalanabilir,
    );
    _kayitlar.add(k);
    return k;
  }

  int _indeks(String id) {
    final i = _kayitlar.indexWhere((k) => k.id == id);
    if (i < 0) throw ArgumentError('Kayıt bulunamadı.');
    return i;
  }

  /// Taslak kayıt silinebilir; onaylı veya faturalı kayıt silinemez.
  void sil(String id) {
    final i = _indeks(id);
    if (_kayitlar[i].durum != ZamanDurumu.taslak) throw StateError('Onaylanmış kayıt silinemez.');
    _kayitlar.removeAt(i);
  }

  /// Kişi kendi kaydını onaylayamaz.
  ZamanKaydi onayla(String id, String onaylayan) {
    final i = _indeks(id);
    final k = _kayitlar[i];
    if (k.kullanici == onaylayan) throw StateError('Kendi zaman kaydınızı onaylayamazsınız.');
    if (k.durum != ZamanDurumu.taslak) throw StateError('Kayıt zaten ${k.durum.ad.toLowerCase()}.');
    return _kayitlar[i] = k._kopya(durum: ZamanDurumu.onaylandi, onaylayan: onaylayan);
  }

  /// Dosyanın onaylı ve faturalanabilir kayıtlarından fatura taslağı; [kesinlestir] ise kayıtlar faturalı olur.
  ZamanFaturaTaslagi faturaTaslagi(String dosyaId, {required int yil, bool kesinlestir = false}) {
    final secilen = _kayitlar
        .where((k) => k.dosyaId == dosyaId && k.durum == ZamanDurumu.onaylandi && k.faturalanabilir)
        .toList()
      ..sort((a, b) => a.tarih.compareTo(b.tarih));
    final no = 'ZF-$yil-${(_faturaSira + 1).toString().padLeft(4, '0')}';
    final t = ZamanFaturaTaslagi(
      no: no,
      dosyaId: dosyaId,
      kalemler: [for (final k in secilen) FaturaKalemi(k, k.tutar(birim: yuvarlamaBirimi))],
    );
    if (kesinlestir) {
      if (secilen.isEmpty) throw StateError('Faturalanacak onaylı kayıt yok.');
      _faturaSira++;
      for (final k in secilen) {
        _kayitlar[_indeks(k.id)] = k._kopya(durum: ZamanDurumu.faturalandi, faturaNo: no);
      }
    }
    return t;
  }

  /// [bas]–[son] (dahil) aralığında kullanıcı bazında toplam dakika ve faturalanabilir dakika.
  Map<String, (int, int)> kullaniciOzeti(Tarih bas, Tarih son) {
    final o = <String, (int, int)>{};
    for (final k in _kayitlar.where((k) => k.tarih.arasinda(bas, son))) {
      final (t, f) = o[k.kullanici] ?? (0, 0);
      o[k.kullanici] = (t + k.dakika, f + k.faturaDakikasi(birim: yuvarlamaBirimi));
    }
    return o;
  }
}

/// Tahsil edilen vekâlet ücretinin ortaklar arasında paylaşımı (yüzde).
class PaylasimKurali {
  const PaylasimKurali({required this.getiren, required this.calisan, required this.buro});

  final int getiren;
  final int calisan;
  final int buro;

  static const varsayilan = PaylasimKurali(getiren: 20, calisan: 50, buro: 30);

  String? hata() {
    if (getiren < 0 || calisan < 0 || buro < 0) return 'Oranlar negatif olamaz.';
    if (getiren + calisan + buro != 100) return 'Oranların toplamı %100 olmalıdır.';
    return null;
  }
}

class GelirPaylasimi {
  GelirPaylasimi._();

  static const buroHesabi = 'büro';

  /// Getiren payı dosyayı getirene, çalışan payı dosyada çalışanlara dakika oranında, kalan büroya.
  /// Kuruş yuvarlama farkı büroya yazılır; dosyada kimse çalışmadıysa çalışan payı da büroya kalır.
  static Map<String, Para> dagit({
    required Para tahsilat,
    required String getiren,
    required Map<String, int> calisanDakikalari,
    PaylasimKurali kural = PaylasimKurali.varsayilan,
  }) {
    final hata = kural.hata();
    if (hata != null) throw ArgumentError(hata);
    if (tahsilat.negatif) throw ArgumentError('Tahsilat negatif olamaz.');
    final sonuc = <String, int>{};
    void ekle(String k, int kurus) => sonuc[k] = (sonuc[k] ?? 0) + kurus;

    final getirenPayi = tahsilat.kurus * kural.getiren ~/ 100;
    ekle(getiren, getirenPayi);
    final calisanHavuzu = tahsilat.kurus * kural.calisan ~/ 100;
    final toplamDk = calisanDakikalari.values.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));
    var dagitilan = getirenPayi;
    if (toplamDk > 0) {
      for (final e in calisanDakikalari.entries) {
        if (e.value <= 0) continue;
        final pay = calisanHavuzu * e.value ~/ toplamDk;
        ekle(e.key, pay);
        dagitilan += pay;
      }
    }
    ekle(buroHesabi, tahsilat.kurus - dagitilan);
    return {for (final e in sonuc.entries) e.key: Para.kurus(e.value)};
  }
}
