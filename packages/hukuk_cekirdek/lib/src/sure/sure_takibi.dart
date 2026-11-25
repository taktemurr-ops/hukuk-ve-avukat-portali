import '../takvim/tarih.dart';
import 'sure_hesaplayici.dart';

enum SureDurumu {
  teyitBekliyor('Teyit bekliyor'),
  teyitli('Teyitli'),
  tamamlandi('Tamamlandı'),
  iptal('İptal');

  const SureDurumu(this.ad);

  final String ad;
}

/// Önceki hesap; yeniden hesaplamada silinmez.
class OncekiHesap {
  const OncekiHesap({required this.sonGun, required this.kuralKodu, required this.neden, required this.tarih});

  final Tarih sonGun;
  final String kuralKodu;
  final String neden;
  final Tarih tarih;
}

/// Bir dosyadaki kritik süre ve yaşam döngüsü.
///
/// Kurallar:
/// - Her sürenin asıl sorumlusu olmalı; yedek sorumlu asıldan farklı olmalı.
/// - Kesin sürede teyit, hesabı oluşturandan farklı bir hukukçu tarafından yapılır.
/// - Süre ancak teyitli ise ve bir kanıtla (işlem no, makbuz, belge) tamamlanır.
/// - Yeniden hesaplamada eski hesap saklanır ve teyit yeniden istenir.
class SureKaydi {
  SureKaydi({
    required this.id,
    required this.dosyaId,
    required this.aciklama,
    required this.sonuc,
    required this.olusturan,
    required this.olusturmaTarihi,
    required this.asilSorumlu,
    this.yedekSorumlu,
    this.kesinSure = true,
    this.tetikleyenTebligatId,
    this.durum = SureDurumu.teyitBekliyor,
    this.teyitEden,
    this.teyitTarihi,
    this.tamamlanmaKaniti,
    this.oncekiHesaplar = const [],
  }) {
    if (yedekSorumlu != null && yedekSorumlu == asilSorumlu) {
      throw ArgumentError('Yedek sorumlu, asıl sorumludan farklı olmalıdır.');
    }
  }

  final String id;
  final String dosyaId;
  final String aciklama;
  final SureSonucu sonuc;
  final String olusturan;
  final Tarih olusturmaTarihi;

  /// Boş ise süre "sahipsiz" sayılır ve yöneticiye eskale edilir.
  final String asilSorumlu;
  final String? yedekSorumlu;
  final bool kesinSure;
  final String? tetikleyenTebligatId;
  final SureDurumu durum;
  final String? teyitEden;
  final Tarih? teyitTarihi;
  final String? tamamlanmaKaniti;
  final List<OncekiHesap> oncekiHesaplar;

  Tarih get sonGun => sonuc.sonGun;
  bool get sahipsiz => asilSorumlu.trim().isEmpty;
  bool get acik => durum == SureDurumu.teyitBekliyor || durum == SureDurumu.teyitli;

  int kalanGun(Tarih bugun) => bugun.farkGun(sonGun);

  SureKaydi teyitEt({required String kullanici, required Tarih tarih}) {
    if (durum != SureDurumu.teyitBekliyor) {
      throw StateError('Yalnızca teyit bekleyen süre teyit edilebilir.');
    }
    if (kesinSure && kullanici == olusturan) {
      throw StateError('Kesin süre, hesabı oluşturandan farklı bir hukukçu tarafından teyit edilmelidir.');
    }
    return _kopya(durum: SureDurumu.teyitli, teyitEden: kullanici, teyitTarihi: tarih);
  }

  SureKaydi tamamla({required String kanit}) {
    if (durum != SureDurumu.teyitli) throw StateError('Teyit edilmemiş süre tamamlanamaz.');
    if (kanit.trim().isEmpty) throw ArgumentError('Tamamlama için kanıt (işlem no, makbuz, belge) gerekir.');
    return _kopya(durum: SureDurumu.tamamlandi, tamamlanmaKaniti: kanit.trim());
  }

