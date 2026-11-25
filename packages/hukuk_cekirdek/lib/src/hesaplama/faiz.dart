import '../sure/onay_durumu.dart';
import '../takvim/tarih.dart';
import 'para.dart';

/// Bir faiz oranının yürürlükte olduğu dönem.
class FaizDonemi {
  const FaizDonemi({required this.baslangic, required this.yillikOran, required this.dayanak});

  final Tarih baslangic;

  /// Yüzde olarak, ör. 24.0
  final double yillikOran;
  final String dayanak;
}

enum FaizTuru {
  yasal('Yasal (kanuni) faiz'),
  avans('Ticari temerrüt (avans) faizi'),
  akdi('Sözleşmesel faiz');

  const FaizTuru(this.ad);

  final String ad;
}

/// Dönemsel faiz oranı tablosu (referans veri; avukat onayıyla güncellenir).
class FaizTablosu {
  FaizTablosu({required this.tur, required List<FaizDonemi> donemler, this.onayDurumu = OnayDurumu.taslak})
      : donemler = List<FaizDonemi>.unmodifiable(<FaizDonemi>[...donemler]..sort((a, b) => a.baslangic.compareTo(b.baslangic)));

  final FaizTuru tur;
  final List<FaizDonemi> donemler;
  final OnayDurumu onayDurumu;

  /// Sözleşmede tek bir oran kararlaştırıldıysa.
  factory FaizTablosu.sabit(double yillikOran, {String dayanak = 'Sözleşme'}) => FaizTablosu(
        tur: FaizTuru.akdi,
        donemler: [FaizDonemi(baslangic: Tarih(1900, 1, 1), yillikOran: yillikOran, dayanak: dayanak)],
        onayDurumu: OnayDurumu.onayli,
      );

  FaizDonemi? donem(Tarih t) {
    FaizDonemi? sonuc;
    for (final d in donemler) {
      if (!d.baslangic.isAfter(t)) sonuc = d;
    }
    return sonuc;
  }

  /// 3095 sayılı Kanun m.1 yasal faiz oranları.
  /// Kaynak: Cumhurbaşkanı Kararı (8485) ve 7589 sayılı Kanun m.10 (12. Yargı Paketi). ONAY BEKLİYOR.
  static final yasal = FaizTablosu(tur: FaizTuru.yasal, donemler: [
    FaizDonemi(baslangic: Tarih(2006, 1, 1), yillikOran: 9, dayanak: '2005/9831 sayılı BKK'),
    FaizDonemi(baslangic: Tarih(2024, 6, 1), yillikOran: 24, dayanak: '8485 sayılı CK'),
    FaizDonemi(
        baslangic: Tarih(2026, 7, 31),
        yillikOran: 31,
        dayanak: '7589 sayılı Kanun m.10 (TCMB 2025 yıl sonu reeskont oranının %80\'i)'),
  ]);

