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
  });

  final String ad;
  final Tarih yururluk;
  final String resmiGazete;
  final List<NispiDilim> dilimler;
  final Map<MahkemeTuru, int> maktu;
  final OnayDurumu onayDurumu;

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

  static final List<AvukatlikUcretTarifesi> tumu = [tarife2025, tarife2026];

  /// Verilen tarihte yürürlükte olan tarife (tarife m.21: hizmetin tamamlandığı / hükmün verildiği tarih).
  static AvukatlikUcretTarifesi gecerli(Tarih tarih) {
    AvukatlikUcretTarifesi sonuc = tumu.first;
    for (final t in tumu) {
      if (!t.yururluk.isAfter(tarih)) sonuc = t;
    }
    return sonuc;
  }
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
class HarcTarifesi {
  const HarcTarifesi({
    required this.yil,
    required this.basvurmaSulh,
    required this.basvurmaAsliye,
    required this.maktuKarar,
    required this.nispiBinde,
    required this.asgariNispi,
    this.onayDurumu = OnayDurumu.taslak,
  });

  final int yil;
  final double basvurmaSulh;
  final double basvurmaAsliye;
  final double maktuKarar;
  final double nispiBinde;
  final double asgariNispi;
  final OnayDurumu onayDurumu;

  static const y2026 = HarcTarifesi(
    yil: 2026,
    basvurmaSulh: 335.20,
    basvurmaAsliye: 732.00,
    maktuKarar: 732.00,
    nispiBinde: 68.31,
    asgariNispi: 732.00,
  );

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
