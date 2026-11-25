import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Hizmet süresi', () {
    test('giriş ve çıkış günleri dahil', () {
      final s = HizmetSuresi.hesapla(Tarih(2020, 1, 1), Tarih(2022, 12, 31));
      expect((s.yil, s.ay, s.gun), (3, 0, 0));
      final t = HizmetSuresi.hesapla(Tarih(2023, 3, 15), Tarih(2026, 5, 20));
      expect((t.yil, t.ay, t.gun), (3, 2, 6));
    });

    test('çıkış girişten önce olamaz', () {
      expect(() => HizmetSuresi.hesapla(Tarih(2026, 1, 2), Tarih(2026, 1, 1)), throwsArgumentError);
    });
  });

  group('Kıdem', () {
    test('tavan altı ücret', () {
      final k = IscilikHesabi.kidem(giris: Tarih(2020, 1, 1), cikis: Tarih(2022, 12, 31), giydirilmisBrutUcret: Para.tl(10000));
      expect(k.tavanUygulandi, isFalse);
      expect(k.brut, Para.tl(30000));
      expect(k.damgaVergisi, Para.tl(227.70));
      expect(k.net, Para.tl(29772.30));
    });

    test('tavan uygulanır (çıkış tarihindeki tavan)', () {
      final k = IscilikHesabi.kidem(giris: Tarih(2016, 7, 1), cikis: Tarih(2026, 6, 30), giydirilmisBrutUcret: Para.tl(100000));
      expect(k.tavanUygulandi, isTrue);
      expect(k.esasUcret, Para.tl(64948.77));
      expect(k.brut, Para.tl(649487.70));
    });

    test('bir yıldan az çalışmada kıdem yok', () {
      expect(() => IscilikHesabi.kidem(giris: Tarih(2026, 1, 1), cikis: Tarih(2026, 6, 1), giydirilmisBrutUcret: Para.tl(1)),
          throwsArgumentError);
    });
  });

  group('İhbar ve izin', () {
    test('ihbar haftaları', () {
      expect(IscilikHesabi.ihbarHaftasi(const HizmetSuresi(0, 5, 29)), 2);
      expect(IscilikHesabi.ihbarHaftasi(const HizmetSuresi(1, 5, 0)), 4);
      expect(IscilikHesabi.ihbarHaftasi(const HizmetSuresi(2, 11, 0)), 6);
      expect(IscilikHesabi.ihbarHaftasi(const HizmetSuresi(3, 0, 0)), 8);
      final i = IscilikHesabi.ihbar(giris: Tarih(2020, 1, 1), cikis: Tarih(2022, 12, 31), giydirilmisBrutUcret: Para.tl(30000));
      expect(i.hafta, 8);
      expect(i.brut, Para.tl(56000));
    });

    test('yıllık izin hakkı', () {
      expect(IscilikHesabi.yillikIzinHakki(kidemYili: 0, yas: 30), 0);
      expect(IscilikHesabi.yillikIzinHakki(kidemYili: 3, yas: 30), 14);
      expect(IscilikHesabi.yillikIzinHakki(kidemYili: 3, yas: 52), 20);
      expect(IscilikHesabi.yillikIzinHakki(kidemYili: 10, yas: 30), 20);
      expect(IscilikHesabi.yillikIzinHakki(kidemYili: 15, yas: 30), 26);
      expect(IscilikHesabi.izinUcreti(kullanilmayanGun: 12, ciplakBrutUcret: Para.tl(30000)).brut, Para.tl(12000));
    });
  });

  group('Döviz', () {
    test('temerrütte alacaklı yüksek kuru seçer', () {
      final borc = Para.tl(1000, birim: 'USD');
      expect(DovizHesabi.borcKarsiligi(dovizTutari: borc, vadeKuru: 40, odemeKuru: 42, temerrut: false).$1, Para.tl(42000));
      final (tl, secim) = DovizHesabi.borcKarsiligi(dovizTutari: borc, vadeKuru: 45, odemeKuru: 42, temerrut: true);
      expect(tl, Para.tl(45000));
      expect(secim, contains('Vade'));
      expect(() => DovizHesabi.tlKarsiligi(Para.tl(1), 40), throwsArgumentError);
    });

    test('döviz temerrüt faizi döviz cinsinden', () {
      final f = DovizHesabi.temerrutFaizi(
          dovizTutari: Para.tl(10000, birim: 'EUR'), yillikOran: 3.65, baslangic: Tarih(2026, 1, 1), bitis: Tarih(2026, 4, 11));
      expect(f, Para.tl(100, birim: 'EUR'));
    });
  });

  test('avans faizi geçmişi tarih sırasında ve güncel oran', () {
    final d = FaizTablosu.avans.donemler;
    for (var i = 1; i < d.length; i++) {
      expect(d[i].baslangic.isAfter(d[i - 1].baslangic), isTrue);
    }
    expect(FaizTablosu.avans.donem(Tarih(2024, 6, 1))!.yillikOran, 51.75);
    expect(FaizTablosu.avans.donem(Tarih(2026, 11, 1))!.yillikOran, 39.75);
  });
}
