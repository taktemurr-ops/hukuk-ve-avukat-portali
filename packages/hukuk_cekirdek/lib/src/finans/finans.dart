import '../hesaplama/para.dart';
import '../takvim/tarih.dart';

/// Serbest meslek makbuzu tutarları.
class MakbuzHesabi {
  const MakbuzHesabi({required this.brut, required this.kdv, required this.stopaj});

  /// Brüt ücretten: KDV brüt üzerinden eklenir; müvekkil tevkifat sorumlusuysa (şirket, kamu)
  /// gelir vergisi stopajı brütten kesilir (GVK m.94; KDV %20, stopaj %20 — ONAY BEKLİYOR).
  factory MakbuzHesabi.bruttenHesapla(Para brut, {double kdvOrani = 20, bool stopajVar = true, double stopajOrani = 20}) =>
      MakbuzHesabi(
        brut: brut,
        kdv: brut.carp(kdvOrani / 100),
        stopaj: stopajVar ? brut.carp(stopajOrani / 100) : Para.sifir,
      );

  /// Avukatın eline geçmesi istenen net ücretten brüte ulaşır.
  factory MakbuzHesabi.nettenHesapla(Para net, {double kdvOrani = 20, bool stopajVar = true, double stopajOrani = 20}) {
    final brut = stopajVar ? net.carp(1 / (1 - stopajOrani / 100)) : net;
    return MakbuzHesabi.bruttenHesapla(brut, kdvOrani: kdvOrani, stopajVar: stopajVar, stopajOrani: stopajOrani);
  }

  final Para brut;
  final Para kdv;
  final Para stopaj;

  /// Gelir vergisi kesintisi sonrası avukata kalan ücret (KDV hariç).
  Para get netUcret => brut - stopaj;

  /// Müvekkilin avukata ödeyeceği toplam.
  Para get tahsilEdilecek => brut + kdv - stopaj;
}

enum CariHareketTuru {
  masrafAvansiAlindi('Masraf avansı alındı', 1),
  masrafYapildi('Masraf yapıldı', -1),
  avansIadesi('Avans iadesi', -1),
  ucretTahakkuku('Vekâlet ücreti tahakkuku', 0),
  ucretTahsilati('Ücret tahsilatı', 0);

  const CariHareketTuru(this.ad, this.avansEtkisi);

  final String ad;

  /// Masraf avansı bakiyesine etkisi (+1 / -1 / 0).
  final int avansEtkisi;
}

class CariHareket {
  const CariHareket({
    required this.id,
    required this.muvekkilId,
    required this.tur,
    required this.tutar,
    required this.tarih,
    required this.aciklama,
    this.dosyaId,
    this.belge,
  });

  final String id;
  final String muvekkilId;
  final String? dosyaId;
  final CariHareketTuru tur;
  final Para tutar;
  final Tarih tarih;
  final String aciklama;

  /// Makbuz, dekont veya harç makbuzu numarası.
  final String? belge;
}

/// Bir müvekkilin cari durumu.
class CariOzet {
  CariOzet(Iterable<CariHareket> hareketler) {
    for (final h in hareketler) {
      if (h.tutar.negatif) throw ArgumentError('Hareket tutarı negatif olamaz; türünü seçin.');
      switch (h.tur) {
        case CariHareketTuru.masrafAvansiAlindi:
          avansBakiyesi = avansBakiyesi + h.tutar;
        case CariHareketTuru.masrafYapildi:
          avansBakiyesi = avansBakiyesi - h.tutar;
          toplamMasraf = toplamMasraf + h.tutar;
        case CariHareketTuru.avansIadesi:
          avansBakiyesi = avansBakiyesi - h.tutar;
        case CariHareketTuru.ucretTahakkuku:
          ucretAlacagi = ucretAlacagi + h.tutar;
        case CariHareketTuru.ucretTahsilati:
          ucretAlacagi = ucretAlacagi - h.tutar;
      }
    }
  }

