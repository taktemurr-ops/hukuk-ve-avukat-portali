import 'isim_eslestirme.dart';
import 'kisi.dart';

/// Bir kişinin bir dosyadaki sıfatı.
enum TarafSifati { muvekkil, karsiTaraf, diger }

/// Bir kişinin hangi dosyada hangi sıfatla yer aldığı.
class DosyaTarafKaydi {
  const DosyaTarafKaydi({
    required this.dosyaId,
    required this.dosyaAdi,
    required this.kisiId,
    required this.sifat,
    this.gizli = false,
    this.kapali = false,
  });

  final String dosyaId;
  final String dosyaAdi;
  final String kisiId;
  final TarafSifati sifat;

  /// Gizli veya etik duvarlı dosya; inceleme sırasında adı ve kimliği gösterilmez.
  final bool gizli;
  final bool kapali;
}

/// Yeni işte yer alacak taraf.
class AdayTaraf {
  const AdayTaraf({required this.ad, required this.sifat, this.kimlikNo});

  final String ad;
  final String? kimlikNo;

  /// Yeni işte müvekkil mi, karşı taraf mı olacak.
  final TarafSifati sifat;
}

enum EslesmeTuru { kimlikNo, tamIsim, benzerIsim, iliskiliKisi }

enum RiskSeviyesi {
  bilgi,
  dikkat,
  catisma;

  String get ad => switch (this) {
        RiskSeviyesi.bilgi => 'Bilgi',
        RiskSeviyesi.dikkat => 'Dikkat',
        RiskSeviyesi.catisma => 'Çatışma',
      };
}

/// İncelemeciye gösterilen dosya özeti; gizli dosyada ad ve kimlik maskelenir.
class DosyaOzeti {
  const DosyaOzeti({required this.dosyaId, required this.dosyaAdi, required this.sifat, required this.kapali});

  /// Gizli dosyada `null`.
  final String? dosyaId;
  final String dosyaAdi;
  final TarafSifati sifat;
  final bool kapali;

  static const String korumaliAd = 'Korumalı dosya';

  factory DosyaOzeti.kayittan(DosyaTarafKaydi k) => DosyaOzeti(
        dosyaId: k.gizli ? null : k.dosyaId,
        dosyaAdi: k.gizli ? korumaliAd : k.dosyaAdi,
        sifat: k.sifat,
        kapali: k.kapali,
      );
}

class Eslesme {
  const Eslesme({
    required this.aday,
    required this.kisiAdi,
    required this.tur,
    required this.benzerlik,
    required this.dosya,
    required this.seviye,
    this.iliski,
  });

  final AdayTaraf aday;
  final String kisiAdi;
  final EslesmeTuru tur;
  final double benzerlik;
  final DosyaOzeti? dosya;
  final RiskSeviyesi seviye;
  final IliskiTuru? iliski;
}

class CikarCatismasiRaporu {
  const CikarCatismasiRaporu(this.eslesmeler);

  final List<Eslesme> eslesmeler;

  RiskSeviyesi? get enYuksekSeviye => eslesmeler.isEmpty
      ? null
      : eslesmeler.map((e) => e.seviye).reduce((a, b) => a.index >= b.index ? a : b);

  bool get catismaVar => eslesmeler.any((e) => e.seviye == RiskSeviyesi.catisma);

  /// Dikkat veya çatışma varsa gerekçeli karar zorunludur.
  bool get kararGerekir => eslesmeler.any((e) => e.seviye != RiskSeviyesi.bilgi);
}

/// Yeni müvekkil ve dosya açılışında çıkar çatışması taraması.
class CikarCatismasiTarayici {
  CikarCatismasiTarayici({
    required this.kisiler,
    required this.iliskiler,
    required this.dosyaKayitlari,
    this.esik = IsimEslestirme.varsayilanEsik,
  });

  final List<Kisi> kisiler;
  final List<KisiIliskisi> iliskiler;
  final List<DosyaTarafKaydi> dosyaKayitlari;
  final double esik;

