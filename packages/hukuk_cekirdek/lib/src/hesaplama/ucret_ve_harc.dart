import '../sure/onay_durumu.dart';
import '../takvim/tarih.dart';
import 'para.dart';

class NispiDilim {
  const NispiDilim(this.genislik, this.oran);

  /// Dilimin TL genişliği; son dilimde `null` (sınırsız).
  final int? genislik;

  /// Yüzde
  final double oran;
}

enum MahkemeTuru {
  sulhHukuk('Sulh hukuk mahkemesi'),
  asliye('Asliye mahkemeleri'),
  tuketici('Tüketici mahkemesi'),
  agirCeza('Ağır ceza mahkemesi');

  const MahkemeTuru(this.ad);

  final String ad;
}

class UcretKalemi {
  const UcretKalemi(this.aralik, this.oran, this.ucret);

  final String aralik;
  final double oran;
  final Para ucret;
}

class UcretSonucu {
  const UcretSonucu({required this.tarife, required this.nispi, required this.kalemler, required this.sonuc, required this.aciklama});

  final AvukatlikUcretTarifesi tarife;
  final Para nispi;
  final List<UcretKalemi> kalemler;
  final Para sonuc;
  final String aciklama;
}

/// Avukatlık Asgari Ücret Tarifesi (AAÜT). Referans veri; ONAY BEKLİYOR.
class AvukatlikUcretTarifesi {
  const AvukatlikUcretTarifesi({
    required this.ad,
    required this.yururluk,
    required this.resmiGazete,
    required this.dilimler,
    required this.maktu,
    this.onayDurumu = OnayDurumu.taslak,
    this.not,
  });

  final String ad;
  final Tarih yururluk;
  final String resmiGazete;
  final List<NispiDilim> dilimler;
  final Map<MahkemeTuru, int> maktu;
  final OnayDurumu onayDurumu;

  /// Kaynak verideki çelişki veya tahmin edilen değerler için avukata not.
  final String? not;

  /// Üçüncü kısım: dava değerinin dilimlere bölünerek hesaplanan nispi ücreti.
  (Para, List<UcretKalemi>) nispiHesapla(Para deger) {
    var kalan = deger.kurus;
    var alt = 0;
    var toplam = Para.sifir;
    final kalemler = <UcretKalemi>[];
    for (final d in dilimler) {
      if (kalan <= 0) break;
      final genislikKurus = d.genislik == null ? kalan : d.genislik! * 100;
      final dilimTutari = kalan < genislikKurus ? kalan : genislikKurus;
      final ucret = Para.kurus(dilimTutari).carp(d.oran / 100);
      kalemler.add(UcretKalemi(
        '${Para.kurus(alt).bicimli} – ${Para.kurus(alt + dilimTutari).bicimli}',
        d.oran,
        ucret,
      ));
      toplam = toplam + ucret;
      kalan -= dilimTutari;
      alt += dilimTutari;
    }
    return (toplam, kalemler);
  }

  /// Nispi ücret maktu ücretin altında kalamaz, hükmedilen miktarı geçemez (AAÜT genel hükümler; ONAY BEKLİYOR).
  UcretSonucu hesapla({required Para deger, MahkemeTuru? mahkeme}) {
    final (nispi, kalemler) = nispiHesapla(deger);
    var sonuc = nispi;
    var aciklama = 'Üçüncü kısma göre nispi ücret.';
    final maktuTl = mahkeme == null ? null : maktu[mahkeme];
    if (maktuTl != null) {
      final maktuPara = Para.tl(maktuTl);
      if (nispi < maktuPara) {
        sonuc = maktuPara;
        aciklama = 'Nispi ücret ${mahkeme!.ad} maktu ücretinin altında kaldığından maktu ücret uygulandı.';
      }
    }
    if (sonuc > deger) {
      sonuc = deger;
      aciklama = '$aciklama Ücret, hükmedilen miktarı geçemeyeceğinden dava değeriyle sınırlandı.';
    }
    return UcretSonucu(tarife: this, nispi: nispi, kalemler: kalemler, sonuc: sonuc, aciklama: aciklama);
  }

