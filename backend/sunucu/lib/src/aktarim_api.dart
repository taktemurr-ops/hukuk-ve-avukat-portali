import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'kimlik_api.dart';
import 'virus_tarama.dart';

/// Excel (.xlsx) aktarımı: dosya saklanmaz; zararlı yazılım taramasından sonra iç ağdaki belge servisine
/// (Türkiye'de, dışarıya kapalı) okutulur ve satırlar önizleme için istemciye döner. Kayıtlar ancak kullanıcı
/// önizlemeyi onaylayınca `/kisiler/toplu` ile eklenir.
class AktarimApi {
  AktarimApi({this.belgeServisi, this.tarayici, this.azamiBoyut = 10 * 1024 * 1024, HttpClient? istemci})
      : _istemci = istemci ?? HttpClient();

  /// Belge servisinin iç adresi (ör. http://belge:8090/); yoksa Excel okuma kapalıdır.
  final Uri? belgeServisi;
  final VirusTarayici? tarayici;
  final int azamiBoyut;
  final HttpClient _istemci;

  Router get router => Router()..post('/aktarim/tablo', _tablo);

  Future<Response> _tablo(Request istek) async {
    kimlik(istek); // oturum zorunlu (ara katman zaten denetler)
    final servis = belgeServisi;
    if (servis == null) {
      throw const ApiHatasi(503, 'Excel okuma bu kurulumda açık değil. Dosyayı CSV olarak kaydedip yapıştırın.',
          kod: 'hizmet_yok');
    }
    final ad = Uri.decodeComponent(istek.headers['x-dosya-adi'] ?? 'tablo.xlsx').split(RegExp(r'[/\\]')).last;
    final b = BytesBuilder(copy: false);
    await for (final parca in istek.read()) {
      b.add(parca);
      if (b.length > azamiBoyut) throw ApiHatasi(413, 'Dosya ${azamiBoyut ~/ (1024 * 1024)} MB sınırını aşıyor.');
    }
    final icerik = b.takeBytes();
    if (icerik.isEmpty) throw const ApiHatasi(400, 'Dosya boş.', kod: 'gecersiz_dosya');
    final t = tarayici;
    if (t != null) {
      final s = await t.tara(icerik);
      if (s.bulgu != null) throw ApiHatasi(400, 'Dosyada zararlı içerik bulundu (${s.bulgu}).', kod: 'zararli_dosya');
    }

    // multipart/form-data gövdesi (alan adı "dosya").
    final sinir = 'hukuk${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final gvd = BytesBuilder(copy: false)
      ..add(utf8.encode('--$sinir\r\nContent-Disposition: form-data; name="dosya"; filename="${ad.replaceAll('"', '')}"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n'))
      ..add(icerik)
      ..add(utf8.encode('\r\n--$sinir--\r\n'));
    final govde = gvd.takeBytes();
    final HttpClientResponse yanit;
    try {
      final r = await _istemci.postUrl(servis.resolve('tablo')).timeout(const Duration(seconds: 10));
      r.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': sinir});
      r.contentLength = govde.length;
      r.add(govde);
      yanit = await r.close().timeout(const Duration(seconds: 60));
    } on Exception {
      throw const ApiHatasi(503, 'Belge servisine ulaşılamadı; biraz sonra yeniden deneyin.', kod: 'hizmet_yok');
    }
    final metin = await utf8.decodeStream(yanit);
    final j = jsonDecode(metin);
    if (yanit.statusCode == 422) {
      throw ApiHatasi(400, '${(j as Map)['detail']}', kod: 'gecersiz_dosya');
    }
    if (yanit.statusCode != 200) {
      throw const ApiHatasi(502, 'Belge servisi dosyayı okuyamadı.', kod: 'hizmet_hatasi');
    }
    return jsonYanit(j);
  }
}
