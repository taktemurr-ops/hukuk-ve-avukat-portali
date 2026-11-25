import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'nesne_deposu.dart';
import 'veritabani.dart';

/// Müvekkil portalı.
///
/// `portal/...` uçları müvekkil oturumu içindir ve yalnızca SECURITY DEFINER portal fonksiyonlarını çağırır;
/// büro tarafı uçları (paylaşım, mesajlar) normal kiracı bağlamında çalışır.
class PortalApi {
  PortalApi(this.vt, this.depo);

  final Veritabani vt;
  final NesneDeposu depo;

  Router get router => Router()
    // Müvekkil tarafı
    ..get('/portal/dosyalar', _dosyalar)
    ..get('/portal/dosyalar/<id>/belgeler', _belgeler)
    ..get('/portal/belgeler/<id>/icerik', _belgeIcerigi)
    ..get('/portal/dosyalar/<id>/mesajlar', _mesajlar)
    ..post('/portal/dosyalar/<id>/mesajlar', _mesajGonder)
    ..post('/portal/dosyalar/<id>/okundu', _okundu)
    // Büro tarafı
    ..get('/portal-paylasimlari', _paylasimlar)
    ..post('/dosyalar/<id>/portal', _dosyaPaylas)
    ..post('/belgeler/<id>/portal', _belgePaylas)
    ..get('/dosyalar/<id>/mesajlar', _buroMesajlari)
    ..post('/dosyalar/<id>/mesajlar', _buroMesajGonder)
    ..post('/dosyalar/<id>/mesajlar/okundu', _buroOkundu);

  // ---------------------------------------------------------------------------
  // Müvekkil tarafı
  // ---------------------------------------------------------------------------