  static final tarifeRg20091224 = AvukatlikUcretTarifesi(
    ad: '2009-2010 AAÜT',
    yururluk: Tarih(2009, 12, 24),
    resmiGazete: '24.12.2009 / 27442',
    dilimler: const [
      NispiDilim(20000, 12),
      NispiDilim(30000, 11),
      NispiDilim(50000, 8),
      NispiDilim(150000, 6),
      NispiDilim(400000, 4),
      NispiDilim(600000, 3),
      NispiDilim(1000000, 1.5),
      NispiDilim(null, 0.1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 500,
      MahkemeTuru.asliye: 1000,
      MahkemeTuru.tuketici: 500,
      MahkemeTuru.agirCeza: 2000,
    },
  );

  static final tarifeRg20101203 = AvukatlikUcretTarifesi(
    ad: '2010-2011 AAÜT',
    yururluk: Tarih(2010, 12, 3),
    resmiGazete: '03.12.2010 / 27774',
    not: 'Son iki dilim (1.100.000 TL %1,5 ve üzeri %0,1) önceki tarifenin 1,1 katı olarak girildi; avukat kontrol etmeli.',
    dilimler: const [
      NispiDilim(22000, 12),
      NispiDilim(33000, 11),
      NispiDilim(55000, 8),
      NispiDilim(165000, 6),
      NispiDilim(440000, 4),
      NispiDilim(660000, 3),
      NispiDilim(1100000, 1.5),
      NispiDilim(null, 0.1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 550,
      MahkemeTuru.asliye: 1100,
      MahkemeTuru.tuketici: 550,
      MahkemeTuru.agirCeza: 2200,
    },
  );

  static final tarifeRg20111221 = AvukatlikUcretTarifesi(
    ad: '2011-2012 AAÜT',
    yururluk: Tarih(2011, 12, 21),
    resmiGazete: '21.12.2011 / 28149',
    dilimler: const [
      NispiDilim(25000, 12),
      NispiDilim(35000, 11),
      NispiDilim(60000, 8),
      NispiDilim(200000, 6),
      NispiDilim(500000, 4),
      NispiDilim(680000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 0.1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 600,
      MahkemeTuru.asliye: 1200,
      MahkemeTuru.tuketici: 600,
      MahkemeTuru.agirCeza: 2400,
    },
  );

  static final tarifeRg20121229 = AvukatlikUcretTarifesi(
    ad: '2012-2013 AAÜT',
    yururluk: Tarih(2012, 12, 29),
    resmiGazete: '29.12.2012 / 28512',
    dilimler: const [
      NispiDilim(25000, 12),
      NispiDilim(35000, 11),
      NispiDilim(60000, 8),
      NispiDilim(200000, 6),
      NispiDilim(500000, 4),
      NispiDilim(680000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 0.1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 660,
      MahkemeTuru.asliye: 1320,
      MahkemeTuru.tuketici: 660,
      MahkemeTuru.agirCeza: 2640,
    },
  );

  static final tarifeRg20131228 = AvukatlikUcretTarifesi(
    ad: '2014 AAÜT',
    yururluk: Tarih(2013, 12, 28),
    resmiGazete: '28.12.2013 / 28865',
    not: 'Kaynaklarda 3. ve 7. dilim tutarları dilim toplamıyla (3.000.000 TL) çelişiyor; 2015 tarifesindeki dilimler esas alındı, avukat kontrol etmeli.',
    dilimler: const [
      NispiDilim(30000, 12),
      NispiDilim(40000, 11),
      NispiDilim(80000, 8),
      NispiDilim(250000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 750,
      MahkemeTuru.asliye: 1500,
      MahkemeTuru.tuketici: 750,
      MahkemeTuru.agirCeza: 3000,
    },
  );

  static final tarifeRg20141231 = AvukatlikUcretTarifesi(
    ad: '2015 AAÜT',
    yururluk: Tarih(2014, 12, 31),
    resmiGazete: '31.12.2014 / 29222',
    dilimler: const [
      NispiDilim(30000, 12),
      NispiDilim(40000, 11),
      NispiDilim(80000, 8),
      NispiDilim(250000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 750,
      MahkemeTuru.asliye: 1500,
      MahkemeTuru.tuketici: 750,
      MahkemeTuru.agirCeza: 3000,
    },
  );

  static final tarifeRg20151221 = AvukatlikUcretTarifesi(
    ad: '2016 AAÜT',
    yururluk: Tarih(2015, 12, 21),
    resmiGazete: '21.12.2015 / 29569',
    dilimler: const [
      NispiDilim(35000, 12),
      NispiDilim(45000, 11),
      NispiDilim(80000, 8),
      NispiDilim(240000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 900,
      MahkemeTuru.asliye: 1800,
      MahkemeTuru.tuketici: 900,
      MahkemeTuru.agirCeza: 3600,
    },
  );

  static final tarifeRg20170102 = AvukatlikUcretTarifesi(
    ad: '2017 AAÜT',
    yururluk: Tarih(2017, 1, 2),
    resmiGazete: '02.01.2017 / 29936',
    dilimler: const [
      NispiDilim(35000, 12),
      NispiDilim(45000, 11),
      NispiDilim(80000, 8),
      NispiDilim(240000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 990,
      MahkemeTuru.asliye: 1980,
      MahkemeTuru.tuketici: 990,
      MahkemeTuru.agirCeza: 3960,
    },
  );

  static final tarifeRg20171230 = AvukatlikUcretTarifesi(
    ad: '2018 AAÜT',
    yururluk: Tarih(2017, 12, 30),
    resmiGazete: '30.12.2017 / 30286',
    not: 'Sulh hukuk maktu ücreti kaynakta sulh ceza ile birlikte okunduğundan avukat kontrol etmeli.',
    dilimler: const [
      NispiDilim(35000, 12),
      NispiDilim(45000, 11),
      NispiDilim(80000, 8),
      NispiDilim(240000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 1090,
      MahkemeTuru.asliye: 2180,
      MahkemeTuru.tuketici: 1090,
      MahkemeTuru.agirCeza: 4360,
    },
  );

  static final tarifeRg20190102 = AvukatlikUcretTarifesi(
    ad: '2019 AAÜT',
    yururluk: Tarih(2019, 1, 2),
    resmiGazete: '02.01.2019 / 30643',
    not: 'Asliye (2.725 TL) doğrulandı; sulh, tüketici ve ağır ceza 2020 tarifesindeki %25 artıştan geriye hesaplandı, avukat kontrol etmeli.',
    dilimler: const [
      NispiDilim(35000, 12),
      NispiDilim(45000, 11),
      NispiDilim(80000, 8),
      NispiDilim(240000, 6),
      NispiDilim(600000, 4),
      NispiDilim(750000, 3),
      NispiDilim(1250000, 1.5),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 1360,
      MahkemeTuru.asliye: 2725,
      MahkemeTuru.tuketici: 1360,
      MahkemeTuru.agirCeza: 5450,
    },
  );

  static final tarifeRg20200102 = AvukatlikUcretTarifesi(
    ad: '2020 AAÜT',
    yururluk: Tarih(2020, 1, 2),
    resmiGazete: '02.01.2020 / 30996',
    dilimler: const [
      NispiDilim(40000, 15),
      NispiDilim(50000, 13),
      NispiDilim(90000, 9.5),
      NispiDilim(250000, 7),
      NispiDilim(620000, 5),
      NispiDilim(775000, 3.5),
      NispiDilim(1275000, 1.8),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 1450,
      MahkemeTuru.asliye: 3400,
      MahkemeTuru.tuketici: 1700,
      MahkemeTuru.agirCeza: 6810,
    },
  );

  static final tarifeRg20201124 = AvukatlikUcretTarifesi(
    ad: '2021 AAÜT',
    yururluk: Tarih(2020, 11, 24),
    resmiGazete: '24.11.2020 / 31314',
    not: 'Tüketici maktu ücreti %20 artışla hesaplandı, avukat kontrol etmeli.',
    dilimler: const [
      NispiDilim(40000, 15),
      NispiDilim(50000, 13),
      NispiDilim(90000, 9.5),
      NispiDilim(250000, 7),
      NispiDilim(620000, 5),
      NispiDilim(775000, 3.5),
      NispiDilim(1275000, 1.8),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 1740,
      MahkemeTuru.asliye: 4080,
      MahkemeTuru.tuketici: 2040,
      MahkemeTuru.agirCeza: 8200,
    },
  );

  static final tarifeRg20211120 = AvukatlikUcretTarifesi(
    ad: '2022 AAÜT',
    yururluk: Tarih(2021, 11, 20),
    resmiGazete: '20.11.2021 / 31665',
    dilimler: const [
      NispiDilim(40000, 15),
      NispiDilim(50000, 13),
      NispiDilim(90000, 9.5),
      NispiDilim(250000, 7),
      NispiDilim(620000, 5),
      NispiDilim(775000, 3.5),
      NispiDilim(1275000, 1.8),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 2175,
      MahkemeTuru.asliye: 5100,
      MahkemeTuru.tuketici: 2550,
      MahkemeTuru.agirCeza: 10250,
    },
  );

  static final tarifeRg20220903 = AvukatlikUcretTarifesi(
    ad: '2022-2023 AAÜT',
    yururluk: Tarih(2022, 9, 3),
    resmiGazete: '03.09.2022 / 31942',
    dilimler: const [
      NispiDilim(100000, 16),
      NispiDilim(100000, 15),
      NispiDilim(300000, 14),
      NispiDilim(500000, 11),
      NispiDilim(700000, 8),
      NispiDilim(900000, 5),
      NispiDilim(1100000, 3),
      NispiDilim(1300000, 2),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 5500,
      MahkemeTuru.asliye: 9200,
      MahkemeTuru.tuketici: 4600,
      MahkemeTuru.agirCeza: 17400,
    },
  );

  static final tarifeRg20230921 = AvukatlikUcretTarifesi(
    ad: '2023-2024 AAÜT',
    yururluk: Tarih(2023, 9, 21),
    resmiGazete: '21.09.2023 / 32316',
    not: 'Tarife metninde son eşik 5.600.000 TL yazıyor ancak dilim genişliklerinin toplamı 5.800.000 TL; hesap dilim genişliklerine göre yapılır.',
    dilimler: const [
      NispiDilim(200000, 16),
      NispiDilim(200000, 15),
      NispiDilim(400000, 14),
      NispiDilim(600000, 11),
      NispiDilim(800000, 8),
      NispiDilim(1000000, 5),
      NispiDilim(1200000, 3),
      NispiDilim(1400000, 2),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 10700,
      MahkemeTuru.asliye: 17900,
      MahkemeTuru.tuketici: 9000,
      MahkemeTuru.agirCeza: 29800,
    },
  );

  static final tarifeRg20241003 = AvukatlikUcretTarifesi(
    ad: '2024-2025 AAÜT',
    yururluk: Tarih(2024, 10, 3),
    resmiGazete: '03.10.2024 / 32681',
    dilimler: const [
      NispiDilim(400000, 16),
      NispiDilim(400000, 15),
      NispiDilim(800000, 14),
      NispiDilim(1200000, 11),
      NispiDilim(1600000, 8),
      NispiDilim(2000000, 5),
      NispiDilim(2400000, 3),
      NispiDilim(2800000, 2),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 18000,
      MahkemeTuru.asliye: 30000,
      MahkemeTuru.tuketici: 15000,
      MahkemeTuru.agirCeza: 48000,
    },
  );

  static final tarife2025 = AvukatlikUcretTarifesi(
    ad: '2025-2026 AAÜT',
    yururluk: Tarih(2025, 11, 4),
    resmiGazete: '04.11.2025 / 33067',
    dilimler: const [
      NispiDilim(600000, 16),
      NispiDilim(600000, 15),
      NispiDilim(1200000, 14),
      NispiDilim(1200000, 13),
      NispiDilim(1800000, 11),
      NispiDilim(2400000, 8),
      NispiDilim(3000000, 5),
      NispiDilim(3600000, 3),
      NispiDilim(4200000, 2),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 30000,
      MahkemeTuru.asliye: 45000,
      MahkemeTuru.tuketici: 22500,
      MahkemeTuru.agirCeza: 65000,
    },
  );

  static final tarife2026 = AvukatlikUcretTarifesi(
    ad: '2026-2027 AAÜT',
    yururluk: Tarih(2026, 11, 3),
    resmiGazete: '03.11.2026 / 33419',
    dilimler: const [
      NispiDilim(800000, 16),
      NispiDilim(800000, 15),
      NispiDilim(1600000, 14),
      NispiDilim(1600000, 13),
      NispiDilim(2400000, 11),
      NispiDilim(3200000, 8),
      NispiDilim(4000000, 5),
      NispiDilim(4800000, 3),
      NispiDilim(5600000, 2),
      NispiDilim(null, 1),
    ],
    maktu: const {
      MahkemeTuru.sulhHukuk: 40000,
      MahkemeTuru.asliye: 62000,
      MahkemeTuru.tuketici: 30000,
      MahkemeTuru.agirCeza: 86000,
    },
  );

  /// 24.12.2009'dan bugüne yürürlüğe giren tarifeler (2010'dan beri açılmış davalar için), eskiden yeniye.
  static final List<AvukatlikUcretTarifesi> tumu = [
    tarifeRg20091224,
    tarifeRg20101203,
    tarifeRg20111221,
    tarifeRg20121229,
    tarifeRg20131228,
    tarifeRg20141231,
    tarifeRg20151221,
    tarifeRg20170102,
    tarifeRg20171230,
    tarifeRg20190102,
    tarifeRg20200102,
    tarifeRg20201124,
    tarifeRg20211120,
    tarifeRg20220903,
    tarifeRg20230921,
    tarifeRg20241003,
    tarife2025,
    tarife2026,
  ];

  /// Verilen tarihte yürürlükte olan tarife (tarife m.21: hizmetin tamamlandığı / hükmün verildiği tarih).
  /// İlk tarifeden önceki tarihler için ilk tarife döner.
  static AvukatlikUcretTarifesi gecerli(Tarih tarih) {
    AvukatlikUcretTarifesi sonuc = tumu.first;
    for (final t in tumu) {
      if (!t.yururluk.isAfter(tarih)) sonuc = t;
    }
    return sonuc;
  }

  /// AYM E.2024/29, K.2024/226 kararının (HMK m.326/2'nin manevi tazminat davaları yönünden iptali)
  /// Resmî Gazete'de yayımlandığı tarih (14.03.2025/32841).
  static final aymManeviTazminatKarariTarihi = Tarih(2025, 3, 14);

  /// Kısmen kabul / kısmen ret halinde iki tarafın vekâlet ücreti. ONAY BEKLİYOR.
  ///
  /// - Davacı vekili lehine: kabul edilen miktar üzerinden üçüncü kısma göre (maktu alt sınır ve
  ///   hükmedilen miktar üst sınırıyla).
  /// - Davalı vekili lehine: reddedilen miktar üzerinden aynı esasla; ancak bu ücret davacı vekili
  ///   lehine belirlenen ücreti geçemez (AAÜT m.10/2 manevi, m.13/3 maddi tazminat).
  /// - Manevi tazminat davasında kısmi ret: AYM 2024/226 kararı (RG 14.03.2025) sonrasında davalı
  ///   lehine vekâlet ücretine hükmedilmez.
  /// - Davanın tamamen reddi: davalı lehine reddedilen miktar üzerinden; manevi tazminatta
  ///   ikinci kısım ikinci bölümdeki maktu ücret (AAÜT m.10/3).
  static KismiKabulSonucu kismiKabulRed({
    required Para talep,
    required Para kabul,
    required Tarih hukumTarihi,
    MahkemeTuru? mahkeme,
    bool maneviTazminat = false,
  }) {
    if (kabul > talep) throw ArgumentError('Kabul edilen miktar talepten büyük olamaz.');
    if (kabul.kurus < 0) throw ArgumentError('Kabul edilen miktar negatif olamaz.');
    final tarife = gecerli(hukumTarihi);
    final aciklamalar = <String>['${tarife.ad} (RG ${tarife.resmiGazete}) uygulandı (hüküm tarihi ${hukumTarihi.turkceBicim}).'];
    if (tarife.not != null) aciklamalar.add(tarife.not!);
    final ret = talep - kabul;

    final davaci = kabul.sifirMi ? null : tarife.hesapla(deger: kabul, mahkeme: mahkeme);
    if (davaci != null) aciklamalar.add('Davacı vekili: kabul edilen ${kabul.bicimli} üzerinden. ${davaci.aciklama}');

    UcretSonucu? davaliHesap;
    var davali = Para.sifir;
    if (ret.sifirMi) {
      aciklamalar.add('Reddedilen kısım olmadığından davalı lehine vekâlet ücreti yok.');
    } else if (kabul.sifirMi) {
      if (maneviTazminat) {
        final m = tarife.maktu[mahkeme ?? MahkemeTuru.asliye];
        davali = m == null ? Para.sifir : Para.tl(m);
        aciklamalar.add('Manevi tazminat davasının tamamen reddi: maktu ücret (AAÜT m.10/3).');
      } else {
        davaliHesap = tarife.hesapla(deger: ret, mahkeme: mahkeme);
        davali = davaliHesap.sonuc;
        aciklamalar.add('Davanın tamamen reddi: reddedilen ${ret.bicimli} üzerinden. ${davaliHesap.aciklama}');
      }
    } else if (maneviTazminat && !hukumTarihi.isBefore(aymManeviTazminatKarariTarihi)) {
      aciklamalar.add('Manevi tazminat davasında kısmi ret: AYM E.2024/29, K.2024/226 kararı (RG 14.03.2025/32841) '
          'gereğince davalı lehine vekâlet ücretine hükmedilmez.');
    } else {
      davaliHesap = tarife.hesapla(deger: ret, mahkeme: mahkeme);
      davali = davaliHesap.sonuc;
      aciklamalar.add('Davalı vekili: reddedilen ${ret.bicimli} üzerinden. ${davaliHesap.aciklama}');
      final ust = davaci!.sonuc;
      if (davali > ust) {
        davali = ust;
        aciklamalar.add('Davalı lehine ücret, davacı vekili lehine belirlenen ücreti geçemeyeceğinden '
            '${ust.bicimli} ile sınırlandı (AAÜT ${maneviTazminat ? 'm.10/2' : 'm.13/3'}).');
      }
      if (maneviTazminat) {
        aciklamalar.add('Hüküm tarihi AYM kararının yayımından (14.03.2025) önce olduğundan kısmi ret ücreti hesaplandı.');
      }
    }
    return KismiKabulSonucu(
      tarife: tarife,
      talep: talep,
      kabul: kabul,
      ret: ret,
      davaci: davaci,
      davaliHesap: davaliHesap,
      davaliUcreti: davali,
      aciklamalar: aciklamalar,
    );
  }
}

class KismiKabulSonucu {
  const KismiKabulSonucu({
    required this.tarife,
    required this.talep,
    required this.kabul,
    required this.ret,
    required this.davaci,
    required this.davaliHesap,
    required this.davaliUcreti,
    required this.aciklamalar,
  });

  final AvukatlikUcretTarifesi tarife;
  final Para talep;
  final Para kabul;
  final Para ret;

  /// Davacı vekili lehine ücret hesabı; kabul yoksa null.
  final UcretSonucu? davaci;

  /// Davalı lehine ücretin sınırlamadan önceki hesabı; hükmedilmiyorsa null.
  final UcretSonucu? davaliHesap;

  /// Davalı vekili lehine hükmedilecek ücret (sınırlandırılmış).
  final Para davaliUcreti;
  final List<String> aciklamalar;

  Para get davaciUcreti => davaci?.sonuc ?? Para.sifir;
}

class DavaHarci {
  const DavaHarci({required this.basvurma, required this.pesinKararHarci, required this.kalanKararHarci, required this.aciklama});

  final Para basvurma;
  final Para pesinKararHarci;

  /// Karar aşamasında (kabul halinde) ödenecek kalan nispi harç.
  final Para kalanKararHarci;
  final String aciklama;

  Para get acilistaOdenecek => basvurma + pesinKararHarci;
}

/// 492 sayılı Harçlar Kanunu (1) sayılı tarife; yıllık güncellenir. ONAY BEKLİYOR.
///
/// 2010'dan beri her dönem ayrı tutulur; dava açılış harcı dava tarihindeki tarifeyle hesaplanır.
/// Nispi karar ve ilam harcı 2010-2011'de binde 59,40; 1.1.2012'den beri binde 68,31.
class HarcTarifesi {
  const HarcTarifesi({
    required this.yil,
    this.baslangicAy = 1,
    this.baslangicGun = 1,
    required this.basvurmaSulh,
    required this.basvurmaAsliye,
    required this.maktuKarar,
    required this.nispiBinde,
    required this.asgariNispi,
    this.kaynak = '',
    this.onayDurumu = OnayDurumu.taslak,
  });

  final int yil;
  final int baslangicAy;
  final int baslangicGun;
  final double basvurmaSulh;
  final double basvurmaAsliye;
  final double maktuKarar;
  final double nispiBinde;
  final double asgariNispi;
  final String kaynak;
  final OnayDurumu onayDurumu;

  Tarih get yururluk => Tarih(yil, baslangicAy, baslangicGun);

  /// Dönemin adı, ör. "2023 (15.07.2023'ten)".
  String get donemAdi => baslangicAy == 1 && baslangicGun == 1 ? '$yil' : '$yil (${yururluk.turkceBicim}\'ten)';

  static const y2010 = HarcTarifesi(
    yil: 2010,
    basvurmaSulh: 8.00,
    basvurmaAsliye: 17.10,
    maktuKarar: 17.10,
    nispiBinde: 59.40,
    asgariNispi: 17.10,
    kaynak: '58-60 seri no HK Genel Tebliği (2009 tutarları %10 artırıldı)',
  );

  static const y2011 = HarcTarifesi(
    yil: 2011,
    basvurmaSulh: 8.60,
    basvurmaAsliye: 18.40,
    maktuKarar: 18.40,
    nispiBinde: 59.40,
    asgariNispi: 18.40,
    kaynak: '63 seri no HK Genel Tebliği',
  );

  static const y2012 = HarcTarifesi(
    yil: 2012,
    basvurmaSulh: 9.85,
    basvurmaAsliye: 21.15,
    maktuKarar: 21.15,
    nispiBinde: 68.31,
    asgariNispi: 21.15,
    kaynak: '2011/2628 BKK, %15 artış',
  );

  static const y2013 = HarcTarifesi(
    yil: 2013,
    basvurmaSulh: 11.30,
    basvurmaAsliye: 24.30,
    maktuKarar: 24.30,
    nispiBinde: 68.31,
    asgariNispi: 24.30,
    kaynak: '69 seri no HK Genel Tebliği',
  );

  static const y2014 = HarcTarifesi(
    yil: 2014,
    basvurmaSulh: 11.70,
    basvurmaAsliye: 25.20,
    maktuKarar: 25.20,
    nispiBinde: 68.31,
    asgariNispi: 25.20,
    kaynak: 'Yeniden değerleme %3,93 (sulh tutarı hesaplandı)',
  );

  static const y2015 = HarcTarifesi(
    yil: 2015,
    basvurmaSulh: 12.80,
    basvurmaAsliye: 27.70,
    maktuKarar: 27.70,
    nispiBinde: 68.31,
    asgariNispi: 27.70,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2016 = HarcTarifesi(
    yil: 2016,
    basvurmaSulh: 13.50,
    basvurmaAsliye: 29.20,
    maktuKarar: 29.20,
    nispiBinde: 68.31,
    asgariNispi: 29.20,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2017 = HarcTarifesi(
    yil: 2017,
    basvurmaSulh: 14.50,
    basvurmaAsliye: 31.40,
    maktuKarar: 31.40,
    nispiBinde: 68.31,
    asgariNispi: 31.40,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2018 = HarcTarifesi(
    yil: 2018,
    basvurmaSulh: 16.50,
    basvurmaAsliye: 35.90,
    maktuKarar: 35.90,
    nispiBinde: 68.31,
    asgariNispi: 35.90,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2019 = HarcTarifesi(
    yil: 2019,
    basvurmaSulh: 20.40,
    basvurmaAsliye: 44.40,
    maktuKarar: 44.40,
    nispiBinde: 68.31,
    asgariNispi: 44.40,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2020 = HarcTarifesi(
    yil: 2020,
    basvurmaSulh: 25.00,
    basvurmaAsliye: 54.40,
    maktuKarar: 54.40,
    nispiBinde: 68.31,
    asgariNispi: 54.40,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2021 = HarcTarifesi(
    yil: 2021,
    basvurmaSulh: 27.20,
    basvurmaAsliye: 59.30,
    maktuKarar: 59.30,
    nispiBinde: 68.31,
    asgariNispi: 59.30,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2022 = HarcTarifesi(
    yil: 2022,
    basvurmaSulh: 37.00,
    basvurmaAsliye: 80.70,
    maktuKarar: 80.70,
    nispiBinde: 68.31,
    asgariNispi: 80.70,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2023 = HarcTarifesi(
    yil: 2023,
    basvurmaSulh: 82.40,
    basvurmaAsliye: 179.90,
    maktuKarar: 179.90,
    nispiBinde: 68.31,
    asgariNispi: 179.90,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2023Temmuz = HarcTarifesi(
    yil: 2023,
    baslangicAy: 7,
    baslangicGun: 15,
    basvurmaSulh: 123.60,
    basvurmaAsliye: 269.85,
    maktuKarar: 269.85,
    nispiBinde: 68.31,
    asgariNispi: 269.85,
    kaynak: '7456 sayılı Kanun ile %50 artış (15.07.2023)',
  );

  static const y2024 = HarcTarifesi(
    yil: 2024,
    basvurmaSulh: 195.80,
    basvurmaAsliye: 427.60,
    maktuKarar: 427.60,
    nispiBinde: 68.31,
    asgariNispi: 427.60,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2025 = HarcTarifesi(
    yil: 2025,
    basvurmaSulh: 281.80,
    basvurmaAsliye: 615.40,
    maktuKarar: 615.40,
    nispiBinde: 68.31,
    asgariNispi: 615.40,
    kaynak: 'HK Genel Tebliği',
  );

  static const y2026 = HarcTarifesi(
    yil: 2026,
    basvurmaSulh: 335.20,
    basvurmaAsliye: 732.00,
    maktuKarar: 732.00,
    nispiBinde: 68.31,
    asgariNispi: 732.00,
    kaynak: 'HK Genel Tebliği Seri No: 98',
  );

  static const List<HarcTarifesi> tumu = [
    y2010,
    y2011,
    y2012,
    y2013,
    y2014,
    y2015,
    y2016,
    y2017,
    y2018,
    y2019,
    y2020,
    y2021,
    y2022,
    y2023,
    y2023Temmuz,
    y2024,
    y2025,
    y2026,
  ];

  /// Verilen tarihte yürürlükte olan harç tarifesi; 2010 öncesi için 2010 tarifesi döner.
  static HarcTarifesi gecerli(Tarih tarih) {
    var sonuc = tumu.first;
    for (final t in tumu) {
      if (!t.yururluk.isAfter(tarih)) sonuc = t;
    }
    return sonuc;
  }

  /// [deger] verilirse nispi harçlı dava; dava açılışında nispi harcın 1/4'ü peşin alınır (HK m.28).
  DavaHarci davaAcilisi({required MahkemeTuru mahkeme, Para? deger}) {
    final basvurma = Para.tl(mahkeme == MahkemeTuru.sulhHukuk ? basvurmaSulh : basvurmaAsliye);
    if (deger == null) {
      return DavaHarci(
        basvurma: basvurma,
        pesinKararHarci: Para.tl(maktuKarar),
        kalanKararHarci: Para.sifir,
        aciklama: 'Maktu harçlı dava: maktu karar ve ilam harcı peşin alınır.',
      );
    }
    final nispi = Para.enBuyuk(deger.carp(nispiBinde / 1000), Para.tl(asgariNispi));
    final pesin = nispi.carp(0.25);
    return DavaHarci(
      basvurma: basvurma,
      pesinKararHarci: pesin,
      kalanKararHarci: nispi - pesin,
      aciklama: 'Nispi harç binde $nispiBinde; dörtte biri peşin, kalanı karar aşamasında.',
    );
  }
}