  /// Yeni evrak, kural değişikliği veya hata düzeltmesinde: eski hesap saklanır, teyit sıfırlanır.
  SureKaydi yenidenHesapla({required SureSonucu yeniSonuc, required String neden, required String kullanici, required Tarih tarih}) {
    if (!acik) throw StateError('Kapanmış süre yeniden hesaplanamaz.');
    if (neden.trim().isEmpty) throw ArgumentError('Yeniden hesaplama nedeni zorunludur.');
    return SureKaydi(
      id: id,
      dosyaId: dosyaId,
      aciklama: aciklama,
      sonuc: yeniSonuc,
      olusturan: kullanici,
      olusturmaTarihi: tarih,
      asilSorumlu: asilSorumlu,
      yedekSorumlu: yedekSorumlu,
      kesinSure: kesinSure,
      tetikleyenTebligatId: tetikleyenTebligatId,
      oncekiHesaplar: [
        ...oncekiHesaplar,
        OncekiHesap(sonGun: sonGun, kuralKodu: sonuc.kural.kod, neden: neden.trim(), tarih: tarih),
      ],
    );
  }

  SureKaydi sorumluDegistir({required String asil, String? yedek}) => SureKaydi(
        id: id,
        dosyaId: dosyaId,
        aciklama: aciklama,
        sonuc: sonuc,
        olusturan: olusturan,
        olusturmaTarihi: olusturmaTarihi,
        asilSorumlu: asil,
        yedekSorumlu: yedek,
        kesinSure: kesinSure,
        tetikleyenTebligatId: tetikleyenTebligatId,
        durum: durum,
        teyitEden: teyitEden,
        teyitTarihi: teyitTarihi,
        tamamlanmaKaniti: tamamlanmaKaniti,
        oncekiHesaplar: oncekiHesaplar,
      );

  SureKaydi iptalEt() => _kopya(durum: SureDurumu.iptal);

  SureKaydi _kopya({SureDurumu? durum, String? teyitEden, Tarih? teyitTarihi, String? tamamlanmaKaniti}) => SureKaydi(
        id: id,
        dosyaId: dosyaId,
        aciklama: aciklama,
        sonuc: sonuc,
        olusturan: olusturan,
        olusturmaTarihi: olusturmaTarihi,
        asilSorumlu: asilSorumlu,
        yedekSorumlu: yedekSorumlu,
        kesinSure: kesinSure,
        tetikleyenTebligatId: tetikleyenTebligatId,
        durum: durum ?? this.durum,
        teyitEden: teyitEden ?? this.teyitEden,
        teyitTarihi: teyitTarihi ?? this.teyitTarihi,
        tamamlanmaKaniti: tamamlanmaKaniti ?? this.tamamlanmaKaniti,
        oncekiHesaplar: oncekiHesaplar,
      );
}

enum UyariSeviyesi {
  hatirlatma('Hatırlatma'),
  yedekSorumlu('Yedek sorumluya'),
  yonetici('Yöneticiye'),
  kritik('Kritik');

  const UyariSeviyesi(this.ad);

  final String ad;
}

class SureUyarisi {
  const SureUyarisi({required this.sure, required this.seviye, required this.mesaj, required this.alicilar});

  final SureKaydi sure;
  final UyariSeviyesi seviye;
  final String mesaj;

  /// Kullanıcı kimlikleri; `yonetici` özel alıcısı dosyanın yöneticisini temsil eder.
  final Set<String> alicilar;
}

/// Hiçbir kritik sürenin sahipsiz ve teyitsiz kalmaması için günlük değerlendirme.
class EskalasyonMotoru {
  const EskalasyonMotoru({
    this.hatirlatmaGunleri = const {7, 3, 1},
    this.teyitIcinGun = 1,
    this.yoneticiAlicisi = 'yonetici',
  });

  /// Son güne bu kadar gün kala asıl sorumluya hatırlatma.
  final Set<int> hatirlatmaGunleri;

  /// Bu kadar gün içinde teyit edilmeyen süre yöneticiye çıkar.
  final int teyitIcinGun;
  final String yoneticiAlicisi;

