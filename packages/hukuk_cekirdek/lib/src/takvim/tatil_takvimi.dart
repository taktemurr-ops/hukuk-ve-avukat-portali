import 'tarih.dart';

/// Tatil türü.
enum TatilTuru {
  /// Ulusal bayram veya genel tatil (tam gün).
  resmiTatil,

  /// Ramazan veya Kurban Bayramı günü (tam gün).
  diniBayram,

  /// Arife veya 28 Ekim gibi öğleden sonra başlayan yarım gün tatil.
  yarimGun,
}

/// Takvimdeki tek bir tatil günü.
class TatilGunu {
  const TatilGunu({required this.tarih, required this.ad, required this.tur});

  final Tarih tarih;
  final String ad;
  final TatilTuru tur;

  bool get tamGun => tur != TatilTuru.yarimGun;

  @override
  String toString() => '${tarih.turkceBicim} $ad';
}

/// Süre hesabında kullanılan tatil takvimi.
///
/// Tatil günleri referans veridir ve avukat onayıyla güncellenir.
class TatilTakvimi {
  /// Aynı güne iki kayıt düşerse tam gün tatil, yarım gün tatile üstün gelir.
  TatilTakvimi(Iterable<TatilGunu> gunler) {
    for (final g in gunler) {
      final mevcut = _gunler[g.tarih];
      if (mevcut == null || (!mevcut.tamGun && g.tamGun)) {
        _gunler[g.tarih] = g;
      }
    }
  }

  final Map<Tarih, TatilGunu> _gunler = {};

  /// Verilen tarihteki tatil kaydı; yoksa `null`.
  TatilGunu? tatil(Tarih tarih) => _gunler[tarih];

  /// Takvimde kaydı olan yılları döner (veri eksikliğini yakalamak için).
  Set<int> get kapsananYillar => _gunler.keys.map((t) => t.yil).toSet();

  Iterable<TatilGunu> get tumGunler {
    final liste = _gunler.values.toList()..sort((a, b) => a.tarih.compareTo(b.tarih));
    return liste;
  }
}
