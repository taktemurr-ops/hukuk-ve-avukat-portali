import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-256-GCM ile alan şifreleme (ör. TOTP sırları). Anahtar ortam değişkeninden gelir ve veritabanında durmaz.
/// Çıktı: 12 bayt nonce + şifreli metin + 16 bayt doğrulama etiketi. [baglam] ek doğrulanmış veridir
/// (ör. kullanıcı kimliği): bir kullanıcının şifreli sırrı başka kullanıcının satırına taşınırsa çözülmez.
class AlanSifreleyici {
  AlanSifreleyici(List<int> anahtar) : _anahtar = Uint8List.fromList(anahtar) {
    if (anahtar.length != 32) throw ArgumentError('Anahtar 32 bayt (AES-256) olmalı.');
  }

  /// Base64 kodlu 32 baytlık anahtar (ör. `openssl rand -base64 32`).
  factory AlanSifreleyici.base64(String anahtar) => AlanSifreleyici(base64Decode(anahtar.trim()));

  final Uint8List _anahtar;
  final Random _rastgele = Random.secure();

  GCMBlockCipher _sifre(bool sifrele, Uint8List nonce, String baglam) => GCMBlockCipher(AESEngine())
    ..init(sifrele, AEADParameters(KeyParameter(_anahtar), 128, nonce, Uint8List.fromList(utf8.encode(baglam))));

  Uint8List sifrele(List<int> acik, {required String baglam}) {
    final nonce = Uint8List.fromList(List.generate(12, (_) => _rastgele.nextInt(256)));
    final cikti = _sifre(true, nonce, baglam).process(Uint8List.fromList(acik));
    return Uint8List.fromList([...nonce, ...cikti]);
  }

  /// Etiket doğrulanmazsa (anahtar, bağlam veya veri değişmişse) [ArgumentError] fırlatır.
  Uint8List coz(List<int> sifreli, {required String baglam}) {
    if (sifreli.length < 12 + 16) throw ArgumentError('Şifreli veri bozuk.');
    final b = Uint8List.fromList(sifreli);
    try {
      return _sifre(false, b.sublist(0, 12), baglam).process(b.sublist(12));
    } on InvalidCipherTextException {
      throw ArgumentError('Şifreli veri doğrulanamadı.');
    }
  }
}
