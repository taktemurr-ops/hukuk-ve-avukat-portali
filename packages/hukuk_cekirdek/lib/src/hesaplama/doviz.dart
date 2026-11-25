import '../takvim/tarih.dart';
import 'para.dart';

/// Yabancı para borcunun Türk lirası karşılığı (TBK m.99).
///
/// Borç, ödeme günündeki rayiç üzerinden Türk parasıyla ödenebilir. Borçlu temerrüde düşmüşse alacaklı, vade
/// günü ya da fiili ödeme günü kurundan birini seçebilir; hesap alacaklı lehine yüksek olanı gösterir.
/// Kurlar kullanıcı tarafından girilir (TCMB döviz satış kuru önerilir); uygulama kur çekmez.
class DovizHesabi {
  DovizHesabi._();

  static Para tlKarsiligi(Para dovizTutari, double kur) {
    if (dovizTutari.birim == 'TRY') throw ArgumentError('Tutar yabancı para olmalı.');
    if (kur <= 0) throw ArgumentError('Kur sıfırdan büyük olmalı.');
    return Para.kurus((dovizTutari.kurus * kur).round());
  }

  /// Seçilen kur ve gerekçesi.
  static (Para tl, String secim) borcKarsiligi({
    required Para dovizTutari,
    required double vadeKuru,
    required double odemeKuru,
    required bool temerrut,
  }) {
    final odeme = tlKarsiligi(dovizTutari, odemeKuru);
    if (!temerrut) return (odeme, 'Ödeme günü kuru');
    final vade = tlKarsiligi(dovizTutari, vadeKuru);
    return vade > odeme ? (vade, 'Vade günü kuru (alacaklının seçimi)') : (odeme, 'Ödeme günü kuru (alacaklının seçimi)');
  }

  /// Yabancı para alacağına temerrüt faizi (3095 s.K. m.4/a): devlet bankalarının o para birimiyle bir yıllık
  /// mevduata uyguladığı en yüksek faiz. Oran kullanıcıdan alınır. Basit faiz, gün/365; sonuç döviz cinsindendir.
  static Para temerrutFaizi({
    required Para dovizTutari,
    required double yillikOran,
    required Tarih baslangic,
    required Tarih bitis,
  }) {
    if (yillikOran < 0) throw ArgumentError('Oran negatif olamaz.');
    final gun = baslangic.farkGun(bitis);
    if (gun <= 0) return Para.kurus(0, birim: dovizTutari.birim);
    return dovizTutari.carp(yillikOran / 100 * gun / 365);
  }
}
