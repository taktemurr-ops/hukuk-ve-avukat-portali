import '../sure/onay_durumu.dart';
import '../takvim/tarih.dart';
import 'para.dart';

/// Hizmet süresi (tam yıl, ay, gün).
class HizmetSuresi {
  const HizmetSuresi(this.yil, this.ay, this.gun);

  final int yil;
  final int ay;
  final int gun;

  /// Giriş ve çıkış günleri dahil.
  factory HizmetSuresi.hesapla(Tarih giris, Tarih cikis) {
    if (cikis.isBefore(giris)) throw ArgumentError('Çıkış tarihi girişten önce olamaz.');
    final son = cikis.gunEkle(1);
    var aylar = (son.yil - giris.yil) * 12 + (son.ay - giris.ay);
    if (giris.ayEkle(aylar).isAfter(son)) aylar--;
    final gun = giris.ayEkle(aylar).farkGun(son);
    return HizmetSuresi(aylar ~/ 12, aylar % 12, gun);
  }

  /// Yıl cinsinden (ay/12, gün/365).
  double get yilKarsiligi => yil + ay / 12 + gun / 365;

  int get toplamAy => yil * 12 + ay;

  @override
  String toString() => '$yil yıl $ay ay $gun gün';
}

/// Kıdem tazminatı tavanı dönemi (1475 s.K. m.14; Hazine ve Maliye Bakanlığı genelgesi, Ocak/Temmuz).
class KidemTavani {
  const KidemTavani(this.baslangic, this.tutar);

  final Tarih baslangic;
  final Para tutar;
}

/// Kıdem tazminatı tavanları. Kaynak: Mali ve Sosyal Haklar genelgeleri. ONAY BEKLİYOR.
class KidemTavanlari {
  KidemTavanlari._();

  static const onayDurumu = OnayDurumu.taslak;

  static final donemler = [
    KidemTavani(Tarih(2022, 1, 1), Para.tl(10848.59)),
    KidemTavani(Tarih(2022, 7, 1), Para.tl(15371.40)),
    KidemTavani(Tarih(2023, 1, 1), Para.tl(19982.83)),
    KidemTavani(Tarih(2023, 7, 1), Para.tl(23489.83)),
    KidemTavani(Tarih(2024, 1, 1), Para.tl(35058.58)),
    KidemTavani(Tarih(2024, 7, 1), Para.tl(41828.42)),
    KidemTavani(Tarih(2025, 1, 1), Para.tl(46655.43)),
    KidemTavani(Tarih(2025, 7, 1), Para.tl(53919.68)),
    KidemTavani(Tarih(2026, 1, 1), Para.tl(64948.77)),
    KidemTavani(Tarih(2026, 7, 1), Para.tl(73729.87)),
  ];

  /// Çıkış tarihinde geçerli tavan; tablo dışındaysa null.
  static Para? tavan(Tarih cikis) {
    Para? sonuc;
    for (final d in donemler) {
      if (!d.baslangic.isAfter(cikis)) sonuc = d.tutar;
    }
    return sonuc;
  }
}

class KidemSonucu {
  const KidemSonucu({
    required this.sure,
    required this.esasUcret,
    required this.tavanUygulandi,
    required this.brut,
    required this.damgaVergisi,
  });

  final HizmetSuresi sure;

  /// Hesaba esas giydirilmiş brüt ücret (tavanla sınırlanmış).
  final Para esasUcret;
  final bool tavanUygulandi;
  final Para brut;
  final Para damgaVergisi;

  /// Kıdem tazminatı tavan tutarına kadar gelir vergisinden istisnadır (GVK m.25/7); yalnız damga vergisi kesilir.
  Para get net => brut - damgaVergisi;
}

class IhbarSonucu {
  const IhbarSonucu({required this.hafta, required this.brut, required this.damgaVergisi});

  final int hafta;
  final Para brut;
  final Para damgaVergisi;
}

class IzinSonucu {
  const IzinSonucu({required this.gun, required this.brut});

  final int gun;
  final Para brut;
}

/// İşçilik alacakları: kıdem, ihbar, yıllık izin ücreti. Brüt hesaplanır; ihbar ve izin ücretindeki gelir vergisi
/// kümülatif matraha bağlı olduğundan bordroya göre ayrıca kesilir. Sonuçlar avukat incelemesine kadar TASLAKTIR.
class IscilikHesabi {
  IscilikHesabi._();

  /// Damga vergisi binde 7,59 (488 s.K. (1) sayılı tablo IV-1-b).
  static const damgaOrani = 0.00759;

  /// [giydirilmisBrutUcret]: aylık brüt ücret + düzenli ödenen yan haklar (yemek, yol, ikramiye payı).
  static KidemSonucu kidem({required Tarih giris, required Tarih cikis, required Para giydirilmisBrutUcret}) {
    final sure = HizmetSuresi.hesapla(giris, cikis);
    if (sure.yil < 1) throw ArgumentError('Kıdem tazminatı için en az bir yıl çalışma gerekir.');
    final tavan = KidemTavanlari.tavan(cikis);
    if (tavan == null) throw ArgumentError('Bu çıkış tarihi için kıdem tavanı tabloda yok.');
    final tavanli = giydirilmisBrutUcret > tavan;
    final esas = tavanli ? tavan : giydirilmisBrutUcret;
    final brut = esas.carp(sure.yilKarsiligi);
    return KidemSonucu(
      sure: sure,
      esasUcret: esas,
      tavanUygulandi: tavanli,
      brut: brut,
      damgaVergisi: brut.carp(damgaOrani),
    );
  }

  /// İhbar süresi (4857 s.K. m.17): 6 aydan az 2 hafta, 6 ay–1,5 yıl 4, 1,5–3 yıl 6, 3 yıldan fazla 8 hafta.
  static int ihbarHaftasi(HizmetSuresi s) {
    final ay = s.toplamAy;
    if (ay < 6) return 2;
    if (ay < 18) return 4;
    if (ay < 36) return 6;
    return 8;
  }

  static IhbarSonucu ihbar({required Tarih giris, required Tarih cikis, required Para giydirilmisBrutUcret}) {
    final hafta = ihbarHaftasi(HizmetSuresi.hesapla(giris, cikis));
    final brut = giydirilmisBrutUcret.carp(hafta * 7 / 30);
    return IhbarSonucu(hafta: hafta, brut: brut, damgaVergisi: brut.carp(damgaOrani));
  }

  /// Yıllık izin hakkı (4857 s.K. m.53): 1–5 yıl 14, 5–15 yıl 20, 15 yıl ve üstü 26 gün;
  /// 18 yaş ve altı ile 50 yaş ve üstü en az 20 gün.
  static int yillikIzinHakki({required int kidemYili, required int yas}) {
    if (kidemYili < 1) return 0;
    final gun = kidemYili < 5 ? 14 : (kidemYili < 15 ? 20 : 26);
    return (yas <= 18 || yas >= 50) && gun < 20 ? 20 : gun;
  }

  /// Kullanılmayan izin ücreti (m.59): son çıplak brüt ücret üzerinden (giydirilmez).
  static IzinSonucu izinUcreti({required int kullanilmayanGun, required Para ciplakBrutUcret}) {
    if (kullanilmayanGun < 0) throw ArgumentError('Gün sayısı negatif olamaz.');
    return IzinSonucu(gun: kullanilmayanGun, brut: ciplakBrutUcret.carp(kullanilmayanGun / 30));
  }
}
