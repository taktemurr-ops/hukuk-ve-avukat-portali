import 'dart:math';

import 'package:crypto/crypto.dart';

/// Zamana dayalı tek kullanımlık şifre (RFC 6238, HMAC-SHA1).
/// Google Authenticator, Microsoft Authenticator vb. uygulamalarla uyumludur.
///
/// Not: Web derlemesinde 64 bitlik bit işlemleri güvenli olmadığından
/// sayaç baytları aritmetikle üretilir.
class Totp {
  Totp._();

  static const _alfabe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String base32Kodla(List<int> baytlar) {
    final sb = StringBuffer();
    var tampon = 0;
    var bit = 0;
    for (final b in baytlar) {
      tampon = (tampon << 8) | (b & 0xff);
      bit += 8;
      while (bit >= 5) {
        sb.write(_alfabe[(tampon >> (bit - 5)) & 31]);
        bit -= 5;
      }
      tampon &= (1 << bit) - 1;
    }
    if (bit > 0) sb.write(_alfabe[(tampon << (5 - bit)) & 31]);
    return sb.toString();
  }

  static List<int> base32Coz(String metin) {
    final temiz = metin.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    final sonuc = <int>[];
    var tampon = 0;
    var bit = 0;
    for (final c in temiz.split('')) {
      final deger = _alfabe.indexOf(c);
      if (deger < 0) throw FormatException('Geçersiz base32 karakteri: $c');
      tampon = (tampon << 5) | deger;
      bit += 5;
      if (bit >= 8) {
        sonuc.add((tampon >> (bit - 8)) & 0xff);
        bit -= 8;
      }
      tampon &= (1 << bit) - 1;
    }
    return sonuc;
  }

  static List<int> _sayacBaytlari(int sayac) {
    final b = List<int>.filled(8, 0);
    var kalan = sayac;
    for (var i = 7; i >= 0; i--) {
      b[i] = kalan % 256;
      kalan = kalan ~/ 256;
    }
    return b;
  }

  static String hotp(List<int> sir, int sayac, {int hane = 6}) {
    final h = Hmac(sha1, sir).convert(_sayacBaytlari(sayac)).bytes;
    final o = h[h.length - 1] & 0x0f;
    final ikili = ((h[o] & 0x7f) << 24) | ((h[o + 1] & 0xff) << 16) | ((h[o + 2] & 0xff) << 8) | (h[o + 3] & 0xff);
    var bolen = 1;
    for (var i = 0; i < hane; i++) {
      bolen *= 10;
    }
    return (ikili % bolen).toString().padLeft(hane, '0');
  }

  static String kod(List<int> sir, DateTime zaman, {int adimSaniye = 30, int hane = 6}) =>
      hotp(sir, zaman.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ adimSaniye, hane: hane);

  /// Saat kaymasına karşı ±[pencere] adım kabul edilir.
  static bool dogrula(List<int> sir, String girilen, DateTime zaman, {int pencere = 1, int adimSaniye = 30}) {
    final temiz = girilen.replaceAll(' ', '');
    if (!RegExp(r'^\d{6}$').hasMatch(temiz)) return false;
    final sayac = zaman.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ adimSaniye;
    for (var d = -pencere; d <= pencere; d++) {
      if (hotp(sir, sayac + d) == temiz) return true;
    }
    return false;
  }

  /// 160 bitlik rastgele sır.
  static List<int> sirUret([Random? rastgele]) {
    final r = rastgele ?? Random.secure();
    return List<int>.generate(20, (_) => r.nextInt(256));
  }

  /// Doğrulayıcı uygulamanın okuyacağı QR içeriği.
  static String otpauthUri({required String yayinci, required String hesap, required List<int> sir}) =>
      'otpauth://totp/${Uri.encodeComponent('$yayinci:$hesap')}'
      '?secret=${base32Kodla(sir)}&issuer=${Uri.encodeComponent(yayinci)}&algorithm=SHA1&digits=6&period=30';
}
