/// Hukuk ve Avukat Portalı uygulama sunucusu.
library;

import 'package:shelf/shelf.dart';

import 'src/abonelik_api.dart';
import 'src/belge_api.dart';
import 'src/buro_api.dart';
import 'src/davet_api.dart';
import 'src/dosya_api.dart';
import 'src/hata.dart';
import 'src/is_api.dart';
import 'src/kimlik_api.dart';
import 'src/kurumsal_api.dart';
import 'src/nesne_deposu.dart';
import 'src/odeme_saglayici.dart';
import 'src/portal_api.dart';
import 'src/sifreleme.dart';
import 'src/virus_tarama.dart';
import 'src/uyum_api.dart';
import 'src/veritabani.dart';

export 'src/abonelik_api.dart';
export 'src/belge_api.dart';
export 'src/buro_api.dart';
export 'src/davet_api.dart';
export 'src/dosya_api.dart';
export 'src/eposta.dart';
export 'src/hata.dart';
export 'src/is_api.dart';
export 'src/kimlik_api.dart';
export 'src/kurumsal_api.dart';
export 'src/nesne_deposu.dart';
export 'src/odeme_saglayici.dart';
export 'src/portal_api.dart';
export 'src/sifre.dart';
export 'src/sifreleme.dart';
export 'src/virus_tarama.dart';
export 'src/uyum_api.dart';
export 'src/veritabani.dart';

/// Yalnızca izin verilen web kökenlerine CORS izni (ör. https://app.hukukportali.com.tr).
Middleware cors(Set<String> izinliKokenler) => (ic) => (istek) async {
      final koken = istek.headers['origin'];
      final izinli = koken != null && izinliKokenler.contains(koken);
      final basliklar = izinli
          ? {
              'access-control-allow-origin': koken,
              'access-control-allow-headers': 'authorization, content-type, x-dosya-adi, x-belge-adi, x-belge-turu',
              'access-control-expose-headers': 'content-disposition, x-sha256',
              'access-control-allow-methods': 'GET, POST, PUT, DELETE',
              'vary': 'origin',
            }
          : <String, String>{};
      if (istek.method == 'OPTIONS') return Response(izinli ? 204 : 403, headers: basliklar);
      final yanit = await ic(istek);
      return yanit.change(headers: basliklar);
    };

/// [depo]: belge içeriklerinin saklandığı nesne deposu (Türkiye'de).
Handler uygulama(
  Veritabani vt, {
  required NesneDeposu depo,
  required AlanSifreleyici sifreleyici,
  OdemeSaglayici? odemeSaglayici,
  Uri? davetAdresi,
  VirusTarayici? virusTarayici,
  Set<String> izinliKokenler = const {},
  int belgeAzamiBoyut = 50 * 1024 * 1024,
  void Function(Object, StackTrace)? kaydet,
}) {
  final cascade = Cascade()
      .add((Request r) => r.url.path == 'saglik' ? jsonYanit({'durum': 'ok'}) : Response.notFound(null))
      .add(KimlikApi(vt, sifreleyici).router.call)
      .add(DosyaApi(vt).router.call)
      .add(IsApi(vt).router.call)
      .add(KurumsalApi(vt).router.call)
      .add(UyumApi(vt).router.call)
      .add(BuroApi(vt).router.call)
      .add(BelgeApi(vt, depo, azamiBoyut: belgeAzamiBoyut, tarayici: virusTarayici).router.call)
      .add(DavetApi(vt, davetAdresi: davetAdresi).router.call)
      .add(PortalApi(vt, depo).router.call)
      .add(AbonelikApi(vt, odemeSaglayici).router.call);
  return const Pipeline()
      .addMiddleware(cors(izinliKokenler))
      .addMiddleware(hataVeGuvenlik(kaydet: kaydet))
      .addMiddleware(oturumDogrula(vt))
      .addHandler(cascade.handler);
}
