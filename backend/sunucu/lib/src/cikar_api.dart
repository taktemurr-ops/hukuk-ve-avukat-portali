import 'dart:convert';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Çıkar çatışması taraması ve iş kabul kararları. Tarama sunucuda, kurumun tüm dosyalarında yapılır
/// (kullanıcının göremediği dosyalar "Korumalı dosya" olarak döner); karar sunucunun kendi taramasına dayanır,
/// istemcinin gönderdiği sonuca güvenilmez.
class CikarApi {
  CikarApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..post('/cikar/tara', _tara)
    ..get('/cikar/kararlar', _kararlar)
    ..post('/cikar/kararlar', _kararEkle)
    ..post('/cikar/kararlar/<id>/onay', _onay);

  static List<AdayTaraf> _adaylar(Map<String, dynamic> j) {
    final ham = j['adaylar'];
    if (ham is! List || ham.isEmpty || ham.length > 50) {
      throw const ApiHatasi(400, '1–50 taraf girilmelidir.', kod: 'gecersiz_istek');
    }
    return [
      for (final a in ham.cast<Map<String, dynamic>>())
        AdayTaraf(
          ad: zorunluMetin(a, 'ad'),
          sifat: enumAlani(a, 'sifat', TarafSifati.values),
          kimlikNo: (a['kimlikNo'] as String?)?.trim().isEmpty ?? true ? null : (a['kimlikNo'] as String).trim(),
        ),
    ];
  }

  Future<CikarCatismasiRaporu> _taramaYap(TxSession tx, List<AdayTaraf> adaylar) async {
    final kisiler = await tx.execute('SELECT id::text, tur, ad, kimlik_no, unvan_gecmisi FROM hukuk.kisi');
    final iliskiler = await tx.execute('SELECT kisi_a::text, kisi_b::text, tur FROM hukuk.kisi_iliski');
    final taraflar = await tx.execute(
        'SELECT dosya_id::text, dosya_adi, kisi_id::text, sifat, korumali, kapali FROM hukuk.cikar_tarama_taraflari()');
    final tarayici = CikarCatismasiTarayici(
      kisiler: [
        for (final r in kisiler)
          Kisi(
            id: r[0]! as String,
            kiraciId: '',
            tur: KisiTuru.values.byName(r[1]! as String),
            ad: r[2]! as String,
            kimlikNo: r[3] as String?,
            unvanGecmisi: [
              for (final u in (r[4] as List? ?? const []).cast<Map<String, dynamic>>())
                UnvanKaydi(unvan: u['unvan'] as String, gecerlilikBitisi: Tarih.parse(u['bitis'] as String)),
            ],
          ),
      ],
      iliskiler: [
        for (final r in iliskiler)
          KisiIliskisi(kisiA: r[0]! as String, kisiB: r[1]! as String, tur: IliskiTuru.values.byName(r[2]! as String)),
      ],
      dosyaKayitlari: [
        for (final r in taraflar)
          DosyaTarafKaydi(
            dosyaId: r[0]! as String,
            dosyaAdi: r[1]! as String,
            kisiId: r[2]! as String,
            sifat: TarafSifati.values.byName(r[3]! as String),
            gizli: r[4] == true,
            kapali: r[5] == true,
          ),
      ],
    );
    return tarayici.tara(adaylar);
  }

  static Map<String, Object?> _eslesmeJson(Eslesme e) => {
        'aday': {'ad': e.aday.ad, 'sifat': e.aday.sifat.name, 'kimlikNo': e.aday.kimlikNo},
        'kisiAdi': e.kisiAdi,
        'tur': e.tur.name,
        'benzerlik': e.benzerlik,
        'seviye': e.seviye.name,
        'iliski': e.iliski?.name,
        'dosya': e.dosya == null
            ? null
            : {'dosyaId': e.dosya!.dosyaId, 'dosyaAdi': e.dosya!.dosyaAdi, 'sifat': e.dosya!.sifat.name, 'kapali': e.dosya!.kapali},
      };

