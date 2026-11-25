import 'dart:convert';
import 'dart:typed_data';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  // Beklenen değer Python argon2-cffi (referans C uygulaması) ile üretildi.
  const referans = r'$argon2id$v=19$m=65536,t=3,p=4$dHV6ZGVnZXJpMTIzNDU2Nw$TcE/1KkBTqBd4qRWm0jj6WTqRLXYGpGSzw2w8hAsDgY';

  test('referans uygulamayla aynı özet', () {
    final tuz = Uint8List.fromList(utf8.encode('tuzdegeri1234567'));
    expect(SifreOzeti.olustur('Gizli-Sifre-2026', tuz: tuz), referans);
  });

  test('doğrulama', () {
    expect(SifreOzeti.dogrula('Gizli-Sifre-2026', referans), isTrue);
    expect(SifreOzeti.dogrula('gizli-sifre-2026', referans), isFalse);
    expect(SifreOzeti.dogrula('x', r'$argon2i$v=19$m=1,t=1,p=1$YQ$YQ'), isFalse);
    expect(SifreOzeti.dogrula('x', 'duz-sifre'), isFalse);
    expect(SifreOzeti.dogrula('x', r'$argon2id$v=19$m=65536,t=3,p=4$!!!$###'), isFalse);
  });

  test('her özet farklı tuz kullanır', () {
    final a = SifreOzeti.olustur('ayni');
    final b = SifreOzeti.olustur('ayni');
    expect(a, isNot(b));
    expect(a, startsWith(r'$argon2id$v=19$m=65536,t=3,p=4$'));
    expect(SifreOzeti.dogrula('ayni', a), isTrue);
  });
}
