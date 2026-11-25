import '../hesaplama/para.dart';
import '../takvim/tarih.dart';
import 'hesap_turu.dart';

/// Fiyatlar TASLAKTIR; lansmanda kurucu tarafından kesinleştirilecek (KDV hariç).
enum FiyatTuru { sabit, koltukBasi, teklif }

enum OdemeDonemi {
  aylik('Aylık', 1),
  yillik('Yıllık', 12);

  const OdemeDonemi(this.ad, this.ay);
  final String ad;
  final int ay;
}

class Paket {
  const Paket({
    required this.hesapTuru,
    required this.fiyatTuru,
    required this.aylikFiyat,
    this.dahilKoltuk = 1,
  });

  final HesapTuru hesapTuru;
  final FiyatTuru fiyatTuru;

  /// Sabit pakette aylık toplam, koltuk başı pakette bir ücretli kullanıcının aylığı.
  final Para aylikFiyat;
  final int dahilKoltuk;

  /// Yıllık ödemede 12 ay yerine 10 ay ücret alınır.
  static const yillikOdenenAy = 10;

  static final taslakPaketler = <HesapTuru, Paket>{
    HesapTuru.avukatlikBurosu: Paket(
        hesapTuru: HesapTuru.avukatlikBurosu, fiyatTuru: FiyatTuru.sabit, aylikFiyat: Para.tl(1000)),
    HesapTuru.hukukBurosu: Paket(
        hesapTuru: HesapTuru.hukukBurosu, fiyatTuru: FiyatTuru.koltukBasi, aylikFiyat: Para.tl(1500)),
    HesapTuru.kurumsal: Paket(
        hesapTuru: HesapTuru.kurumsal, fiyatTuru: FiyatTuru.teklif, aylikFiyat: Para.tl(0)),
  };

  /// Bir dönemin KDV hariç tutarı. Teklif usulü pakette hesaplanmaz.
  Para donemTutari(OdemeDonemi donem, {int ucretliKoltuk = 1}) {
    if (fiyatTuru == FiyatTuru.teklif) {
      throw StateError('Kurumsal paket teklif usulüdür; tutar sözleşmeden gelir.');
    }
    final ay = donem == OdemeDonemi.yillik ? yillikOdenenAy : 1;
    final carpan = fiyatTuru == FiyatTuru.koltukBasi ? (ucretliKoltuk < 1 ? 1 : ucretliKoltuk) : 1;
    return aylikFiyat.carp(ay * carpan);
  }
}

class FaturaTutari {
  const FaturaTutari(this.matrah, this.kdv);
  final Para matrah;
  final Para kdv;
  Para get toplam => matrah + kdv;

  static const kdvOrani = 0.20;
  factory FaturaTutari.hesapla(Para matrah) => FaturaTutari(matrah, matrah.carp(kdvOrani));
}

enum AbonelikDurumu {
  deneme('Deneme'),
  aktif('Aktif'),
  odemeBekliyor('Ödeme bekliyor'),
  askida('Askıda — salt okunur'),
  iptal('İptal edildi');

  const AbonelikDurumu(this.ad);
  final String ad;
}

/// Abonelik yaşam döngüsü: deneme → aktif → (başarısız ödeme) → ödeme bekliyor → askıda.
/// Askıda veya iptal sonrası veriler silinmez; kullanıcı salt okunur erişir ve dışa aktarabilir.
class Abonelik {
  Abonelik._(this.paket, this.donem, this.baslangic)
      : durum = AbonelikDurumu.deneme,
        donemBasi = baslangic,
        donemSonu = baslangic.gunEkle(denemeGun);

  factory Abonelik.denemeBaslat(Paket paket, Tarih bugun, {OdemeDonemi donem = OdemeDonemi.aylik}) =>
      Abonelik._(paket, donem, bugun);

  static const denemeGun = 14;

