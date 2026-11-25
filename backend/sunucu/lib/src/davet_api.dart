import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'sifre.dart';
import 'veritabani.dart';

/// Ekip ve müvekkil daveti. Kod yalnızca oluşturma yanıtında döner (davet bağlantısına konur, e-postayla gider);
/// sunucuda yalnızca SHA-256 özeti tutulur. Davet edilen kişi şifresini kendisi belirler.
class DavetApi {
  DavetApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..get('/koltuklar', _koltuklar)
    ..get('/davetler', _davetler)
    ..post('/davetler', _davetEt)
    ..post('/davetler/<id>/iptal', _iptal)
    ..post('/acik/davet-kabul', _kabul);

  Future<Response> _koltuklar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT lisans, dolu FROM hukuk.koltuk_durumu()'));
    return jsonYanit({'lisans': rs.first[0], 'dolu': rs.first[1]});
  }

  Future<Response> _davetler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, eposta, roller, davet_eden::text, olusturma, son_gecerlilik, kullanildi, iptal, '
            'kisi_id::text FROM hukuk.davet ORDER BY olusturma DESC LIMIT 500'));
    final simdi = DateTime.now();
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'eposta': r[1],
          'roller': r[2],
          'davetEden': r[3],
          'olusturma': (r[4]! as DateTime).toIso8601String(),
          'sonGecerlilik': (r[5]! as DateTime).toIso8601String(),
          'durum': r[7] != null
              ? 'iptal'
              : r[6] != null
                  ? 'kullanildi'
                  : (r[5]! as DateTime).isBefore(simdi)
                      ? 'suresiDoldu'
                      : 'bekliyor',
          'kisiId': r[8],
        },
    ]);
  }

  Future<Response> _davetEt(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final eposta = zorunluMetin(j, 'eposta').toLowerCase();
    final epostaHatasi = Dogrulayicilar.eposta(eposta);
    if (epostaHatasi != null) throw ApiHatasi(400, epostaHatasi, kod: 'gecersiz_istek');
    final roller = <Rol>{};
    for (final x in (j['roller'] as List? ?? const [])) {
      final r = Rol.values.where((y) => y.name == x).firstOrNull;
      if (r == null) throw ApiHatasi(400, 'Bilinmeyen rol: $x', kod: 'gecersiz_istek');
      roller.add(r);
    }
    final kisiId = j['kisiId'] as String?;
    if (roller.contains(Rol.muvekkil) && (roller.length > 1 || kisiId == null)) {
      throw const ApiHatasi(400, 'Müvekkil daveti tek rollüdür ve bir kişi kartına bağlanmalıdır.', kod: 'gecersiz_istek');
    }
    final kod = Davet.kodUret();
    final id = await vt.kiraciIcin(k, (tx) async {
      // Koltuk kontrolü kilit altında (aynı anda iki davetle sınırı aşmaya karşı).
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('koltuk' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      final koltuk = await tx.execute('SELECT lisans, dolu FROM hukuk.koltuk_durumu()');
      final (lisans, dolu) = (koltuk.first[0]! as int, koltuk.first[1]! as int);
      if (roller.isEmpty) throw const ApiHatasi(400, 'En az bir rol seçilmelidir.', kod: 'eksik_alan');
      if (!roller.every(ucretsizRoller.contains) && dolu >= lisans) {
        throw ApiHatasi(409,
            'Lisans koltukları dolu ($dolu/$lisans). Kullanıcı eklemek için paketinizi güncelleyin.', kod: 'koltuk_dolu');
      }
      if (kisiId != null) {
        // Kişi kartı bu kurumda olmalı (RLS ile görünürlük).
        final kisi = await tx.execute(Sql.named('SELECT 1 FROM hukuk.kisi WHERE id = CAST(@p AS uuid)'), parameters: {'p': kisiId});
        if (kisi.isEmpty) throw const ApiHatasi(400, 'Kişi kartı bulunamadı.', kod: 'gecersiz_istek');
      }
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.davet (kiraci_id, eposta, roller, kod_ozeti, davet_eden, kisi_id) '
            'VALUES (CAST(@k AS uuid), @e, CAST(@r AS text[]), @o, CAST(@u AS uuid), CAST(@p AS uuid)) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'e': eposta,
          'r': [for (final r in roller) r.name],
          'o': tokenOzeti(kod),
          'u': k.kullaniciId,
          'p': kisiId,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'davet', yeni, '$eposta · ${roller.map((r) => r.ad).join(', ')}');
      return yeni;
    });
    return jsonYanit({
      'id': id,
      'kod': kod,
      'gecerlilikSaat': 72,
      'bilgi': 'Kod yalnızca bir kez gösterilir; davet bağlantısıyla kişiye iletin.',
    }, durum: 201);
  }

  Future<Response> _iptal(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.davet SET iptal = now() WHERE id = CAST(@id AS uuid) AND iptal IS NULL AND kullanildi IS NULL'),
        parameters: {'id': id},
      );
      if (rs.affectedRows == 1) await DosyaApi.denetim(tx, k, 'degisiklik', 'davet', id, 'İptal edildi');
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Bekleyen davet bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'durum': 'iptal'});
  }

  /// Oturumsuz: davet bağlantısındaki kodla hesap açılır; şifre kuralları sunucuda da denetlenir.
  Future<Response> _kabul(Request istek) async {
    final j = await jsonGovde(istek);
    final kod = zorunluMetin(j, 'kod');
    final eposta = zorunluMetin(j, 'eposta').toLowerCase();
    final ad = zorunluMetin(j, 'adSoyad');
    final sifre = zorunluMetin(j, 'sifre');
    final sifreHatasi = Dogrulayicilar.sifre(sifre, eposta: eposta);
    if (sifreHatasi != null) throw ApiHatasi(400, sifreHatasi, kod: 'zayif_sifre');
    final rs = await vt.genel((tx) => tx.execute(
          Sql.named('SELECT kiraci_id::text, kullanici_id::text FROM hukuk.davet_kabul(@o, @e, @a, @s)'),
          parameters: {'o': tokenOzeti(kod.trim()), 'e': eposta, 'a': ad, 's': SifreOzeti.olustur(sifre)},
        ));
    return jsonYanit({'kiraciId': rs.first[0], 'kullaniciId': rs.first[1]}, durum: 201);
  }
}