  List<SureUyarisi> degerlendir(Iterable<SureKaydi> sureler, Tarih bugun) {
    final uyarilar = <SureUyarisi>[];
    for (final s in sureler.where((s) => s.acik)) {
      final kalan = s.kalanGun(bugun);
      final ekip = {if (!s.sahipsiz) s.asilSorumlu, if (s.yedekSorumlu != null) s.yedekSorumlu!};

      if (kalan < 0) {
        uyarilar.add(SureUyarisi(
          sure: s,
          seviye: UyariSeviyesi.kritik,
          mesaj: '${s.aciklama}: son gün ${s.sonGun.turkceBicim} geçti, işlem kaydı yok.',
          alicilar: {...ekip, yoneticiAlicisi},
        ));
        continue;
      }
      if (s.sahipsiz) {
        uyarilar.add(SureUyarisi(
          sure: s,
          seviye: UyariSeviyesi.yonetici,
          mesaj: '${s.aciklama}: sorumlu atanmamış.',
          alicilar: {yoneticiAlicisi},
        ));
      }
      if (s.durum == SureDurumu.teyitBekliyor) {
        final bekleme = s.olusturmaTarihi.farkGun(bugun);
        if (bekleme >= teyitIcinGun || kalan <= 3) {
          uyarilar.add(SureUyarisi(
            sure: s,
            seviye: UyariSeviyesi.yonetici,
            mesaj: '${s.aciklama}: hesap $bekleme gündür teyit edilmedi (son gün ${s.sonGun.turkceBicim}).',
            alicilar: {...ekip, yoneticiAlicisi},
          ));
          continue;
        }
      }
      if (kalan == 0) {
        uyarilar.add(SureUyarisi(
          sure: s,
          seviye: UyariSeviyesi.yonetici,
          mesaj: '${s.aciklama}: son gün bugün.',
          alicilar: {...ekip, yoneticiAlicisi},
        ));
      } else if (kalan == 1 && s.yedekSorumlu != null) {
        uyarilar.add(SureUyarisi(
          sure: s,
          seviye: UyariSeviyesi.yedekSorumlu,
          mesaj: '${s.aciklama}: son gün yarın.',
          alicilar: ekip,
        ));
      } else if (hatirlatmaGunleri.contains(kalan) && !s.sahipsiz) {
        uyarilar.add(SureUyarisi(
          sure: s,
          seviye: UyariSeviyesi.hatirlatma,
          mesaj: '${s.aciklama}: son güne $kalan gün kaldı.',
          alicilar: {s.asilSorumlu},
        ));
      }
    }
    uyarilar.sort((a, b) {
      final seviye = b.seviye.index.compareTo(a.seviye.index);
      return seviye != 0 ? seviye : a.sure.sonGun.compareTo(b.sure.sonGun);
    });
    return uyarilar;
  }
}

class DevirKalemi {
  const DevirKalemi({required this.sure, required this.rol, required this.devralabilir});

  final SureKaydi sure;

  /// "asıl" veya "yedek"
  final String rol;

  /// Diğer sorumlu (yedek veya asıl) aktifse önerilen devralan; yoksa `null` = kritik.
  final String? devralabilir;

  bool get kritik => devralabilir == null;
}

/// İzin veya işten ayrılışta kullanıcının açık sürelerinin devir listesi.
class DevirListesi {
  DevirListesi._();

  static List<DevirKalemi> olustur({
    required String ayrilan,
    required Iterable<SureKaydi> sureler,
    Set<String> pasifKullanicilar = const {},
  }) {
    final pasif = {...pasifKullanicilar, ayrilan};
    final liste = <DevirKalemi>[];
    for (final s in sureler.where((s) => s.acik)) {
      if (s.asilSorumlu == ayrilan) {
        final y = s.yedekSorumlu;
        liste.add(DevirKalemi(sure: s, rol: 'asıl', devralabilir: y != null && !pasif.contains(y) ? y : null));
      } else if (s.yedekSorumlu == ayrilan) {
        liste.add(DevirKalemi(
            sure: s, rol: 'yedek', devralabilir: !pasif.contains(s.asilSorumlu) ? s.asilSorumlu : null));
      }
    }
    liste.sort((a, b) {
      if (a.kritik != b.kritik) return a.kritik ? -1 : 1;
      return a.sure.sonGun.compareTo(b.sure.sonGun);
    });
    return liste;
  }
}
