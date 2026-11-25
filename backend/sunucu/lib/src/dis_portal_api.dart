import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'kimlik_api.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Dış avukat portalı: anlaşmalı büro kendi işlerini, bütçe kullanımını ve faturalarını görür, fatura yükler.
/// Kurum verisine (dosya, talep, sözleşme) erişim yoktur; yalnızca işin konusu gösterilir.
class DisPortalApi {
  DisPortalApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..get('/dis-portal/isler', _isler)
    ..get('/dis-portal/isler/<id>/faturalar', _faturalar)
    ..post('/dis-portal/isler/<id>/faturalar', _faturaEkle);

  Future<Response> _isler(Request istek) async {
    final rs = await vt.disPortalIcin(
        kimlik(istek),
        (tx) => tx.execute('SELECT id::text, konu, baslangic, kapali, butce_kurus, onaylanan_kurus, bekleyen_kurus '
            'FROM hukuk.dis_portal_isleri()'));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'konu': r[1],
          'baslangic': tarihMetni(r[2]),
          'kapali': r[3],
          'butceKurus': r[4],
          'onaylananKurus': r[5],
          'bekleyenKurus': r[6],
        },
    ]);
  }

  Future<Response> _faturalar(Request istek, String id) async {
    final rs = await vt.disPortalIcin(
        kimlik(istek),
        (tx) => tx.execute(
            Sql.named('SELECT id::text, no, tarih, tutar_kurus, aciklama, durum, ret_gerekcesi '
                'FROM hukuk.dis_portal_faturalari(CAST(@i AS uuid))'),
            parameters: {'i': id}));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'no': r[1],
          'tarih': tarihMetni(r[2]),
          'tutarKurus': r[3],
          'aciklama': r[4],
          'durum': r[5],
          'retGerekcesi': r[6],
        },
    ]);
  }

  Future<Response> _faturaEkle(Request istek, String id) async {
    final j = await jsonGovde(istek);
    final tutar = j['tutarKurus'];
    if (tutar is! int || tutar <= 0) throw const ApiHatasi(400, 'Tutar pozitif olmalı.', kod: 'gecersiz_istek');
    final tarih = DateTime.tryParse(zorunluMetin(j, 'tarih'));
    if (tarih == null) throw const ApiHatasi(400, 'Tarih YYYY-AA-GG biçiminde olmalı.', kod: 'gecersiz_istek');
    final rs = await vt.disPortalIcin(
        kimlik(istek),
        (tx) => tx.execute(
            Sql.named('SELECT hukuk.dis_portal_fatura_ekle(CAST(@i AS uuid), @n, CAST(@t AS date), @tu, @a)::text'),
            parameters: {
              'i': id,
              'n': zorunluMetin(j, 'no'),
              't': zorunluMetin(j, 'tarih'),
              'tu': tutar,
              'a': (j['aciklama'] as String?) ?? '',
            }));
    return jsonYanit({'id': rs.first[0]}, durum: 201);
  }
}
