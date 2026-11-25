import '../takvim/tarih.dart';
import 'isim_eslestirme.dart';

enum KisiTuru { gercek, tuzel }

enum IletisimTercihi { eposta, telefon, sms, portal }

/// Kişinin veya şirketin önceki adı/unvanı.
class UnvanKaydi {
  const UnvanKaydi({required this.unvan, required this.gecerlilikBitisi});

  final String unvan;
  final Tarih gecerlilikBitisi;
}

/// Müvekkil, karşı taraf, tanık, bilirkişi, vekil ve diğer tüm taraflar için tek kart.
class Kisi {
  const Kisi({
    required this.id,
    required this.kiraciId,
    required this.tur,
    required this.ad,
    this.kimlikNo,
    this.mersisNo,
    this.eposta,
    this.telefon,
    this.adres,
    this.iletisimTercihi = IletisimTercihi.eposta,
    this.unvanGecmisi = const [],
    this.notlar,
  });

  final String id;
  final String kiraciId;
  final KisiTuru tur;

  /// Ad soyad (gerçek kişi) veya unvan (tüzel kişi).
  final String ad;

  /// TCKN (gerçek kişi) veya VKN (tüzel kişi).
  final String? kimlikNo;
  final String? mersisNo;
  final String? eposta;
  final String? telefon;
  final String? adres;
  final IletisimTercihi iletisimTercihi;
  final List<UnvanKaydi> unvanGecmisi;
  final String? notlar;

  /// Güncel ad ve tüm eski unvanlar; eşleştirmede hepsi taranır.
  List<String> get tumAdlar => [ad, for (final u in unvanGecmisi) u.unvan];

  /// Unvan değişikliği: eski unvan geçmişe yazılır, kart aynı kalır.
  Kisi unvanDegistir(String yeniAd, Tarih degisimTarihi) => kopya(
        ad: yeniAd,
        unvanGecmisi: [...unvanGecmisi, UnvanKaydi(unvan: ad, gecerlilikBitisi: degisimTarihi)],
      );

  Kisi kopya({
    String? id,
    String? ad,
    String? kimlikNo,
    String? mersisNo,
    String? eposta,
    String? telefon,
    String? adres,
    IletisimTercihi? iletisimTercihi,
    List<UnvanKaydi>? unvanGecmisi,
    String? notlar,
  }) =>
      Kisi(
        id: id ?? this.id,
        kiraciId: kiraciId,
        tur: tur,
        ad: ad ?? this.ad,
        kimlikNo: kimlikNo ?? this.kimlikNo,
        mersisNo: mersisNo ?? this.mersisNo,
        eposta: eposta ?? this.eposta,
        telefon: telefon ?? this.telefon,
        adres: adres ?? this.adres,
        iletisimTercihi: iletisimTercihi ?? this.iletisimTercihi,
        unvanGecmisi: unvanGecmisi ?? this.unvanGecmisi,
        notlar: notlar ?? this.notlar,
      );
}

enum IliskiTuru { ortak, istirak, yetkili, calisan, akraba, vekil, grupSirketi }

/// İki kişi arasındaki ilişki; çıkar çatışması taramasında dolaylı eşleşme için kullanılır.
class KisiIliskisi {
  const KisiIliskisi({required this.kisiA, required this.kisiB, required this.tur});

  final String kisiA;
  final String kisiB;
  final IliskiTuru tur;

  String? karsiTaraf(String kisiId) => kisiId == kisiA
      ? kisiB
      : kisiId == kisiB
          ? kisiA
          : null;
}

enum MukerrerTuru { kesin, olasi }

class MukerrerAdayi {
  const MukerrerAdayi({required this.kisi, required this.tur, required this.benzerlik});

  final Kisi kisi;
  final MukerrerTuru tur;
  final double benzerlik;
}

/// Yeni kayıt öncesi mükerrer kontrolü ve kayıt birleştirme.
class MukerrerKontrol {
  MukerrerKontrol._();

  /// Aynı kimlik numarası = kesin; aynı/benzer ad = olası.
  static List<MukerrerAdayi> bul(
    Iterable<Kisi> mevcut, {
    required String ad,
    String? kimlikNo,
    double esik = IsimEslestirme.varsayilanEsik,
  }) {
    final sonuc = <MukerrerAdayi>[];
    for (final k in mevcut) {
      if (kimlikNo != null && kimlikNo.isNotEmpty && k.kimlikNo == kimlikNo) {
        sonuc.add(MukerrerAdayi(kisi: k, tur: MukerrerTuru.kesin, benzerlik: 1));
        continue;
      }
      var enIyi = 0.0;
      for (final a in k.tumAdlar) {
        final b = IsimEslestirme.benzerlik(ad, a);
        if (b > enIyi) enIyi = b;
      }
      if (enIyi >= esik) {
        sonuc.add(MukerrerAdayi(kisi: k, tur: MukerrerTuru.olasi, benzerlik: enIyi));
      }
    }
    sonuc.sort((x, y) => y.benzerlik.compareTo(x.benzerlik));
    return sonuc;
  }

  /// [ana] kartı korunur; boş alanları [ikincil] karttan doldurulur, ikincil adı
  /// farklıysa unvan geçmişine eklenir. Dosya, belge ve görev bağlantılarının
  /// ikincil id'den ana id'ye taşınması veri katmanının işidir.
  static Kisi birlestir(Kisi ana, Kisi ikincil, {required Tarih tarih}) {
    if (ana.kiraciId != ikincil.kiraciId) {
      throw ArgumentError('Farklı müşteri ortamlarındaki kayıtlar birleştirilemez.');
    }
    if (ana.kimlikNo != null && ikincil.kimlikNo != null && ana.kimlikNo != ikincil.kimlikNo) {
      throw ArgumentError('Kimlik numaraları farklı kayıtlar birleştirilemez.');
    }
    final gecmis = [...ana.unvanGecmisi];
    final bilinen = ana.tumAdlar.map(IsimEslestirme.normallestir).toSet();
    for (final eskiAd in ikincil.tumAdlar) {
      if (bilinen.add(IsimEslestirme.normallestir(eskiAd))) {
        gecmis.add(UnvanKaydi(unvan: eskiAd, gecerlilikBitisi: tarih));
      }
    }
    final notlar = [ana.notlar, ikincil.notlar].whereType<String>().where((n) => n.isNotEmpty);
    return ana.kopya(
      kimlikNo: ana.kimlikNo ?? ikincil.kimlikNo,
      mersisNo: ana.mersisNo ?? ikincil.mersisNo,
      eposta: ana.eposta ?? ikincil.eposta,
      telefon: ana.telefon ?? ikincil.telefon,
      adres: ana.adres ?? ikincil.adres,
      unvanGecmisi: gecmis,
      notlar: notlar.isEmpty ? null : notlar.join('\n'),
    );
  }
}
