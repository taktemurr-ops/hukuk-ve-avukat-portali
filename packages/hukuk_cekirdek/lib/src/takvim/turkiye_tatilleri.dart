import 'tarih.dart';
import 'tatil_takvimi.dart';

/// Türkiye resmi tatil takvimi (2429 sayılı Kanun ve Diyanet dini günler takvimi).
///
/// DİKKAT: Dini bayram tarihleri her yıl Diyanet takvimine göre girilir.
/// Bu dosyadaki dini bayram tarihleri avukat onayı bekleyen referans veridir;
/// canlı ortamda bu veri yönetim panelinden (referans veri modülü) yönetilecektir.
class TurkiyeTatilleri {
  TurkiyeTatilleri._();

  /// Sabit tarihli ulusal bayram ve genel tatiller.
  static List<TatilGunu> sabitTatiller(int yil) => [
        TatilGunu(tarih: Tarih(yil, 1, 1), ad: 'Yılbaşı', tur: TatilTuru.resmiTatil),
        TatilGunu(
            tarih: Tarih(yil, 4, 23), ad: 'Ulusal Egemenlik ve Çocuk Bayramı', tur: TatilTuru.resmiTatil),
        TatilGunu(tarih: Tarih(yil, 5, 1), ad: 'Emek ve Dayanışma Günü', tur: TatilTuru.resmiTatil),
        TatilGunu(
            tarih: Tarih(yil, 5, 19),
            ad: 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı',
            tur: TatilTuru.resmiTatil),
        TatilGunu(
            tarih: Tarih(yil, 7, 15),
            ad: 'Demokrasi ve Millî Birlik Günü',
            tur: TatilTuru.resmiTatil),
        TatilGunu(tarih: Tarih(yil, 8, 30), ad: 'Zafer Bayramı', tur: TatilTuru.resmiTatil),
        TatilGunu(tarih: Tarih(yil, 10, 28), ad: 'Cumhuriyet Bayramı arifesi', tur: TatilTuru.yarimGun),
        TatilGunu(tarih: Tarih(yil, 10, 29), ad: 'Cumhuriyet Bayramı', tur: TatilTuru.resmiTatil),
      ];

  /// Dini bayramlar: yıl -> (arife, bayram günleri).
  ///
  /// Kaynak: Diyanet İşleri Başkanlığı dini günler takvimi (basın aracılığıyla).
  /// ONAY BEKLİYOR: ekipteki avukat Diyanet'in resmi takvimiyle karşılaştırmalıdır.
  static final Map<int, List<_DiniBayram>> _diniBayramlar = {
    2026: [
      _DiniBayram('Ramazan Bayramı', Tarih(2026, 3, 19), [Tarih(2026, 3, 20), Tarih(2026, 3, 21), Tarih(2026, 3, 22)]),
      _DiniBayram('Kurban Bayramı', Tarih(2026, 5, 26),
          [Tarih(2026, 5, 27), Tarih(2026, 5, 28), Tarih(2026, 5, 29), Tarih(2026, 5, 30)]),
    ],
    2027: [
      _DiniBayram('Ramazan Bayramı', Tarih(2027, 3, 8), [Tarih(2027, 3, 9), Tarih(2027, 3, 10), Tarih(2027, 3, 11)]),
      _DiniBayram('Kurban Bayramı', Tarih(2027, 5, 15),
          [Tarih(2027, 5, 16), Tarih(2027, 5, 17), Tarih(2027, 5, 18), Tarih(2027, 5, 19)]),
    ],
  };

  /// Dini bayram verisi bulunan yıllar.
  static Set<int> get diniBayramVerisiOlanYillar => _diniBayramlar.keys.toSet();

  static List<TatilGunu> diniBayramlar(int yil) {
    final bayramlar = _diniBayramlar[yil];
    if (bayramlar == null) return const [];
    return [
      for (final b in bayramlar) ...[
        TatilGunu(tarih: b.arife, ad: '${b.ad} arifesi', tur: TatilTuru.yarimGun),
        for (var i = 0; i < b.gunler.length; i++)
          TatilGunu(tarih: b.gunler[i], ad: '${b.ad} ${i + 1}. gün', tur: TatilTuru.diniBayram),
      ],
    ];
  }

  /// Verilen yıllar için tam takvim.
  static TatilTakvimi takvim(Iterable<int> yillar) => TatilTakvimi([
        for (final yil in yillar) ...[...sabitTatiller(yil), ...diniBayramlar(yil)],
      ]);
}

class _DiniBayram {
  _DiniBayram(this.ad, this.arife, this.gunler);

  final String ad;
  final Tarih arife;
  final List<Tarih> gunler;
}