  Future<Response> _dosyalar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.portalIcin(
        k,
        (tx) => tx.execute('SELECT id::text, ic_no, baslik, asama, acilis, kapanis, sorumlu, sonraki_durusma, '
            'sonraki_durusma_yeri, okunmamis, tur FROM hukuk.portal_dosyalari()'));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'icNo': r[1],
          'baslik': r[2],
          'asama': r[3],
          'asamaAdi': DosyaAsamasi.values.where((a) => a.name == r[3]).map((a) => a.ad).firstOrNull ?? r[3],
          'acilis': (r[4]! as DateTime).toIso8601String().substring(0, 10),
          'kapali': r[5] != null,
          'sorumluAvukat': r[6],
          'sonrakiDurusma': (r[7] as DateTime?)?.toUtc().toIso8601String(),
          'sonrakiDurusmaYeri': r[8],
          'okunmamisMesaj': r[9],
          'tur': r[10],
        },
    ]);
  }

  Future<Response> _belgeler(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final rs = await vt.portalIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id::text, ad, tur, no, sha256, boyut, dosya_adi, zaman FROM hukuk.portal_belgeleri(CAST(@d AS uuid))'),
              parameters: {'d': dosyaId},
            ));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'ad': r[1],
          'tur': r[2],
          'surum': r[3],
          'sha256': (r[4]! as String).trim(),
          'boyut': r[5],
          'dosyaAdi': r[6],
          'zaman': (r[7]! as DateTime).toIso8601String(),
        },
    ]);
  }

  Future<Response> _belgeIcerigi(Request istek, String belgeId) async {
    final k = kimlik(istek);
    final rs = await vt.portalIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT depo_anahtari, sha256, dosya_adi FROM hukuk.portal_belge_icerigi(CAST(@b AS uuid))'),
              parameters: {'b': belgeId},
            ));
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    final (anahtar, ozet, ad) = (rs.first[0]! as String, (rs.first[1]! as String).trim(), rs.first[2]! as String);
    final icerik = await depo.oku(anahtar);
    if (sha256Ozeti(icerik) != ozet) {
      throw const ApiHatasi(500, 'Belge bütünlük denetiminden geçemedi; büronuza bildirildi.', kod: 'butunluk');
    }
    return Response.ok(icerik, headers: {
      'content-type': 'application/octet-stream',
      'content-disposition': "attachment; filename*=UTF-8''${Uri.encodeComponent(ad)}",
      'x-sha256': ozet,
      'cache-control': 'no-store',
    });
  }

  static List<Map<String, Object?>> _mesajJson(Result rs) => [
        for (final r in rs)
          {
            'id': r[0],
            'muvekkilden': r[1],
            'gonderen': r[2],
            'metin': r[3],
            'zaman': (r[4]! as DateTime).toIso8601String(),
            'okundu': (r[5] as DateTime?)?.toIso8601String(),
          },
      ];

  Future<Response> _mesajlar(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final rs = await vt.portalIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id, muvekkilden, gonderen, metin, zaman, okundu FROM hukuk.portal_mesajlari(CAST(@d AS uuid))'),
              parameters: {'d': dosyaId},
            ));
    return jsonYanit(_mesajJson(rs));
  }

  static String _metin(Map<String, dynamic> j) {
    final m = zorunluMetin(j, 'metin');
    if (m.length > 5000) throw const ApiHatasi(400, 'Mesaj en fazla 5000 karakter olabilir.', kod: 'gecersiz_istek');
    return m;
  }

  Future<Response> _mesajGonder(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final metin = _metin(await jsonGovde(istek));
    final rs = await vt.portalIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT hukuk.portal_mesaj_gonder(CAST(@d AS uuid), @m)'),
            parameters: {'d': dosyaId, 'm': metin}));
    return jsonYanit({'id': rs.first[0]}, durum: 201);
  }

  Future<Response> _okundu(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    await vt.portalIcin(
        k, (tx) => tx.execute(Sql.named('SELECT hukuk.portal_mesajlari_oku(CAST(@d AS uuid))'), parameters: {'d': dosyaId}));
    return jsonYanit({'durum': 'okundu'});
  }

  // ---------------------------------------------------------------------------
  // Büro tarafı
  // ---------------------------------------------------------------------------

  /// Portalda paylaşılan dosyalar ve müvekkille paylaşılan belgeler.
  Future<Response> _paylasimlar(Request istek) async {
    final k = kimlik(istek);
    final (dosyalar, belgeler) = await vt.kiraciIcin(k, (tx) async {
      final d = await tx.execute('SELECT dosya_id::text FROM hukuk.portal_paylasim');
      final b = await tx.execute('SELECT id::text FROM hukuk.belge WHERE portalda');
      return (d, b);
    });
    return jsonYanit({
      'dosyalar': [for (final r in dosyalar) r[0]],
      'belgeler': [for (final r in belgeler) r[0]],
    });
  }

  Future<Response> _dosyaPaylas(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final paylas = (await jsonGovde(istek))['paylas'] == true;
    await vt.kiraciIcin(k, (tx) async {
      final mevcut = await tx.execute(Sql.named('SELECT 1 FROM hukuk.dosya WHERE id = CAST(@d AS uuid)'),
          parameters: {'d': dosyaId});
      if (mevcut.isEmpty) throw ApiHatasi.bulunamadi;
      if (paylas) {
        await tx.execute(
          Sql.named('INSERT INTO hukuk.portal_paylasim (dosya_id, kiraci_id) VALUES (CAST(@d AS uuid), CAST(@k AS uuid)) '
              'ON CONFLICT (dosya_id) DO NOTHING'),
          parameters: {'d': dosyaId, 'k': k.kiraciId},
        );
      } else {
        await tx.execute(Sql.named('DELETE FROM hukuk.portal_paylasim WHERE dosya_id = CAST(@d AS uuid)'),
            parameters: {'d': dosyaId});
      }
      await DosyaApi.denetim(tx, k, 'degisiklik', 'dosya', dosyaId, paylas ? 'Müvekkil portalında paylaşıldı' : 'Portal paylaşımı kaldırıldı');
    });
    return jsonYanit({'paylasildi': paylas});
  }

  Future<Response> _belgePaylas(Request istek, String belgeId) async {
    final k = kimlik(istek);
    final paylas = (await jsonGovde(istek))['paylas'] == true;
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.belge SET portalda = @p WHERE id = CAST(@b AS uuid) AND NOT gizli'),
        parameters: {'p': paylas, 'b': belgeId},
      );
      if (rs.affectedRows == 1) {
        await DosyaApi.denetim(tx, k, 'degisiklik', 'belge', belgeId, paylas ? 'Müvekkille paylaşıldı' : 'Müvekkil paylaşımı kaldırıldı');
      }
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Belge bulunamadı veya gizli belge paylaşılamaz.', kod: 'bulunamadi');
    return jsonYanit({'paylasildi': paylas});
  }

  Future<Response> _buroMesajlari(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT m.id, m.muvekkilden, u.ad_soyad, m.metin, m.zaman, m.okundu FROM hukuk.portal_mesaj m '
                  'JOIN hukuk.kullanici u ON u.id = m.gonderen WHERE m.dosya_id = CAST(@d AS uuid) ORDER BY m.id'),
              parameters: {'d': dosyaId},
            ));
    return jsonYanit(_mesajJson(rs));
  }

  Future<Response> _buroMesajGonder(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final metin = _metin(await jsonGovde(istek));
    final id = await vt.kiraciIcin(k, (tx) async {
      final p = await tx.execute(Sql.named('SELECT 1 FROM hukuk.portal_paylasim WHERE dosya_id = CAST(@d AS uuid)'),
          parameters: {'d': dosyaId});
      if (p.isEmpty) throw const ApiHatasi(409, 'Dosya müvekkil portalında paylaşılmamış.', kod: 'kural');
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.portal_mesaj (kiraci_id, dosya_id, gonderen, muvekkilden, metin) '
            'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), CAST(@u AS uuid), false, @m) RETURNING id'),
        parameters: {'k': k.kiraciId, 'd': dosyaId, 'u': k.kullaniciId, 'm': metin},
      );
      return rs.first[0];
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _buroOkundu(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('UPDATE hukuk.portal_mesaj SET okundu = now() WHERE dosya_id = CAST(@d AS uuid) AND muvekkilden '
                  'AND okundu IS NULL'),
              parameters: {'d': dosyaId},
            ));
    return jsonYanit({'durum': 'okundu'});
  }
}
