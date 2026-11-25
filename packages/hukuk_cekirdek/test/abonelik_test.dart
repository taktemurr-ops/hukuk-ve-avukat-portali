import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final buro = Paket.taslakPaketler[HesapTuru.avukatlikBurosu]!;
  final hukuk = Paket.taslakPaketler[HesapTuru.hukukBurosu]!;
  final kurumsal = Paket.taslakPaketler[HesapTuru.kurumsal]!;

  group('Paket', () {
    test('aylık ve yıllık tutar', () {
      expect(buro.donemTutari(OdemeDonemi.aylik).kurus, 100000);
      expect(buro.donemTutari(OdemeDonemi.yillik).kurus, 1000000);
      expect(hukuk.donemTutari(OdemeDonemi.aylik, ucretliKoltuk: 4).kurus, 600000);
      expect(() => kurumsal.donemTutari(OdemeDonemi.aylik), throwsStateError);
    });
    test('KDV %20', () {
      final f = FaturaTutari.hesapla(Para.tl(1500));
      expect(f.kdv.kurus, 30000);
      expect(f.toplam.kurus, 180000);
    });
  });

  group('Abonelik', () {
    test('deneme 14 gün sonra askıya düşer, veri salt okunur', () {
      final a = Abonelik.denemeBaslat(buro, Tarih(2026, 12, 1));
      expect(a.donemSonu, Tarih(2026, 12, 15));
      a.gunlukKontrol(Tarih(2026, 12, 14));
      expect(a.durum, AbonelikDurumu.deneme);
      a.gunlukKontrol(Tarih(2026, 12, 15));
      expect(a.durum, AbonelikDurumu.askida);
      expect(a.yazilabilir, isFalse);
    });

    test('denemede ödeme bugünden dönem başlatır; yenileme dönem sonundan devam eder', () {
      final a = Abonelik.denemeBaslat(buro, Tarih(2026, 12, 1));
      a.odemeAlindi(Tarih(2026, 12, 10));
      expect(a.durum, AbonelikDurumu.aktif);
      expect(a.donemSonu, Tarih(2027, 1, 10));
      a.odemeAlindi(Tarih(2027, 1, 8));
      expect(a.donemSonu, Tarih(2027, 2, 10));
    });

    test('başarısız ödeme: 1-3-7. gün tekrar, 7 günden sonra askı', () {
      final a = Abonelik.denemeBaslat(buro, Tarih(2026, 12, 1))..odemeAlindi(Tarih(2026, 12, 1));
      a.odemeBasarisiz(Tarih(2027, 1, 1));
      expect(a.durum, AbonelikDurumu.odemeBekliyor);
      expect(a.yazilabilir, isTrue);
      expect(a.sonrakiDeneme(Tarih(2027, 1, 1)), Tarih(2027, 1, 2));
      expect(a.sonrakiDeneme(Tarih(2027, 1, 2)), Tarih(2027, 1, 4));
      expect(a.sonrakiDeneme(Tarih(2027, 1, 8)), isNull);
      a.gunlukKontrol(Tarih(2027, 1, 8));
      expect(a.durum, AbonelikDurumu.odemeBekliyor);
      a.gunlukKontrol(Tarih(2027, 1, 9));
      expect(a.durum, AbonelikDurumu.askida);
      a.odemeAlindi(Tarih(2027, 1, 10));
      expect(a.durum, AbonelikDurumu.aktif);
      expect(a.donemSonu, Tarih(2027, 2, 10));
    });

    test('iptal dönem sonunda geçerli olur', () {
      final a = Abonelik.denemeBaslat(buro, Tarih(2026, 12, 1))..odemeAlindi(Tarih(2026, 12, 1));
      a.iptalEt();
      a.gunlukKontrol(Tarih(2026, 12, 31));
      expect(a.durum, AbonelikDurumu.aktif);
      a.gunlukKontrol(Tarih(2027, 1, 1));
      expect(a.durum, AbonelikDurumu.iptal);
    });

    test('koltuk artışı kalan gün oranında faturalanır', () {
      final a = Abonelik.denemeBaslat(hukuk, Tarih(2027, 1, 1))..odemeAlindi(Tarih(2027, 1, 1));
      a.ucretliKoltuk = 2;
      // 31 günlük dönemin 10 günü kalmış: 1 koltuk × 1500 × 10/31 = 483,87
      expect(a.koltukDegistir(3, Tarih(2027, 1, 22)).kurus, 48387);
      expect(a.koltukDegistir(2, Tarih(2027, 1, 23)), Para.sifir);
      expect(() => Abonelik.denemeBaslat(buro, Tarih(2027, 1, 1)).koltukDegistir(2, Tarih(2027, 1, 2)),
          throwsStateError);
    });
  });
}
