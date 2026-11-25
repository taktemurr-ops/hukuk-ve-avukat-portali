import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sunucudan dönen, kullanıcıya gösterilebilir hata.
class SunucuHatasi implements Exception {
  const SunucuHatasi(this.durum, this.kod, this.mesaj);

  final int durum;
  final String kod;
  final String mesaj;

  @override
  String toString() => mesaj;
}

/// Uygulama sunucusuyla HTTPS + JSON haberleşmesi. Oturum token'ı yalnızca bellekte tutulur.
class ApiIstemcisi {
  ApiIstemcisi(this.adres, {http.Client? istemci}) : _http = istemci ?? http.Client();

  final Uri adres;
  final http.Client _http;
  String? token;

  static const _zamanAsimi = Duration(seconds: 30);

  Map<String, String> get _basliklar => {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Uri _yol(String yol) => adres.resolve(yol.startsWith('/') ? yol.substring(1) : yol);

  Future<Object?> get(String yol) async => _coz(await _http.get(_yol(yol), headers: _basliklar).timeout(_zamanAsimi));

  Future<Object?> post(String yol, [Map<String, Object?> govde = const {}]) async =>
      _coz(await _http.post(_yol(yol), headers: _basliklar, body: jsonEncode(govde)).timeout(_zamanAsimi));

  Future<Object?> delete(String yol) async =>
      _coz(await _http.delete(_yol(yol), headers: _basliklar).timeout(_zamanAsimi));

  Object? _coz(http.Response y) {
    final metin = utf8.decode(y.bodyBytes);
    Object? j;
    try {
      j = metin.isEmpty ? null : jsonDecode(metin);
    } on FormatException {
      j = null;
    }
    if (y.statusCode >= 200 && y.statusCode < 300) return j;
    if (j is Map<String, dynamic>) {
      throw SunucuHatasi(y.statusCode, '${j['hata'] ?? 'hata'}', '${j['mesaj'] ?? 'Sunucu hatası.'}');
    }
    throw SunucuHatasi(y.statusCode, 'hata', 'Sunucuya ulaşılamadı (${y.statusCode}).');
  }

  void kapat() => _http.close();
}
