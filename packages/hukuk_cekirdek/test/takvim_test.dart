import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Tarih', () {
    test('Geçersiz tarih reddedilir', () {
      expect(() => Tarih(2026, 2, 30), throwsArgumentError);
    });

    test('Ay ekleme artık yılı ve ay sonunu doğru işler', () {
      expect(Tarih(2028, 1, 31).ayEkle(1), Tarih(2028, 2, 29));
      expect(Tarih(2027, 1, 31).ayEkle(1), Tarih(2027, 2, 28));
      expect(Tarih(2026, 12, 15).ayEkle(1), Tarih(2027, 1, 15));
      expect(Tarih(2026, 3, 31).ayEkle(-1), Tarih(2026, 2, 28));
    });

    test('Haftanın günü ve Türkçe biçim', () {
      final t = Tarih(2026, 11, 25);
      expect(t.gunAdi, 'Çarşamba');
      expect(t.turkceBicim, '25.11.2026');
      expect(Tarih.parse('2026-11-25'), t);
    });
  });

  group('Türkiye tatil takvimi', () {
    final takvim = TurkiyeTatilleri.takvim([2026, 2027]);

    test('Sabit resmi tatiller', () {
      expect(takvim.tatil(Tarih(2026, 10, 29))?.tamGun, isTrue);
      expect(takvim.tatil(Tarih(2026, 10, 28))?.tur, TatilTuru.yarimGun);
      expect(takvim.tatil(Tarih(2026, 7, 15)), isNotNull);
    });

    test('Dini bayramlar ve arifeler', () {
      expect(takvim.tatil(Tarih(2027, 3, 8))?.tur, TatilTuru.yarimGun);
      expect(takvim.tatil(Tarih(2027, 3, 9))?.tur, TatilTuru.diniBayram);
      expect(takvim.tatil(Tarih(2026, 5, 27))?.tur, TatilTuru.diniBayram);
    });

    test('Çakışan günde tam gün tatil öncelikli', () {
      // 19 Mayıs 2027 hem Gençlik ve Spor Bayramı hem Kurban Bayramı
      expect(takvim.tatil(Tarih(2027, 5, 19))?.tamGun, isTrue);
    });

    test('Kapsanan yıllar', () {
      expect(takvim.kapsananYillar, {2026, 2027});
    });
  });

  group('Elektronik tebligat', () {
    test('Ulaşmayı izleyen beşinci gün tebliğ sayılır', () {
      expect(ElektronikTebligat.tebligTarihi(Tarih(2026, 11, 25)), Tarih(2026, 11, 30));
    });

    test('Ulaşma ve tebliğ tarihleri ayrı tutulur', () {
      final t = TebligatTarihleri.elektronik(Tarih(2026, 12, 28));
      expect(t.ulasma, Tarih(2026, 12, 28));
      expect(t.tebligEdilen, Tarih(2027, 1, 2));
    });
  });
}
