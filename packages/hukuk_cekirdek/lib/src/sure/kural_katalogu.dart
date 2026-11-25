import '../takvim/tarih.dart';
import 'sure_kurali.dart';

/// Başlangıç süre kuralları.
///
/// TÜMÜ TASLAKTIR. Ekipteki avukat her kuralın süresini, dayanağını ve
/// adli tatil durumunu kontrol edip onaylamadan canlıda kullanılmaz.
/// Canlı ortamda kurallar veritabanında sürümlü tutulur; bu liste ilk tohum verisidir.
class KuralKatalogu {
  KuralKatalogu._();

  static final Tarih _tohum = Tarih(2011, 10, 1);

  static final List<SureKurali> tohumKurallar = [
    SureKurali(
      kod: 'HMK_CEVAP_DILEKCESI',
      ad: 'Cevap dilekçesi süresi',
      miktar: 2,
      birim: SureBirimi.hafta,
      yargiKolu: YargiKolu.hukuk,
      dayanak: 'HMK m.127',
      adliTatildeUzar: true,
      surum: 1,
      yururlukTarihi: _tohum,
      aciklama: 'Dava dilekçesinin tebliğinden itibaren. Ek süre kararı ayrıca girilir.',
    ),
    SureKurali(
      kod: 'HMK_ISTINAF',
      ad: 'İstinaf başvuru süresi',
      miktar: 2,
      birim: SureBirimi.hafta,
      yargiKolu: YargiKolu.hukuk,
      dayanak: 'HMK m.345',
      adliTatildeUzar: true,
      surum: 1,
      yururlukTarihi: _tohum,
      aciklama: 'Gerekçeli kararın tebliğinden itibaren.',
    ),
    SureKurali(
      kod: 'IIK_ODEME_EMRINE_ITIRAZ',
      ad: 'Ödeme emrine itiraz süresi',
      miktar: 7,
      birim: SureBirimi.gun,
      yargiKolu: YargiKolu.icra,
      dayanak: 'İİK m.62',
      adliTatildeUzar: false,
      surum: 1,
      yururlukTarihi: Tarih(1932, 6, 19),
      aciklama: 'İlamsız takipte ödeme emrinin tebliğinden itibaren. İcra tatil kuralları avukatça netleştirilecek.',
    ),
    SureKurali(
      kod: 'IYUK_DAVA_ACMA',
      ad: 'İdari dava açma süresi',
      miktar: 60,
      birim: SureBirimi.gun,
      yargiKolu: YargiKolu.idari,
      dayanak: 'İYUK m.7',
      adliTatildeUzar: true,
      surum: 1,
      yururlukTarihi: Tarih(1982, 1, 20),
      aciklama: 'Özel kanunlarda ayrı süre yoksa; vergi davalarında 30 gün. Adli tatil durumu avukatça teyit edilecek.',
    ),
    SureKurali(
      kod: 'IS_K_ISE_IADE_ARABULUCU',
      ad: 'İşe iade için arabulucuya başvuru süresi',
      miktar: 1,
      birim: SureBirimi.ay,
      yargiKolu: YargiKolu.arabuluculuk,
      dayanak: 'İş Kanunu m.20',
      adliTatildeUzar: false,
      surum: 1,
      yururlukTarihi: Tarih(2018, 1, 1),
      aciklama: 'Fesih bildiriminin tebliğinden itibaren. Hak düşürücü süredir.',
    ),
  ];

  static SureKurali? bul(String kod) {
    for (final k in tohumKurallar) {
      if (k.kod == kod) return k;
    }
    return null;
  }
}
