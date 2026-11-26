import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

/// 2010'dan beri açılmış davalar için geçmiş tarifeler ve takvimler.
void main() {
  group('Tatil takvimi 2010-2027', () {
    final takvim = TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar);

    test('2010-2027 arasındaki her yıl için veri var', () {
      expect(TurkiyeTatilleri.diniBayramVerisiOlanYillar, containsAll([for (var y = 2010; y <= 2027; y++) y]));
      expect(takvim.kapsananYillar.reduce((a, b) => a < b ? a : b), 2010);
    });

    test('Geçmiş dini bayramlar (Türkiye takvimi)', () {
      expect(takvim.tatil(Tarih(2010, 9, 9))?.tur, TatilTuru.diniBayram);
      expect(takvim.tatil(Tarih(2010, 9, 8))?.tur, TatilTuru.yarimGun);
      expect(takvim.tatil(Tarih(2016, 9, 12))?.tur, TatilTuru.diniBayram);
      expect(takvim.tatil(Tarih(2021, 5, 13))?.tur, TatilTuru.diniBayram);
      expect(takvim.tatil(Tarih(2025, 6, 9))?.tur, TatilTuru.diniBayram);
    });

    test('15 Temmuz 2017\'den itibaren tatil', () {
      expect(takvim.tatil(Tarih(2016, 7, 15)), isNull);
      expect(takvim.tatil(Tarih(2018, 7, 15)), isNotNull);
    });

    test('2010 Kurban Bayramına denk gelen süre bayram sonrasına kayar', () {
      final h = SureHesaplayici(takvim);
      final s = h.hesapla(kural: KuralKatalogu.bul('IIK_ODEME_EMRINE_ITIRAZ')!.onayla('test'), baslangic: Tarih(2010, 11, 9));
      // 16 Kasım Salı bayram -> 19 Kasım'a kadar bayram, 20-21 hafta sonu -> 22 Kasım Pazartesi
      expect(s.sonGun, Tarih(2010, 11, 22));
    });
  });

  group('Adli tatil yıllara göre', () {
    test('HUMK döneminde 5 Eylül, sonra 31 Ağustos', () {
      expect(AdliTatil.donem(2010), (Tarih(2010, 7, 20), Tarih(2010, 9, 5)));
      expect(AdliTatil.donem(2012), (Tarih(2012, 7, 20), Tarih(2012, 8, 31)));
    });

    test('2010 adli tatilinde biten süre 5 Eylül\'den itibaren uzar', () {
      final h = SureHesaplayici(TurkiyeTatilleri.takvim([2010]));
      final s = h.hesapla(kural: KuralKatalogu.bul('HMK_ISTINAF')!.onayla('test'), baslangic: Tarih(2010, 8, 20));
      // Ham son gün 3 Eylül -> 5 Eylül + 7 = 12 Eylül Pazar -> 13 Eylül Pazartesi
      expect(s.sonGun, Tarih(2010, 9, 13));
    });
  });

  group('AAÜT 2009-2027', () {
    test('Tarifeler eskiden yeniye sıralı ve tarihe göre seçilir', () {
      final t = AvukatlikUcretTarifesi.tumu;
      for (var i = 1; i < t.length; i++) {
        expect(t[i].yururluk.isAfter(t[i - 1].yururluk), isTrue, reason: t[i].ad);
      }
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2010, 6, 1)).ad, '2009-2010 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2010, 12, 3)).ad, '2010-2011 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2015, 6, 1)).ad, '2015 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2023, 1, 1)).ad, '2022-2023 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2025, 1, 1)).ad, '2024-2025 AAÜT');
    });

    test('Her tarifede dört mahkeme için maktu ücret var', () {
      for (final t in AvukatlikUcretTarifesi.tumu) {
        expect(t.maktu.keys, containsAll(MahkemeTuru.values), reason: t.ad);
      }
    });

    test('2012 tarifesinde nispi ücret', () {
      final t = AvukatlikUcretTarifesi.gecerli(Tarih(2012, 6, 1));
      // 25.000 x %12 + 35.000 x %11 + 40.000 x %8
      expect(t.nispiHesapla(Para.tl(100000)).$1, Para.tl(10050));
      expect(t.hesapla(deger: Para.tl(5000), mahkeme: MahkemeTuru.asliye).sonuc, Para.tl(1200));
    });

    test('2020 tarifesinde ilk dilim %15', () {
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2020, 6, 1)).nispiHesapla(Para.tl(40000)).$1, Para.tl(6000));
    });
  });

  group('Kısmi kabul / kısmi ret (AAÜT)', () {
    final hukum = Tarih(2026, 11, 25);

    test('Davalı ücreti davacı ücretini geçemez', () {
      final k = AvukatlikUcretTarifesi.kismiKabulRed(
          talep: Para.tl(1000000), kabul: Para.tl(50000), hukumTarihi: hukum, mahkeme: MahkemeTuru.asliye);
      expect(k.davaciUcreti, Para.tl(50000));
      expect(k.davaliHesap!.sonuc, Para.tl(150500));
      expect(k.davaliUcreti, Para.tl(50000));
      expect(k.ret, Para.tl(950000));
    });

    test('Manevi tazminatta kısmi ret: AYM kararı sonrası davalı lehine ücret yok', () {
      final k = AvukatlikUcretTarifesi.kismiKabulRed(
          talep: Para.tl(1000000),
          kabul: Para.tl(100000),
          hukumTarihi: hukum,
          mahkeme: MahkemeTuru.asliye,
          maneviTazminat: true);
      expect(k.davaciUcreti, Para.tl(62000));
      expect(k.davaliUcreti, Para.sifir);
      expect(k.aciklamalar.any((a) => a.contains('2024/226')), isTrue);
    });

    test('Manevi tazminatta AYM kararından önceki hükümde sınırlı davalı ücreti', () {
      final k = AvukatlikUcretTarifesi.kismiKabulRed(
          talep: Para.tl(1000000),
          kabul: Para.tl(100000),
          hukumTarihi: Tarih(2025, 3, 13),
          mahkeme: MahkemeTuru.asliye,
          maneviTazminat: true);
      expect(k.tarife.ad, '2024-2025 AAÜT');
      expect(k.davaliUcreti, k.davaciUcreti);
      expect(k.davaliUcreti.sifirMi, isFalse);
    });

    test('Davanın tamamen reddi', () {
      final maddi = AvukatlikUcretTarifesi.kismiKabulRed(
          talep: Para.tl(300000), kabul: Para.sifir, hukumTarihi: hukum, mahkeme: MahkemeTuru.asliye);
      expect(maddi.davaciUcreti, Para.sifir);
      expect(maddi.davaliUcreti, Para.tl(62000));
      final manevi = AvukatlikUcretTarifesi.kismiKabulRed(
          talep: Para.tl(300000), kabul: Para.sifir, hukumTarihi: hukum, maneviTazminat: true);
      expect(manevi.davaliUcreti, Para.tl(62000));
    });

    test('Tamamen kabulde davalı ücreti yok, kabul talepten büyük olamaz', () {
      final k = AvukatlikUcretTarifesi.kismiKabulRed(talep: Para.tl(100000), kabul: Para.tl(100000), hukumTarihi: hukum);
      expect(k.davaliUcreti, Para.sifir);
      expect(
          () => AvukatlikUcretTarifesi.kismiKabulRed(talep: Para.tl(1), kabul: Para.tl(2), hukumTarihi: hukum),
          throwsArgumentError);
    });
  });

  group('Harçlar 2010-2026', () {
    test('Dava tarihine göre harç tarifesi', () {
      expect(HarcTarifesi.gecerli(Tarih(2010, 5, 1)).basvurmaAsliye, 17.10);
      expect(HarcTarifesi.gecerli(Tarih(2023, 7, 14)).basvurmaAsliye, 179.90);
      expect(HarcTarifesi.gecerli(Tarih(2023, 7, 15)).basvurmaAsliye, 269.85);
      expect(HarcTarifesi.gecerli(Tarih(2026, 11, 25)).basvurmaAsliye, 732.00);
      final t = HarcTarifesi.tumu;
      for (var i = 1; i < t.length; i++) {
        expect(t[i].yururluk.isAfter(t[i - 1].yururluk), isTrue);
      }
    });

    test('2011 nispi harç binde 59,40', () {
      final d = HarcTarifesi.gecerli(Tarih(2011, 6, 1)).davaAcilisi(mahkeme: MahkemeTuru.asliye, deger: Para.tl(100000));
      expect(d.basvurma, Para.tl(18.40));
      expect(d.pesinKararHarci, Para.tl(1485));
      expect(d.kalanKararHarci, Para.tl(4455));
    });

    test('İcra tahsil harcı oranları 2012\'de değişti', () {
      expect(IcraHarcTarifesi.gecerli(Tarih(2011, 6, 1)).tahsilOranlari[TahsilAsamasi.hacizdenOnce], 3.96);
      expect(IcraHarcTarifesi.gecerli(Tarih(2012, 6, 1)).tahsilOranlari[TahsilAsamasi.hacizdenOnce], 4.55);
      expect(IcraHarcTarifesi.gecerli(Tarih(2015, 6, 1)).basvurmaHarci, Para.tl(27.70));
    });

    test('Eski takipte açılış harcı takip tarihindeki tarifeyle', () {
      final talep = TakipTalebi(
          tur: TakipTuru.ilamsiz,
          asilAlacak: Para.tl(10000),
          temerrutTarihi: Tarih(2015, 1, 1),
          takipTarihi: Tarih(2015, 3, 2));
      final a = IcraHesabi.acilisHarclari(talep, Para.sifir);
      expect(a.basvurma, Para.tl(27.70));
      expect(a.pesin, Para.tl(50));
    });
  });

  group('Kıdem tavanı ve avans faizi 2010+', () {
    test('Kıdem tavanı', () {
      expect(KidemTavanlari.tavan(Tarih(2010, 3, 1)), Para.tl(2427.04));
      expect(KidemTavanlari.tavan(Tarih(2015, 8, 31)), Para.tl(3709.98));
      expect(KidemTavanlari.tavan(Tarih(2015, 9, 1)), Para.tl(3828.37));
      expect(KidemTavanlari.tavan(Tarih(2021, 12, 31)), Para.tl(8284.51));
    });

    test('Avans faizi', () {
      expect(FaizTablosu.avans.donem(Tarih(2010, 6, 1))?.yillikOran, 16);
      expect(FaizTablosu.avans.donem(Tarih(2012, 7, 1))?.yillikOran, 16.5);
      expect(FaizTablosu.avans.donem(Tarih(2014, 6, 1))?.yillikOran, 11.75);
    });
  });
}