  /// Ticari temerrüt (avans) faizi (3095 s.K. m.2/2): TCMB'nin kısa vadeli avans işlemlerine uyguladığı oran,
  /// tebliğin Resmî Gazete'de yayımı tarihinden itibaren. Kaynak: TCMB reeskont ve avans faiz oranları tablosu.
  /// 2014 öncesi dönemler yüklenmedi. ONAY BEKLİYOR.
  static final avans = FaizTablosu(tur: FaizTuru.avans, donemler: [
    FaizDonemi(baslangic: Tarih(2014, 12, 14), yillikOran: 10.5, dayanak: 'TCMB tebliği 14.12.2014'),
    FaizDonemi(baslangic: Tarih(2016, 12, 31), yillikOran: 9.75, dayanak: 'TCMB tebliği 31.12.2016'),
    FaizDonemi(baslangic: Tarih(2018, 6, 29), yillikOran: 19.5, dayanak: 'TCMB tebliği 29.06.2018'),
    FaizDonemi(baslangic: Tarih(2019, 10, 11), yillikOran: 18.25, dayanak: 'TCMB tebliği 11.10.2019'),
    FaizDonemi(baslangic: Tarih(2019, 12, 21), yillikOran: 13.75, dayanak: 'TCMB tebliği 21.12.2019'),
    FaizDonemi(baslangic: Tarih(2020, 6, 13), yillikOran: 10, dayanak: 'TCMB tebliği 13.06.2020'),
    FaizDonemi(baslangic: Tarih(2020, 12, 19), yillikOran: 16.75, dayanak: 'TCMB tebliği 19.12.2020'),
    FaizDonemi(baslangic: Tarih(2022, 1, 2), yillikOran: 15.75, dayanak: 'TCMB tebliği 02.01.2022'),
    FaizDonemi(baslangic: Tarih(2022, 12, 31), yillikOran: 10.75, dayanak: 'TCMB tebliği 31.12.2022'),
    FaizDonemi(baslangic: Tarih(2023, 6, 24), yillikOran: 16.75, dayanak: 'TCMB tebliği 24.06.2023'),
    FaizDonemi(baslangic: Tarih(2023, 9, 1), yillikOran: 26.75, dayanak: 'TCMB tebliği 01.09.2023'),
    FaizDonemi(baslangic: Tarih(2023, 9, 28), yillikOran: 31.75, dayanak: 'TCMB tebliği 28.09.2023'),
    FaizDonemi(baslangic: Tarih(2023, 11, 1), yillikOran: 36.75, dayanak: 'TCMB tebliği 01.11.2023'),
    FaizDonemi(baslangic: Tarih(2023, 12, 1), yillikOran: 41.75, dayanak: 'TCMB tebliği 01.12.2023'),
    FaizDonemi(baslangic: Tarih(2023, 12, 23), yillikOran: 44.25, dayanak: 'TCMB tebliği 23.12.2023'),
    FaizDonemi(baslangic: Tarih(2024, 4, 1), yillikOran: 51.75, dayanak: 'TCMB tebliği 01.04.2024'),
    FaizDonemi(baslangic: Tarih(2024, 12, 28), yillikOran: 49.25, dayanak: 'TCMB tebliği 28.12.2024'),
    FaizDonemi(baslangic: Tarih(2025, 3, 8), yillikOran: 44.25, dayanak: 'TCMB tebliği 08.03.2025'),
    FaizDonemi(baslangic: Tarih(2025, 9, 17), yillikOran: 42.25, dayanak: 'TCMB tebliği 17.09.2025'),
    FaizDonemi(baslangic: Tarih(2025, 12, 20), yillikOran: 39.75, dayanak: 'TCMB tebliği 20.12.2025'),
  ]);
}

class FaizKalemi {
  const FaizKalemi({required this.baslangic, required this.bitis, required this.gun, required this.oran, required this.faiz});

  final Tarih baslangic;
  final Tarih bitis;
  final int gun;
  final double oran;
  final Para faiz;
}

class FaizSonucu {
  const FaizSonucu({required this.anapara, required this.kalemler, required this.uyarilar});

  final Para anapara;
  final List<FaizKalemi> kalemler;
  final List<String> uyarilar;

  Para get toplamFaiz => kalemler.fold(Para.sifir, (t, k) => t + k.faiz);
  Para get toplam => anapara + toplamFaiz;
  int get toplamGun => kalemler.fold(0, (t, k) => t + k.gun);
}

/// Basit faiz: anapara × oran × gün / 365; oran değiştiğinde dönemlere bölünür.
class FaizHesaplayici {
  FaizHesaplayici._();

  /// [baslangic] temerrüt tarihi (faiz bu günden sonra işler), [bitis] hesap tarihi.
  static FaizSonucu hesapla({
    required Para anapara,
    required Tarih baslangic,
    required Tarih bitis,
    required FaizTablosu tablo,
  }) {
    if (bitis.isBefore(baslangic)) throw ArgumentError('Bitiş tarihi başlangıçtan önce olamaz.');
    final uyarilar = <String>[];
    if (tablo.onayDurumu != OnayDurumu.onayli) {
      uyarilar.add('${tablo.tur.ad} oran tablosu avukat onayı bekliyor.');
    }
    if (tablo.donem(baslangic) == null) {
      uyarilar.add('${baslangic.turkceBicim} için oran tanımlı değil; ilk tanımlı oran kullanıldı.');
    }

    // Dönem sınırlarını topla
    final sinirlar = <Tarih>[baslangic];
    for (final d in tablo.donemler) {
      if (d.baslangic.isAfter(baslangic) && d.baslangic.isBefore(bitis)) sinirlar.add(d.baslangic);
    }
    sinirlar.add(bitis);

    final kalemler = <FaizKalemi>[];
    for (var i = 0; i < sinirlar.length - 1; i++) {
      final bas = sinirlar[i];
      final bit = sinirlar[i + 1];
      final gun = bas.farkGun(bit);
      if (gun <= 0) continue;
      final donem = tablo.donem(bas) ?? tablo.donemler.first;
      kalemler.add(FaizKalemi(
        baslangic: bas,
        bitis: bit,
        gun: gun,
        oran: donem.yillikOran,
        faiz: anapara.carp(donem.yillikOran / 100 * gun / 365),
      ));
    }
    return FaizSonucu(anapara: anapara, kalemler: List.unmodifiable(kalemler), uyarilar: uyarilar);
  }
}
