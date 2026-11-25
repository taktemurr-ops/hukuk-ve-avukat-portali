import 'dart:convert';

import 'package:shelf/shelf.dart';

/// İstemciye gösterilebilir hata. Ayrıntı ve iz kayıtlara yazılır, istemciye gitmez.
class ApiHatasi implements Exception {
  const ApiHatasi(this.durum, this.mesaj, {this.kod = 'hata'});

  final int durum;
  final String mesaj;
  final String kod;

  static const yetkisiz = ApiHatasi(401, 'Oturum açmanız gerekiyor.', kod: 'yetkisiz');
  static const bulunamadi = ApiHatasi(404, 'Kayıt bulunamadı.', kod: 'bulunamadi');
}

Response jsonYanit(Object? govde, {int durum = 200}) => Response(
      durum,
      body: jsonEncode(govde),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<Map<String, dynamic>> jsonGovde(Request istek) async => jsonGovdeMetinden(await istek.readAsString());

Map<String, dynamic> jsonGovdeMetinden(String metin) {
  if (metin.length > 1024 * 1024) throw const ApiHatasi(413, 'İstek çok büyük.');
  try {
    final j = jsonDecode(metin);
    if (j is Map<String, dynamic>) return j;
  } on FormatException {
    // aşağıda
  }
  throw const ApiHatasi(400, 'Geçersiz JSON.', kod: 'gecersiz_istek');
}

String zorunluMetin(Map<String, dynamic> j, String alan) {
  final v = j[alan];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  throw ApiHatasi(400, '"$alan" alanı zorunludur.', kod: 'eksik_alan');
}

/// Hataları JSON'a çevirir, güvenlik başlıklarını ekler.
Middleware hataVeGuvenlik({void Function(Object hata, StackTrace iz)? kaydet}) => (ic) => (istek) async {
      Response yanit;
      try {
        yanit = await ic(istek);
      } on ApiHatasi catch (e) {
        yanit = jsonYanit({'hata': e.kod, 'mesaj': e.mesaj}, durum: e.durum);
      } catch (e, iz) {
        kaydet?.call(e, iz);
        yanit = jsonYanit({'hata': 'sunucu', 'mesaj': 'Beklenmeyen bir hata oluştu.'}, durum: 500);
      }
      return yanit.change(headers: {
        'x-content-type-options': 'nosniff',
        'x-frame-options': 'DENY',
        'referrer-policy': 'no-referrer',
        'cache-control': 'no-store',
        'strict-transport-security': 'max-age=31536000; includeSubDomains',
      });
    };
