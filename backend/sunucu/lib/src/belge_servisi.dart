import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'hata.dart';

/// İç ağdaki Python belge servisinin (Türkiye'de, dışarıya kapalı) istemcisi: Excel okuma, Word üretme,
/// metin çıkarma/OCR. Hata durumunda kullanıcıya gösterilebilir [ApiHatasi] fırlatır.
class BelgeServisi {
  BelgeServisi(this.adres, {HttpClient? istemci}) : _istemci = istemci ?? HttpClient();

  final Uri adres;
  final HttpClient _istemci;

  Future<(int, List<int>, String?)> _gonder(String yol, List<int> govde, ContentType tur,
      {Duration zamanAsimi = const Duration(seconds: 60)}) async {
    try {
      final r = await _istemci.postUrl(adres.resolve(yol)).timeout(const Duration(seconds: 10));
      r.headers.contentType = tur;
      r.contentLength = govde.length;
      r.add(govde);
      final y = await r.close().timeout(zamanAsimi);
      final b = BytesBuilder(copy: false);
      await for (final p in y) {
        b.add(p);
      }
      return (y.statusCode, b.takeBytes().toList(), y.headers.value('x-eksik-alan-sayisi'));
    } on Exception {
      throw const ApiHatasi(503, 'Belge servisine ulaşılamadı; biraz sonra yeniden deneyin.', kod: 'hizmet_yok');
    }
  }

  Future<Object?> _dosyaGonder(String yol, String ad, List<int> icerik, {Duration? zamanAsimi}) async {
    final sinir = 'hukuk${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final gvd = BytesBuilder(copy: false)
      ..add(utf8.encode('--$sinir\r\nContent-Disposition: form-data; name="dosya"; filename="${ad.replaceAll('"', '')}"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n'))
      ..add(icerik)
      ..add(utf8.encode('\r\n--$sinir--\r\n'));
    final (durum, govde, _) = await _gonder(yol, gvd.takeBytes(),
        ContentType('multipart', 'form-data', parameters: {'boundary': sinir}),
        zamanAsimi: zamanAsimi ?? const Duration(seconds: 60));
    final j = _json(govde);
    if (durum == 422) throw ApiHatasi(400, '${(j as Map?)?['detail'] ?? 'Dosya okunamadı.'}', kod: 'gecersiz_dosya');
    if (durum != 200) throw const ApiHatasi(502, 'Belge servisi dosyayı işleyemedi.', kod: 'hizmet_hatasi');
    return j;
  }

  static Object? _json(List<int> b) {
    try {
      return jsonDecode(utf8.decode(b));
    } on FormatException {
      return null;
    }
  }

  /// .xlsx'in ilk sayfası: {"sayfa", "satirlar", "uyarilar"}.
  Future<Object?> tablo(String ad, List<int> icerik) => _dosyaGonder('tablo', ad, icerik);

  /// Metin çıkarma (gerekirse OCR): {"tur", "metin", "sayfaSayisi", "ocr", "uyarilar", ...}.
  Future<Map<String, dynamic>> metin(String ad, List<int> icerik) async =>
      ((await _dosyaGonder('metin', ad, icerik, zamanAsimi: const Duration(minutes: 5))) as Map).cast<String, dynamic>();

  /// Rapor tablolarından Excel ya da PDF. [sayfalar]: [{ad, basliklar, satirlar}].
  Future<List<int>> rapor(String baslik, List<Map<String, Object?>> sayfalar, {bool pdf = false}) async {
    final (durum, govde, _) = await _gonder('rapor',
        utf8.encode(jsonEncode({'baslik': baslik, 'sayfalar': sayfalar, 'bicim': pdf ? 'pdf' : 'xlsx'})), ContentType.json);
    if (durum == 422) {
      final j = _json(govde);
      throw ApiHatasi(400, '${(j is Map ? j['detail'] : null) ?? 'Rapor geçersiz.'}', kod: 'gecersiz_istek');
    }
    if (durum != 200) throw const ApiHatasi(502, 'Rapor dosyası üretilemedi.', kod: 'hizmet_hatasi');
    return govde;
  }

  /// Şablon metninden Word (ya da [pdf] ise PDF) belgesi; eksik alan işaretleri sarı vurgulanır.
  /// Dönen: (belge baytları, eksik alan sayısı).
  Future<(List<int>, int)> docx(String baslik, String metin, {bool pdf = false}) async {
    final (durum, govde, eksik) = await _gonder('docx',
        utf8.encode(jsonEncode({'baslik': baslik, 'metin': metin, 'bicim': pdf ? 'pdf' : 'docx'})), ContentType.json);
    if (durum == 422) throw const ApiHatasi(400, 'Belge metni geçersiz.', kod: 'gecersiz_istek');
    if (durum != 200) throw const ApiHatasi(502, 'Word belgesi üretilemedi.', kod: 'hizmet_hatasi');
    return (govde, int.tryParse(eksik ?? '') ?? 0);
  }
}
