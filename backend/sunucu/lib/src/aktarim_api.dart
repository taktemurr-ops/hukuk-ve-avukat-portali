import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'belge_servisi.dart';
import 'guvenlik.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'virus_tarama.dart';

/// Excel (.xlsx) aktarımı: dosya saklanmaz; zararlı yazılım taramasından sonra iç ağdaki belge servisine
/// (Türkiye'de, dışarıya kapalı) okutulur ve satırlar önizleme için istemciye döner. Kayıtlar ancak kullanıcı
/// önizlemeyi onaylayınca `/kisiler/toplu` ile eklenir.
class AktarimApi {
  AktarimApi({this.belgeServisi, this.tarayici, this.azamiBoyut = 10 * 1024 * 1024});

  /// İç ağdaki belge servisi; yoksa Excel okuma kapalıdır.
  final BelgeServisi? belgeServisi;
  final VirusTarayici? tarayici;
  final int azamiBoyut;

  Router get router => Router()..post('/aktarim/tablo', _tablo);

  Future<Response> _tablo(Request istek) async {
    kimlik(istek); // oturum zorunlu (ara katman zaten denetler)
    final servis = belgeServisi;
    if (servis == null) {
      throw const ApiHatasi(503, 'Excel okuma bu kurulumda açık değil. Dosyayı CSV olarak kaydedip yapıştırın.',
          kod: 'hizmet_yok');
    }
    final ad = basliktanCoz(istek.headers['x-dosya-adi'] ?? 'tablo.xlsx').split(RegExp(r'[/\\]')).last;
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

    return jsonYanit(await servis.tablo(ad, icerik));
  }
}
