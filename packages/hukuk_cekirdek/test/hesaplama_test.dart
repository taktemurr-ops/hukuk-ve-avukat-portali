import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Para', () {
    test('Kuruşa yarım yukarı yuvarlar ve Türkçe biçimler', () {
      expect(Para.tl(1234.565).kurus, 123457);
      expect(Para.tl(1234567.89).bicimli, '1.234.567,89 TL');
      expect(Para.tl(-50).bicimli, '-50,00 TL');
      expect(Para.tl(0.1) + Para.tl(0.2), Para.tl(0.3));
    });

    test('Farklı para birimleri toplanamaz', () {
      expect(() => Para.tl(1) + Para.tl(1, birim: 'USD'), throwsArgumentError);
    });
  });

  group('Faiz', () {
    test('Yasal faiz 31.07.2026 oran değişiminde dönemlere bölünür', () {
      final s = FaizHesaplayici.hesapla(
        anapara: Para.tl(100000),
        baslangic: Tarih(2026, 7, 1),
        bitis: Tarih(2026, 9, 29),
        tablo: FaizTablosu.yasal,
      );
      expect(s.kalemler, hasLength(2));
      expect(s.kalemler.first.oran, 24);
      expect(s.kalemler.first.gun, 30);
      expect(s.kalemler.first.faiz, Para.tl(1972.60));
      expect(s.kalemler.last.oran, 31);
      expect(s.kalemler.last.gun, 60);
      expect(s.kalemler.last.faiz, Para.tl(5095.89));
      expect(s.toplamFaiz, Para.tl(7068.49));
      expect(s.toplamGun, 90);
      expect(s.uyarilar.single, contains('onay'));
    });

    test('Sözleşmesel sabit oran', () {
      final s = FaizHesaplayici.hesapla(
        anapara: Para.tl(50000),
        baslangic: Tarih(2025, 1, 1),
        bitis: Tarih(2026, 1, 1),
        tablo: FaizTablosu.sabit(10),
      );
      expect(s.toplamFaiz, Para.tl(5000));
      expect(s.uyarilar, isEmpty);
    });

    test('Bitiş başlangıçtan önce olamaz', () {
      expect(
        () => FaizHesaplayici.hesapla(
            anapara: Para.tl(1), baslangic: Tarih(2026, 2, 1), bitis: Tarih(2026, 1, 1), tablo: FaizTablosu.yasal),
        throwsArgumentError,
      );
    });
  });

  group('Avukatlık ücreti (AAÜT)', () {
    final t26 = AvukatlikUcretTarifesi.tarife2026;

    test('2026-2027 tarifesinde dilimli nispi ücret', () {
      final (ucret, kalemler) = t26.nispiHesapla(Para.tl(2000000));
      expect(ucret, Para.tl(304000));
      expect(kalemler, hasLength(3));
      expect(t26.nispiHesapla(Para.tl(30000000)).$1, Para.tl(1708000));
    });

    test('2025-2026 tarifesi kaynaktaki örnekle aynı sonucu verir', () {
      expect(AvukatlikUcretTarifesi.tarife2025.nispiHesapla(Para.tl(900000)).$1, Para.tl(141000));
    });

    test('Nispi ücret maktu ücretin altına düşmez, hükmedilen miktarı geçmez', () {
      expect(t26.hesapla(deger: Para.tl(300000), mahkeme: MahkemeTuru.asliye).sonuc, Para.tl(62000));
      expect(t26.hesapla(deger: Para.tl(50000), mahkeme: MahkemeTuru.asliye).sonuc, Para.tl(50000));
      expect(t26.hesapla(deger: Para.tl(300000)).sonuc, Para.tl(48000));
    });

    test('Tarihe göre yürürlükteki tarife seçilir', () {
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2026, 11, 25)).ad, '2026-2027 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2026, 6, 1)).ad, '2025-2026 AAÜT');
      expect(AvukatlikUcretTarifesi.gecerli(Tarih(2026, 11, 3)).ad, '2026-2027 AAÜT');
    });

    test('Dilimlerin toplam genişliği tarifedeki %1 eşiğine eşittir', () {
      int toplam(AvukatlikUcretTarifesi t) => t.dilimler.where((d) => d.genislik != null).fold(0, (a, d) => a + d.genislik!);
      expect(toplam(t26), 24800000);
      expect(toplam(AvukatlikUcretTarifesi.tarife2025), 18600000);
    });
  });

  group('Dava harcı (2026)', () {
    const h = HarcTarifesi.y2026;

    test('Nispi harçlı davada dörtte bir peşin', () {
      final d = h.davaAcilisi(mahkeme: MahkemeTuru.asliye, deger: Para.tl(1000000));
      expect(d.basvurma, Para.tl(732));
      expect(d.pesinKararHarci, Para.tl(17077.50));
      expect(d.kalanKararHarci, Para.tl(51232.50));
      expect(d.acilistaOdenecek, Para.tl(17809.50));
    });

    test('Nispi harç asgari tutarın altına düşmez', () {
      final d = h.davaAcilisi(mahkeme: MahkemeTuru.asliye, deger: Para.tl(5000));
      expect(d.pesinKararHarci, Para.tl(183));
    });

    test('Maktu harçlı sulh davası', () {
      final d = h.davaAcilisi(mahkeme: MahkemeTuru.sulhHukuk);
      expect(d.basvurma, Para.tl(335.20));
      expect(d.pesinKararHarci, Para.tl(732));
      expect(d.kalanKararHarci, Para.sifir);
    });
  });
}
