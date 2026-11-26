import 'tarih.dart';
import 'tatil_takvimi.dart';

/// Türkiye resmi tatil takvimi (2429 sayılı Kanun ve Diyanet dini günler takvimi).
///
/// DİKKAT: Dini bayram tarihleri her yıl Diyanet takvimine göre girilir.
/// Bu dosyadaki dini bayram tarihleri avukat onayı bekleyen referans veridir;
/// canlı ortamda bu veri yönetim panelinden (referans veri modülü) yönetilecektir.
class TurkiyeTatilleri {
  TurkiyeTatilleri._();

  /// 15 Temmuz Demokrasi ve Millî Birlik Günü'nün genel tatil sayıldığı ilk yıl.
  static const demokrasiGunuIlkYil = 2017;

  /// Dini bayram verisinin başladığı yıl (2010'dan beri açılmış davalar için).
  static const ilkVeriYili = 2010;

  /// Sabit tarihli ulusal bayram ve genel tatiller (yıla göre; 2429 s.K. m.2).
  static List<TatilGunu> sabitTatiller(int yil) => [
        TatilGunu(tarih: Tarih(yil, 1, 1), ad: 'Yılbaşı', tur: TatilTuru.resmiTatil),
        TatilGunu(
            tarih: Tarih(yil, 4, 23), ad: 'Ulusal Egemenlik ve Çocuk Bayramı', tur: TatilTuru.resmiTatil),
        TatilGunu(tarih: Tarih(yil, 5, 1), ad: 'Emek ve Dayanışma Günü', tur: TatilTuru.resmiTatil),
        TatilGunu(
            tarih: Tarih(yil, 5, 19),
            ad: 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı',
            tur: TatilTuru.resmiTatil),
        // 6752 sayılı Kanun (RG 29.10.2016) ile eklendi; ilk kez 2017'de genel tatil.
        if (yil >= demokrasiGunuIlkYil)
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
  /// 2010-2025 geçmiş yıllar Diyanet takvimine göre girildi; Türkiye'de bayram günleri
  /// diğer ülkelerden bir gün önce başlayabilir (ör. Ramazan Bayramı 9 Eylül 2010).
  /// ONAY BEKLİYOR: ekipteki avukat Diyanet'in resmi takvimiyle karşılaştırmalıdır.
  static final Map<int, List<_DiniBayram>> _diniBayramlar = {
    2010: [
      _DiniBayram('Ramazan Bayramı', Tarih(2010, 9, 8), [Tarih(2010, 9, 9), Tarih(2010, 9, 10), Tarih(2010, 9, 11)]),
      _DiniBayram('Kurban Bayramı', Tarih(2010, 11, 15),
          [Tarih(2010, 11, 16), Tarih(2010, 11, 17), Tarih(2010, 11, 18), Tarih(2010, 11, 19)]),
    ],
    2011: [
      _DiniBayram('Ramazan Bayramı', Tarih(2011, 8, 29), [Tarih(2011, 8, 30), Tarih(2011, 8, 31), Tarih(2011, 9, 1)]),
      _DiniBayram('Kurban Bayramı', Tarih(2011, 11, 5),
          [Tarih(2011, 11, 6), Tarih(2011, 11, 7), Tarih(2011, 11, 8), Tarih(2011, 11, 9)]),
    ],
    2012: [
      _DiniBayram('Ramazan Bayramı', Tarih(2012, 8, 18), [Tarih(2012, 8, 19), Tarih(2012, 8, 20), Tarih(2012, 8, 21)]),
      _DiniBayram('Kurban Bayramı', Tarih(2012, 10, 24),
          [Tarih(2012, 10, 25), Tarih(2012, 10, 26), Tarih(2012, 10, 27), Tarih(2012, 10, 28)]),
    ],
    2013: [
      _DiniBayram('Ramazan Bayramı', Tarih(2013, 8, 7), [Tarih(2013, 8, 8), Tarih(2013, 8, 9), Tarih(2013, 8, 10)]),
      _DiniBayram('Kurban Bayramı', Tarih(2013, 10, 14),
          [Tarih(2013, 10, 15), Tarih(2013, 10, 16), Tarih(2013, 10, 17), Tarih(2013, 10, 18)]),
    ],
    2014: [
      _DiniBayram('Ramazan Bayramı', Tarih(2014, 7, 27), [Tarih(2014, 7, 28), Tarih(2014, 7, 29), Tarih(2014, 7, 30)]),
      _DiniBayram('Kurban Bayramı', Tarih(2014, 10, 3),
          [Tarih(2014, 10, 4), Tarih(2014, 10, 5), Tarih(2014, 10, 6), Tarih(2014, 10, 7)]),
    ],
    2015: [
      _DiniBayram('Ramazan Bayramı', Tarih(2015, 7, 16), [Tarih(2015, 7, 17), Tarih(2015, 7, 18), Tarih(2015, 7, 19)]),
      _DiniBayram('Kurban Bayramı', Tarih(2015, 9, 23),
          [Tarih(2015, 9, 24), Tarih(2015, 9, 25), Tarih(2015, 9, 26), Tarih(2015, 9, 27)]),
    ],
    2016: [
      _DiniBayram('Ramazan Bayramı', Tarih(2016, 7, 4), [Tarih(2016, 7, 5), Tarih(2016, 7, 6), Tarih(2016, 7, 7)]),
      _DiniBayram('Kurban Bayramı', Tarih(2016, 9, 11),
          [Tarih(2016, 9, 12), Tarih(2016, 9, 13), Tarih(2016, 9, 14), Tarih(2016, 9, 15)]),
    ],
    2017: [
      _DiniBayram('Ramazan Bayramı', Tarih(2017, 6, 24), [Tarih(2017, 6, 25), Tarih(2017, 6, 26), Tarih(2017, 6, 27)]),
      _DiniBayram('Kurban Bayramı', Tarih(2017, 8, 31),
          [Tarih(2017, 9, 1), Tarih(2017, 9, 2), Tarih(2017, 9, 3), Tarih(2017, 9, 4)]),
    ],
    2018: [
      _DiniBayram('Ramazan Bayramı', Tarih(2018, 6, 14), [Tarih(2018, 6, 15), Tarih(2018, 6, 16), Tarih(2018, 6, 17)]),
      _DiniBayram('Kurban Bayramı', Tarih(2018, 8, 20),
          [Tarih(2018, 8, 21), Tarih(2018, 8, 22), Tarih(2018, 8, 23), Tarih(2018, 8, 24)]),
    ],
    2019: [
      _DiniBayram('Ramazan Bayramı', Tarih(2019, 6, 3), [Tarih(2019, 6, 4), Tarih(2019, 6, 5), Tarih(2019, 6, 6)]),
      _DiniBayram('Kurban Bayramı', Tarih(2019, 8, 10),
          [Tarih(2019, 8, 11), Tarih(2019, 8, 12), Tarih(2019, 8, 13), Tarih(2019, 8, 14)]),
    ],
    2020: [
      _DiniBayram('Ramazan Bayramı', Tarih(2020, 5, 23), [Tarih(2020, 5, 24), Tarih(2020, 5, 25), Tarih(2020, 5, 26)]),
      _DiniBayram('Kurban Bayramı', Tarih(2020, 7, 30),
          [Tarih(2020, 7, 31), Tarih(2020, 8, 1), Tarih(2020, 8, 2), Tarih(2020, 8, 3)]),
    ],
    2021: [
      _DiniBayram('Ramazan Bayramı', Tarih(2021, 5, 12), [Tarih(2021, 5, 13), Tarih(2021, 5, 14), Tarih(2021, 5, 15)]),
      _DiniBayram('Kurban Bayramı', Tarih(2021, 7, 19),
          [Tarih(2021, 7, 20), Tarih(2021, 7, 21), Tarih(2021, 7, 22), Tarih(2021, 7, 23)]),
    ],
    2022: [
      _DiniBayram('Ramazan Bayramı', Tarih(2022, 5, 1), [Tarih(2022, 5, 2), Tarih(2022, 5, 3), Tarih(2022, 5, 4)]),
      _DiniBayram('Kurban Bayramı', Tarih(2022, 7, 8),
          [Tarih(2022, 7, 9), Tarih(2022, 7, 10), Tarih(2022, 7, 11), Tarih(2022, 7, 12)]),
    ],
    2023: [
      _DiniBayram('Ramazan Bayramı', Tarih(2023, 4, 20), [Tarih(2023, 4, 21), Tarih(2023, 4, 22), Tarih(2023, 4, 23)]),
      _DiniBayram('Kurban Bayramı', Tarih(2023, 6, 27),
          [Tarih(2023, 6, 28), Tarih(2023, 6, 29), Tarih(2023, 6, 30), Tarih(2023, 7, 1)]),
    ],
    2024: [
      _DiniBayram('Ramazan Bayramı', Tarih(2024, 4, 9), [Tarih(2024, 4, 10), Tarih(2024, 4, 11), Tarih(2024, 4, 12)]),
      _DiniBayram('Kurban Bayramı', Tarih(2024, 6, 15),
          [Tarih(2024, 6, 16), Tarih(2024, 6, 17), Tarih(2024, 6, 18), Tarih(2024, 6, 19)]),
    ],
    2025: [
      _DiniBayram('Ramazan Bayramı', Tarih(2025, 3, 29), [Tarih(2025, 3, 30), Tarih(2025, 3, 31), Tarih(2025, 4, 1)]),
      _DiniBayram('Kurban Bayramı', Tarih(2025, 6, 5),
          [Tarih(2025, 6, 6), Tarih(2025, 6, 7), Tarih(2025, 6, 8), Tarih(2025, 6, 9)]),
    ],
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