  /// Başarısız ödeme sonrası tekrar deneme günleri (ilk hatadan itibaren).
  static const tekrarDenemeGunleri = [1, 3, 7];

  final Paket paket;
  OdemeDonemi donem;
  final Tarih baslangic;
  AbonelikDurumu durum;
  Tarih donemBasi;
  Tarih donemSonu;
  int ucretliKoltuk = 1;
  Tarih? ilkBasarisizOdeme;
  bool donemSonundaIptal = false;

  bool get yazilabilir => durum == AbonelikDurumu.deneme || durum == AbonelikDurumu.aktif ||
      durum == AbonelikDurumu.odemeBekliyor;

  /// Ödeme başarılı: yeni dönem başlar (önceki dönem sonundan veya bugünden, hangisi geçse).
  void odemeAlindi(Tarih bugun) {
    if (durum == AbonelikDurumu.iptal) throw StateError('İptal edilmiş abonelik yeniden ödenemez.');
    final esas = bugun.farkGun(donemSonu) > 0 ? donemSonu : bugun;
    final yeniBaslangic = durum == AbonelikDurumu.deneme ? bugun : esas;
    donemBasi = yeniBaslangic;
    donemSonu = yeniBaslangic.ayEkle(donem.ay);
    durum = AbonelikDurumu.aktif;
    ilkBasarisizOdeme = null;
  }

  void odemeBasarisiz(Tarih bugun) {
    if (durum == AbonelikDurumu.iptal) return;
    ilkBasarisizOdeme ??= bugun;
    durum = AbonelikDurumu.odemeBekliyor;
  }

  /// Bir sonraki tekrar deneme tarihi; denemeler bittiyse null.
  Tarih? sonrakiDeneme(Tarih bugun) {
    final ilk = ilkBasarisizOdeme;
    if (ilk == null) return null;
    for (final g in tekrarDenemeGunleri) {
      final t = ilk.gunEkle(g);
      if (bugun.farkGun(t) > 0) return t;
    }
    return null;
  }

  /// Günlük çalışan iş: süresi dolan deneme, biten tekrar denemeler, dönem sonu iptalleri.
  void gunlukKontrol(Tarih bugun) {
    if (durum == AbonelikDurumu.deneme && bugun.farkGun(donemSonu) <= 0) {
      durum = AbonelikDurumu.askida;
    } else if (durum == AbonelikDurumu.odemeBekliyor && ilkBasarisizOdeme != null &&
        ilkBasarisizOdeme!.farkGun(bugun) > tekrarDenemeGunleri.last) {
      durum = AbonelikDurumu.askida;
    } else if (donemSonundaIptal && durum == AbonelikDurumu.aktif && bugun.farkGun(donemSonu) <= 0) {
      durum = AbonelikDurumu.iptal;
    }
  }

  /// İptal dönem sonunda geçerli olur; o güne kadar kullanım sürer.
  void iptalEt() => donemSonundaIptal = true;

  /// Koltuk artışında kalan gün oranında fark faturası (KDV hariç). Azalış bir sonraki dönemde geçerlidir.
  Para koltukDegistir(int yeniKoltuk, Tarih bugun) {
    if (paket.fiyatTuru != FiyatTuru.koltukBasi) {
      throw StateError('Bu pakette koltuk sayısı değiştirilemez.');
    }
    if (yeniKoltuk < 1) throw ArgumentError('En az bir ücretli kullanıcı olmalı.');
    final fark = yeniKoltuk - ucretliKoltuk;
    ucretliKoltuk = yeniKoltuk;
    if (fark <= 0 || durum != AbonelikDurumu.aktif) return Para.sifir;
    final toplamGun = donemBasi.farkGun(donemSonu);
    final kalanGun = bugun.farkGun(donemSonu);
    if (kalanGun <= 0) return Para.sifir;
    return paket.donemTutari(donem, ucretliKoltuk: fark).carp(kalanGun / toplamGun);
  }
}