  Future<Response> _tara(Request istek) async {
    final k = kimlik(istek);
    final adaylar = _adaylar(await jsonGovde(istek));
    final rapor = await vt.kiraciIcin(k, (tx) async {
      final r = await _taramaYap(tx, adaylar);
      await DosyaApi.denetim(tx, k, 'goruntuleme', 'cikar_tarama', '-', '${adaylar.length} taraf · ${r.eslesmeler.length} eşleşme');
      return r;
    });
    return jsonYanit({'eslesmeler': [for (final e in rapor.eslesmeler) _eslesmeJson(e)], 'enYuksek': rapor.enYuksekSeviye?.name});
  }

  Future<Response> _kararEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final adaylar = _adaylar(j);
    final tur = enumAlani(j, 'tur', KararTuru.values);
    final gerekce = '${j['gerekce'] ?? ''}'.trim();
    final kosullar = (j['kosullar'] as String?)?.trim();
    if (gerekce.length < 10) throw const ApiHatasi(400, 'Gerekçe en az 10 karakter olmalıdır.', kod: 'gecersiz_istek');
    if (tur == KararTuru.kosulluKabul && (kosullar == null || kosullar.isEmpty)) {
      throw const ApiHatasi(400, 'Koşullu kabulde koşullar yazılmalıdır.', kod: 'gecersiz_istek');
    }
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rapor = await _taramaYap(tx, adaylar); // istemcinin taramasına güvenilmez
      final en = rapor.enYuksekSeviye;
      final onayBekler = en == RiskSeviyesi.catisma && tur != KararTuru.ret;
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.is_kabul_karari (kiraci_id, adaylar, eslesmeler, en_yuksek, tur, gerekce, kosullar, durum) '
            'VALUES (CAST(@k AS uuid), CAST(@a AS jsonb), CAST(@e AS jsonb), @s, @t, @g, @ko, @d) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'a': jsonEncode([for (final a in adaylar) {'ad': a.ad, 'sifat': a.sifat.name, 'kimlikNo': a.kimlikNo}]),
          'e': jsonEncode([for (final e in rapor.eslesmeler) _eslesmeJson(e)]),
          's': en?.name,
          't': tur.name,
          'g': gerekce,
          'ko': kosullar == null || kosullar.isEmpty ? null : kosullar,
          'd': onayBekler ? 'onayBekliyor' : 'gecerli',
        },
      );
      final id = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'kararKaydi', 'is_kabul', id,
          '${adaylar.map((a) => a.ad).join(', ')} · ${tur.name}${onayBekler ? ' · yönetici onayı bekliyor' : ''}');
      return {'id': id, 'durum': onayBekler ? 'onayBekliyor' : 'gecerli', 'enYuksek': en?.name};
    });
    return jsonYanit(sonuc, durum: 201);
  }

  Future<Response> _kararlar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, adaylar, en_yuksek, tur, gerekce, kosullar, karar_veren::text, zaman, durum, '
            'onaylayan::text, onay_zamani FROM hukuk.is_kabul_karari ORDER BY zaman DESC LIMIT 200'));
    String? zaman(Object? v) => v == null ? null : (v as DateTime).toUtc().toIso8601String();
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'adaylar': r[1],
          'enYuksek': r[2],
          'tur': r[3],
          'gerekce': r[4],
          'kosullar': r[5],
          'kararVeren': r[6],
          'zaman': zaman(r[7]),
          'durum': r[8],
          'onaylayan': r[9],
          'onayZamani': zaman(r[10]),
        },
    ]);
  }

  Future<Response> _onay(Request istek, String id) async {
    final k = kimlik(istek);
    await vt.kiraciIcin(
        k, (tx) => tx.execute(Sql.named('SELECT hukuk.is_kabul_onayla(CAST(@i AS uuid))'), parameters: {'i': id}));
    return jsonYanit({'durum': 'gecerli'});
  }
}