  CikarCatismasiRaporu tara(List<AdayTaraf> adaylar) {
    final sonuc = <Eslesme>[];
    final kisiById = {for (final k in kisiler) k.id: k};

    for (final aday in adaylar) {
      for (final kisi in kisiler) {
        final (tur, benzerlik) = _eslestir(aday, kisi);
        if (tur == null) continue;

        for (final kayit in dosyaKayitlari.where((d) => d.kisiId == kisi.id)) {
          var seviye = _seviye(aday.sifat, kayit.sifat);
          if (tur == EslesmeTuru.benzerIsim && seviye == RiskSeviyesi.catisma) {
            seviye = RiskSeviyesi.dikkat;
          }
          sonuc.add(Eslesme(
            aday: aday,
            kisiAdi: kisi.ad,
            tur: tur,
            benzerlik: benzerlik,
            dosya: DosyaOzeti.kayittan(kayit),
            seviye: seviye,
          ));
        }

        // Dolaylı: eşleşen kişinin ortakları, iştirakleri, yetkilileri...
        if (tur == EslesmeTuru.benzerIsim) continue;
        for (final iliski in iliskiler) {
          final digerId = iliski.karsiTaraf(kisi.id);
          final diger = digerId == null ? null : kisiById[digerId];
          if (diger == null) continue;
          for (final kayit in dosyaKayitlari.where((d) => d.kisiId == diger.id)) {
            if (_seviye(aday.sifat, kayit.sifat) != RiskSeviyesi.catisma) continue;
            sonuc.add(Eslesme(
              aday: aday,
              kisiAdi: diger.ad,
              tur: EslesmeTuru.iliskiliKisi,
              benzerlik: benzerlik,
              dosya: DosyaOzeti.kayittan(kayit),
              seviye: RiskSeviyesi.dikkat,
              iliski: iliski.tur,
            ));
          }
        }
      }
    }

    sonuc.sort((a, b) => b.seviye.index.compareTo(a.seviye.index));
    return CikarCatismasiRaporu(List.unmodifiable(sonuc));
  }

  (EslesmeTuru?, double) _eslestir(AdayTaraf aday, Kisi kisi) {
    final no = aday.kimlikNo?.trim();
    if (no != null && no.isNotEmpty && no == kisi.kimlikNo) return (EslesmeTuru.kimlikNo, 1.0);
    var enIyi = 0.0;
    for (final ad in kisi.tumAdlar) {
      final b = IsimEslestirme.benzerlik(aday.ad, ad);
      if (b > enIyi) enIyi = b;
    }
    if (enIyi >= 1.0) return (EslesmeTuru.tamIsim, 1.0);
    if (enIyi >= esik) return (EslesmeTuru.benzerIsim, enIyi);
    return (null, enIyi);
  }

  static RiskSeviyesi _seviye(TarafSifati yeni, TarafSifati mevcut) {
    final ters = (yeni == TarafSifati.muvekkil && mevcut == TarafSifati.karsiTaraf) ||
        (yeni == TarafSifati.karsiTaraf && mevcut == TarafSifati.muvekkil);
    return ters ? RiskSeviyesi.catisma : RiskSeviyesi.bilgi;
  }
}

enum KararTuru { kabul, kosulluKabul, ret }

/// İş kabul kararı. Gerekçe her zaman zorunlu; çatışmada yönetici onayı zorunlu.
class CikarCatismasiKarari {
  const CikarCatismasiKarari({
    required this.tur,
    required this.gerekce,
    required this.kararVeren,
    this.yoneticiOnayi,
    this.kosullar,
  });

  final KararTuru tur;
  final String gerekce;
  final String kararVeren;
  final String? yoneticiOnayi;

  /// Koşullu kabulde alınan önlemler (ör. etik duvar, müvekkilden yazılı muvafakat).
  final String? kosullar;

  /// Hata yoksa `null`.
  String? dogrula(CikarCatismasiRaporu rapor) {
    if (gerekce.trim().length < 10) return 'Gerekçe en az 10 karakter olmalıdır.';
    if (tur == KararTuru.kosulluKabul && (kosullar == null || kosullar!.trim().isEmpty)) {
      return 'Koşullu kabulde koşullar yazılmalıdır.';
    }
    if (rapor.catismaVar && tur != KararTuru.ret) {
      if (yoneticiOnayi == null || yoneticiOnayi!.trim().isEmpty) {
        return 'Çatışma varken kabul için yönetici onayı gerekir.';
      }
      if (yoneticiOnayi == kararVeren) {
        return 'Yönetici onayı karar verenden farklı bir kişi tarafından verilmelidir.';
      }
    }
    return null;
  }
}
