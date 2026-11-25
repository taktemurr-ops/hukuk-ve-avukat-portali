import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('E-posta', () {
    test('geçerli ve geçersiz adresler', () {
      expect(Dogrulayicilar.eposta('av.ayse@buro.com.tr'), isNull);
      expect(Dogrulayicilar.eposta(''), isNotNull);
      expect(Dogrulayicilar.eposta('ayse@buro'), isNotNull);
      expect(Dogrulayicilar.eposta('ayse buro@x.com'), isNotNull);
    });
  });

  group('Şifre politikası', () {
    test('uzunluk, harf ve rakam', () {
      expect(Dogrulayicilar.sifre('kisa1'), contains('10 karakter'));
      expect(Dogrulayicilar.sifre('1234567890'), contains('harf'));
      expect(Dogrulayicilar.sifre('sadeceharfler'), contains('rakam'));
      expect(Dogrulayicilar.sifre('Guclu2026Sifre'), isNull);
    });

    test('e-postanın kullanıcı adını içeremez', () {
      expect(Dogrulayicilar.sifre('ayseyilmaz2026', eposta: 'ayseyilmaz@buro.com'), isNotNull);
      expect(Dogrulayicilar.sifre('Mavi2026Deniz', eposta: 'ayseyilmaz@buro.com'), isNull);
    });
  });

  group('Telefon', () {
    test('Türkiye cep telefonu biçimleri', () {
      expect(Dogrulayicilar.cepTelefonu('0532 123 45 67'), isNull);
      expect(Dogrulayicilar.cepTelefonu('+905321234567'), isNull);
      expect(Dogrulayicilar.cepTelefonu('5321234567'), isNull);
      expect(Dogrulayicilar.cepTelefonu('0212 123 45 67'), isNotNull);
    });
  });

  group('TCKN ve VKN', () {
    test('TC kimlik numarası algoritması', () {
      expect(Dogrulayicilar.tcknGecerli('10000000146'), isTrue);
      expect(Dogrulayicilar.tcknGecerli('10000000147'), isFalse);
      expect(Dogrulayicilar.tcknGecerli('01234567890'), isFalse);
      expect(Dogrulayicilar.tcknGecerli('1234'), isFalse);
    });

    test('Vergi kimlik numarası algoritması', () {
      expect(Dogrulayicilar.vknGecerli('1234567890'), isTrue);
      expect(Dogrulayicilar.vknGecerli('9876543217'), isTrue);
      expect(Dogrulayicilar.vknGecerli('9876543210'), isFalse);
    });

    test('Fatura alanı TCKN veya VKN kabul eder', () {
      expect(Dogrulayicilar.tcknVeyaVkn('10000000146'), isNull);
      expect(Dogrulayicilar.tcknVeyaVkn('1234567890'), isNull);
      expect(Dogrulayicilar.tcknVeyaVkn('123'), isNotNull);
      expect(Dogrulayicilar.tcknVeyaVkn('10000000147'), contains('TC kimlik'));
    });
  });
}
