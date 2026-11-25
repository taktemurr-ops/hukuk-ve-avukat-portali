import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

SureKurali _kural(String kod) => KuralKatalogu.bul(kod)!.onayla('test');

void main() {
  final takvim = TurkiyeTatilleri.takvim([2026, 2027, 2028]);
  final hesaplayici = SureHesaplayici(takvim);

  group('Temel hesap', () {
    test('2 haftalık süre karşılık gelen günde biter', () {
      final s = hesaplayici.hesapla(kural: _kural('HMK_ISTINAF'), baslangic: Tarih(2026, 11, 25));
      expect(s.sonGun, Tarih(2026, 12, 9));
      expect(s.uyarilar, isEmpty);
    });

    test('Başlangıç günü sayılmaz, gün olarak süre', () {
      final s = hesaplayici.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 11, 26));
      // 26 Kasım Perşembe + 7 gün = 3 Aralık Perşembe
      expect(s.sonGun, Tarih(2026, 12, 3));
    });

    test('Hafta sonuna denk gelen süre pazartesiye kayar', () {
      final s = hesaplayici.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 11, 28));
      // 5 Aralık Cumartesi -> 7 Aralık Pazartesi
      expect(s.sonGun, Tarih(2026, 12, 7));
    });

    test('Resmi tatile denk gelen süre ilk iş gününe kayar', () {
      final s = hesaplayici.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 10, 22));
      // 29 Ekim Perşembe Cumhuriyet Bayramı -> 30 Ekim Cuma
      expect(s.sonGun, Tarih(2026, 10, 30));
    });

    test('Ay olarak süre, hedef ayda gün yoksa ayın son günü', () {
      final s = hesaplayici.hesapla(kural: _kural('IS_K_ISE_IADE_ARABULUCU'), baslangic: Tarih(2027, 1, 31));
      // 28 Şubat 2027 Pazar -> 1 Mart 2027 Pazartesi
      expect(s.sonGun, Tarih(2027, 3, 1));
    });
  });

  group('Adli tatil', () {
    test('Adli tatilde biten süre bitişten itibaren bir hafta uzar', () {
      final s = hesaplayici.hesapla(kural: _kural('HMK_ISTINAF'), baslangic: Tarih(2026, 7, 25));
      // Ham son gün 8 Ağustos -> 31 Ağustos + 7 = 7 Eylül 2026 Pazartesi
      expect(s.sonGun, Tarih(2026, 9, 7));
      expect(s.adimlar.any((a) => a.aciklama.contains('adli tatil')), isTrue);
    });

    test('Adli tatile tabi olmayan süre uzamaz', () {
      final s = hesaplayici.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 7, 25));
      // 1 Ağustos Cumartesi -> 3 Ağustos Pazartesi
      expect(s.sonGun, Tarih(2026, 8, 3));
    });
  });

  group('Yarım gün tatil (arife)', () {
    test('Varsayılan ayarda arife günü süre kaymaz', () {
      final s = hesaplayici.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 5, 19));
      expect(s.sonGun, Tarih(2026, 5, 26));
    });

    test('Arife erteler ayarında bayram ve hafta sonu boyunca kayar', () {
      final h = SureHesaplayici(takvim, ayarlar: const HesapAyarlari(yarimGunTatilErtelerMi: true));
      final s = h.hesapla(kural: _kural('IIK_ODEME_EMRINE_ITIRAZ'), baslangic: Tarih(2026, 5, 19));
      // 26 Mayıs arife -> 27-30 Mayıs Kurban Bayramı -> 31 Mayıs Pazar -> 1 Haziran Pazartesi
      expect(s.sonGun, Tarih(2026, 6, 1));
    });
  });

  group('Güvenlik kuralları', () {
    test('Taslak kural varsayılan olarak hesaplanmaz', () {
      expect(
        () => hesaplayici.hesapla(kural: KuralKatalogu.bul('HMK_ISTINAF')!, baslangic: Tarih(2026, 11, 25)),
        throwsStateError,
      );
    });

    test('Taslak kurala izin verilirse uyarı eklenir', () {
      final h = SureHesaplayici(takvim, ayarlar: const HesapAyarlari(taslakKuralaIzinVer: true));
      final s = h.hesapla(kural: KuralKatalogu.bul('HMK_ISTINAF')!, baslangic: Tarih(2026, 11, 25));
      expect(s.uyarilar, isNotEmpty);
    });

    test('Tatil verisi olmayan yıl için uyarı verilir', () {
      final s = hesaplayici.hesapla(kural: _kural('HMK_ISTINAF'), baslangic: Tarih(2031, 3, 3));
      expect(s.uyarilar.any((u) => u.contains('2031')), isTrue);
    });

    test('Her hesap teyit gerektirir ve gerekçesini taşır', () {
      final s = hesaplayici.hesapla(kural: _kural('HMK_ISTINAF'), baslangic: Tarih(2026, 11, 25));
      expect(s.teyitGerekir, isTrue);
      expect(s.adimlar.first.aciklama, contains('HMK m.345'));
      expect(s.adimlar.last.tarih, s.sonGun);
    });

    test('Katalogdaki tüm kurallar taslak başlar', () {
      for (final k in KuralKatalogu.tohumKurallar) {
        expect(k.onayDurumu, OnayDurumu.taslak, reason: k.kod);
      }
    });
  });
}
