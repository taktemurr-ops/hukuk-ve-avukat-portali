/// Hukuk ve Avukat Portalı uygulama sunucusu.
library;

import 'package:shelf/shelf.dart';

import 'src/dosya_api.dart';
import 'src/hata.dart';
import 'src/is_api.dart';
import 'src/kimlik_api.dart';
import 'src/kurumsal_api.dart';
import 'src/uyum_api.dart';
import 'src/veritabani.dart';

export 'src/dosya_api.dart';
export 'src/hata.dart';
export 'src/is_api.dart';
export 'src/kimlik_api.dart';
export 'src/kurumsal_api.dart';
export 'src/sifre.dart';
export 'src/uyum_api.dart';
export 'src/veritabani.dart';

/// Yalnızca izin verilen web kökenlerine CORS izni (ör. https://app.hukukportali.com.tr).
Middleware cors(Set<String> izinliKokenler) => (ic) => (istek) async {
      final koken = istek.headers['origin'];
      final izinli = koken != null && izinliKokenler.contains(koken);
      final basliklar = izinli
          ? {
              'access-control-allow-origin': koken,
              'access-control-allow-headers': 'authorization, content-type',
              'access-control-allow-methods': 'GET, POST, PUT, DELETE',
              'vary': 'origin',
            }
          : <String, String>{};
      if (istek.method == 'OPTIONS') return Response(izinli ? 204 : 403, headers: basliklar);
      final yanit = await ic(istek);
      return yanit.change(headers: basliklar);
    };

Handler uygulama(Veritabani vt, {Set<String> izinliKokenler = const {}, void Function(Object, StackTrace)? kaydet}) {
  final cascade = Cascade()
      .add((Request r) => r.url.path == 'saglik' ? jsonYanit({'durum': 'ok'}) : Response.notFound(null))
      .add(KimlikApi(vt).router.call)
      .add(DosyaApi(vt).router.call)
      .add(IsApi(vt).router.call)
      .add(KurumsalApi(vt).router.call)
      .add(UyumApi(vt).router.call);
  return const Pipeline()
      .addMiddleware(cors(izinliKokenler))
      .addMiddleware(hataVeGuvenlik(kaydet: kaydet))
      .addMiddleware(oturumDogrula(vt))
      .addHandler(cascade.handler);
}