  /// Müvekkilden alınan ve henüz harcanmamış masraf avansı. Negatifse büro müvekkil adına masraf yapmış demektir.
  Para avansBakiyesi = Para.sifir;
  Para toplamMasraf = Para.sifir;

  /// Tahakkuk etmiş ama tahsil edilmemiş vekâlet ücreti.
  Para ucretAlacagi = Para.sifir;

  bool avansYetersiz(Para esik) => avansBakiyesi < esik;
}

enum EmanetHareketTuru {
  giris('Müvekkil adına tahsilat'),
  muvekkileAktarim('Müvekkile aktarım'),
  ucretMahsubu('Ücretle mahsup');

  const EmanetHareketTuru(this.ad);

  final String ad;
}

class EmanetHareketi {
  const EmanetHareketi({
    required this.id,
    required this.muvekkilId,
    required this.dosyaId,
    required this.tur,
    required this.tutar,
    required this.tarih,
    required this.aciklama,
    this.mahsupOnayi,
  });

  final String id;
  final String muvekkilId;
  final String dosyaId;
  final EmanetHareketTuru tur;
  final Para tutar;
  final Tarih tarih;
  final String aciklama;

  /// Ücretle mahsupta müvekkilin yazılı onayı veya sözleşme maddesi referansı.
  final String? mahsupOnayi;
}

/// Müvekkil parası (ör. icra tahsilatı) büro gelirinden ayrı izlenir.
///
/// Kurallar: bakiye eksiye düşemez; ücretle mahsup belgelenmiş onay ister;
/// uzun süre bekleyen emanet uyarı üretir.
class EmanetHesabi {
  EmanetHesabi({this.beklemeUyariGunu = 15});

  final int beklemeUyariGunu;
  final List<EmanetHareketi> _hareketler = [];

  List<EmanetHareketi> get hareketler => List.unmodifiable(_hareketler);

  Para bakiye(String muvekkilId, {String? dosyaId}) {
    var b = Para.sifir;
    for (final h in _hareketler.where((h) => h.muvekkilId == muvekkilId && (dosyaId == null || h.dosyaId == dosyaId))) {
      b = h.tur == EmanetHareketTuru.giris ? b + h.tutar : b - h.tutar;
    }
    return b;
  }

  void ekle(EmanetHareketi h) {
    if (h.tutar.negatif || h.tutar.sifirMi) throw ArgumentError('Tutar sıfırdan büyük olmalıdır.');
    if (h.tur != EmanetHareketTuru.giris) {
      if (h.tutar > bakiye(h.muvekkilId, dosyaId: h.dosyaId)) {
        throw StateError('Emanet bakiyesi yetersiz: müvekkil parası eksiye düşemez.');
      }
      if (h.tur == EmanetHareketTuru.ucretMahsubu && (h.mahsupOnayi == null || h.mahsupOnayi!.trim().isEmpty)) {
        throw StateError('Ücretle mahsup için müvekkil onayı veya sözleşme dayanağı girilmelidir.');
      }
    }
    _hareketler.add(h);
  }

  /// Bakiyesi olan ve son girişinden bu yana [beklemeUyariGunu] günden fazla geçen müvekkil/dosya çiftleri.
  List<(String muvekkilId, String dosyaId, Para bakiye, int gun)> bekleyenler(Tarih bugun) {
    final anahtarlar = {for (final h in _hareketler) (h.muvekkilId, h.dosyaId)};
    final sonuc = <(String, String, Para, int)>[];
    for (final (m, d) in anahtarlar) {
      final b = bakiye(m, dosyaId: d);
      if (!(b > Para.sifir)) continue;
      final sonGiris = _hareketler
          .where((h) => h.muvekkilId == m && h.dosyaId == d && h.tur == EmanetHareketTuru.giris)
          .map((h) => h.tarih)
          .reduce((a, c) => a.isAfter(c) ? a : c);
      final gun = sonGiris.farkGun(bugun);
      if (gun > beklemeUyariGunu) sonuc.add((m, d, b, gun));
    }
    return sonuc;
  }
}
