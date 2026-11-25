import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Argon2id şifre özeti (PHC biçimi: `$argon2id$v=19$m=...,t=...,p=...$tuz$özet`).
/// Veritabanı yalnızca bu biçimi kabul eder; düz şifre hiçbir yerde saklanmaz.
class SifreOzeti {
  SifreOzeti._();

  static const bellekKib = 65536;
  static const tekrar = 3;
  static const paralel = 4;
  static const uzunluk = 32;

  static String _b64(List<int> b) => base64.encode(b).replaceAll('=', '');

  static Uint8List _b64Coz(String s) => base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));

  static (Uint8List, Uint8List)? _cozBase64Cifti(String a, String b) {
    try {
      return (_b64Coz(a), _b64Coz(b));
    } on FormatException {
      return null;
    }
  }

  static Uint8List _hesapla(String sifre, Uint8List tuz, int m, int t, int p, int uzunluk) {
    final parametreler = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      tuz,
      desiredKeyLength: uzunluk,
      iterations: t,
      memory: m,
      lanes: p,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );
    final uretec = Argon2BytesGenerator()..init(parametreler);
    return uretec.process(Uint8List.fromList(utf8.encode(sifre)));
  }

  static String olustur(String sifre, {Random? rastgele, Uint8List? tuz}) {
    final r = rastgele ?? Random.secure();
    final t = tuz ?? Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
    final ozet = _hesapla(sifre, t, bellekKib, tekrar, paralel, uzunluk);
    return '\$argon2id\$v=19\$m=$bellekKib,t=$tekrar,p=$paralel\$${_b64(t)}\$${_b64(ozet)}';
  }

  /// Sabit zamanlı karşılaştırma ile doğrular; biçim bozuksa false.
  static bool dogrula(String sifre, String kayitli) {
    final parca = kayitli.split('\$');
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', tuz, özet]
    if (parca.length != 6 || parca[1] != 'argon2id' || parca[2] != 'v=19') return false;
    final ayar = <String, int>{};
    for (final kv in parca[3].split(',')) {
      final i = kv.indexOf('=');
      if (i < 1) return false;
      final deger = int.tryParse(kv.substring(i + 1));
      if (deger == null) return false;
      ayar[kv.substring(0, i)] = deger;
    }
    final m = ayar['m'], t = ayar['t'], p = ayar['p'];
    if (m == null || t == null || p == null) return false;
    final cozulmus = _cozBase64Cifti(parca[4], parca[5]);
    if (cozulmus == null) return false;
    final (tuz, beklenen) = cozulmus;
    final hesap = _hesapla(sifre, tuz, m, t, p, beklenen.length);
    var fark = 0;
    for (var i = 0; i < beklenen.length; i++) {
      fark |= hesap[i] ^ beklenen[i];
    }
    return fark == 0;
  }
}
