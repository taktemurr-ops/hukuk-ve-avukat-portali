import '../takvim/tarih.dart';
import 'onay_durumu.dart';

/// Sürenin ölçü birimi.
enum SureBirimi { gun, hafta, ay, yil }

/// Usul kanunlarına göre yargı kolu; adli tatil ve tatil kuralları buna göre değişir.
enum YargiKolu { hukuk, ceza, idari, icra, arabuluculuk, diger }

/// Bir hukuki sürenin kuralı.
///
/// Her kural; dayanağı, yürürlük tarihi, sürümü ve onay durumuyla saklanır.
/// Kural değişirse eski sürüm silinmez, eski hesaplar eski sürümle yeniden üretilebilir.
class SureKurali {
  const SureKurali({
    required this.kod,
    required this.ad,
    required this.miktar,
    required this.birim,
    required this.yargiKolu,
    required this.dayanak,
    required this.adliTatildeUzar,
    required this.surum,
    required this.yururlukTarihi,
    this.onayDurumu = OnayDurumu.taslak,
    this.onaylayan,
    this.aciklama,
  }) : assert(miktar > 0, 'Süre miktarı pozitif olmalı');

  /// Sistem içi benzersiz kod, ör. `HMK_ISTINAF`.
  final String kod;

  /// Kullanıcıya görünen ad, ör. "İstinaf başvuru süresi".
  final String ad;

  final int miktar;
  final SureBirimi birim;
  final YargiKolu yargiKolu;

  /// Kanun maddesi, ör. "HMK m.345".
  final String dayanak;

  /// Süre adli tatile denk gelirse adli tatil bitiminden itibaren bir hafta uzar mı.
  final bool adliTatildeUzar;

  final int surum;
  final Tarih yururlukTarihi;
  final OnayDurumu onayDurumu;

  /// Kuralı onaylayan avukatın adı veya kullanıcı kimliği.
  final String? onaylayan;
  final String? aciklama;

  bool get kullanilabilir => onayDurumu == OnayDurumu.onayli;

  String get sureMetni {
    final birimAdi = switch (birim) {
      SureBirimi.gun => 'gün',
      SureBirimi.hafta => 'hafta',
      SureBirimi.ay => 'ay',
      SureBirimi.yil => 'yıl',
    };
    return '$miktar $birimAdi';
  }

  SureKurali onayla(String avukat) => SureKurali(
        kod: kod,
        ad: ad,
        miktar: miktar,
        birim: birim,
        yargiKolu: yargiKolu,
        dayanak: dayanak,
        adliTatildeUzar: adliTatildeUzar,
        surum: surum,
        yururlukTarihi: yururlukTarihi,
        onayDurumu: OnayDurumu.onayli,
        onaylayan: avukat,
        aciklama: aciklama,
      );
}
