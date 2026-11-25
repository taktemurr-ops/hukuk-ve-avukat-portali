import 'dart:convert';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'kimlik_api.dart';
import 'veritabani.dart';

/// Dosya ve süre uçları. Görünürlük veritabanındaki RLS ile sağlanır: görülemeyen dosya "bulunamadı" döner
/// (varlığı bile sızmasın diye 403 değil 404).
class DosyaApi {
  DosyaApi(this.vt, {SureHesaplayici? hesaplayici})
      : hesaplayici = hesaplayici ??
            SureHesaplayici(TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar));

  final Veritabani vt;

  /// Varsayılan ayarlarda taslak kurallar reddedilir; canlıda yalnızca avukat onaylı kurallar kullanılır.
  final SureHesaplayici hesaplayici;

  Router get router => Router()
    ..get('/dosyalar', _liste)
    ..post('/dosyalar', _olustur)
    ..get('/dosyalar/<id>', _ayrinti)
    ..get('/dosyalar/<id>/sureler', _sureler)
    ..post('/dosyalar/<id>/sureler', _sureHesapla)
    ..post('/sureler/<id>/teyit', _teyit)
    ..post('/sureler/<id>/tamamla', _tamamla)
    ..get('/denetim/dogrula', _denetimDogrula);

  static Future<void> denetim(TxSession tx, KimlikBaglami k, String islem, String nesneTuru, String nesneId,
      [String aciklama = '']) =>
      tx.execute(
        Sql.named('INSERT INTO hukuk.denetim_kaydi (kiraci_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet) '
            "VALUES (CAST(@k AS uuid), @i, @t, @n, @a, '', '')"),
        parameters: {'k': k.kiraciId, 'i': islem, 't': nesneTuru, 'n': nesneId, 'a': aciklama},
      );

  static String _tarih(Object? v) {
    if (v is DateTime) return Tarih.from(v).isoBicim;
    return v?.toString() ?? '';
  }

  Future<Response> _liste(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, ic_no, tur, baslik, sorumlu::text, yedek_sorumlu::text, gizli, asama, acilis '
            'FROM hukuk.dosya ORDER BY acilis DESC, ic_no DESC LIMIT 500'));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'icNo': r[1],
          'tur': r[2],
          'baslik': r[3],
          'sorumlu': r[4],
          'yedekSorumlu': r[5],
          'gizli': r[6],
          'asama': r[7],
          'acilis': _tarih(r[8]),
        },
    ]);
  }

  Future<Response> _olustur(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = zorunluMetin(j, 'tur');
    if (!DosyaTuru.values.any((t) => t.name == tur)) throw const ApiHatasi(400, 'Geçersiz dosya türü.');
    final baslik = zorunluMetin(j, 'baslik');
    final sorumlu = (j['sorumlu'] as String?) ?? k.kullaniciId;
    final yedek = j['yedekSorumlu'] as String?;
    final gizli = j['gizli'] == true;
    final id = await vt.kiraciIcin(k, (tx) async {
      // Yıl bazında sıra numarası; aynı anda açılan dosyalar için kiracı kilidi.
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('dosya_no' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      final yil = DateTime.now().year;
      final sira = await tx.execute(
        Sql.named("SELECT count(*) + 1 FROM hukuk.dosya WHERE ic_no LIKE @y || '/%'"),
        parameters: {'y': '$yil'},
      );
      final icNo = '$yil/${(sira.first[0]! as int).toString().padLeft(4, '0')}';
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.dosya (kiraci_id, ic_no, tur, baslik, sorumlu, yedek_sorumlu, gizli) '
            'VALUES (CAST(@k AS uuid), @n, @t, @b, CAST(@s AS uuid), CAST(@y AS uuid), @g) RETURNING id::text'),
        parameters: {'k': k.kiraciId, 'n': icNo, 't': tur, 'b': baslik, 's': sorumlu, 'y': yedek, 'g': gizli},
      );
      final yeniId = rs.first[0]! as String;
      await denetim(tx, k, 'olusturma', 'dosya', yeniId, '$icNo · $baslik');
      return yeniId;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _ayrinti(Request istek, String id) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) async {
      final r = await tx.execute(
        Sql.named('SELECT id::text, ic_no, tur, baslik, sorumlu::text, yedek_sorumlu::text, gizli, asama, acilis, kapanis '
            'FROM hukuk.dosya WHERE id = CAST(@id AS uuid)'),
        parameters: {'id': id},
      );
      if (r.isNotEmpty) await denetim(tx, k, 'goruntuleme', 'dosya', id);
      return r;
    });
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    final r = rs.first;
    return jsonYanit({
      'id': r[0],
      'icNo': r[1],
      'tur': r[2],
      'baslik': r[3],
      'sorumlu': r[4],
      'yedekSorumlu': r[5],
      'gizli': r[6],
      'asama': r[7],
      'acilis': _tarih(r[8]),
      'kapanis': r[9] == null ? null : _tarih(r[9]),
    });
  }

  Future<Response> _sureler(Request istek, String id) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id::text, aciklama, kural_kodu, son_gun, durum, olusturan::text, asil_sorumlu::text, '
                  'yedek_sorumlu::text, teyit_eden::text, baslangic, hesap_adimlari::text, kanit '
                  'FROM hukuk.sure_kaydi WHERE dosya_id = CAST(@d AS uuid) ORDER BY son_gun'),
              parameters: {'d': id},
            ));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'aciklama': r[1],
          'kuralKodu': r[2],
          'sonGun': _tarih(r[3]),
          'durum': r[4],
          'olusturan': r[5],
          'asilSorumlu': r[6],
          'yedekSorumlu': r[7],
          'teyitEden': r[8],
          'baslangic': r[9] == null ? null : _tarih(r[9]),
          'adimlar': jsonDecode(r[10]! as String),
          'kanit': r[11],
        },
    ]);
  }

  static Tarih _baslangicTarihi(Map<String, dynamic> j) {
    try {
      final ulasma = Tarih.parse(zorunluMetin(j, 'tarih'));
      return j['elektronikTebligat'] == true ? ElektronikTebligat.tebligTarihi(ulasma) : ulasma;
    } on FormatException {
      throw const ApiHatasi(400, 'Tarih YYYY-AA-GG biçiminde olmalı.');
    } on ArgumentError {
      throw const ApiHatasi(400, 'Geçersiz tarih.');
    }
  }

  SureSonucu _hesapla(SureKurali kural, Tarih baslangic) {
    try {
      return hesaplayici.hesapla(kural: kural, baslangic: baslangic);
    } on StateError catch (e) {
      throw ApiHatasi(409, e.message, kod: 'kural_onaysiz');
    }
  }

  /// Süre sunucuda hesaplanır (istemcinin hesabına güvenilmez) ve teyit bekler hâlde kaydedilir.
  Future<Response> _sureHesapla(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kural = KuralKatalogu.bul(zorunluMetin(j, 'kuralKodu'));
    if (kural == null) throw const ApiHatasi(400, 'Süre kuralı bulunamadı.');
    final baslangic = _baslangicTarihi(j);
    final sonuc = _hesapla(kural, baslangic);
    final id = await vt.kiraciIcin(k, (tx) async {
      final d = await tx.execute(
        Sql.named('SELECT sorumlu::text, yedek_sorumlu::text, baslik FROM hukuk.dosya WHERE id = CAST(@d AS uuid)'),
        parameters: {'d': dosyaId},
      );
      if (d.isEmpty) throw ApiHatasi.bulunamadi;
      final aciklama = (j['aciklama'] as String?)?.trim().isNotEmpty == true ? j['aciklama'] as String : kural.ad;
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.sure_kaydi (kiraci_id, dosya_id, aciklama, kural_kodu, son_gun, olusturan, '
            'asil_sorumlu, yedek_sorumlu, baslangic, hesap_adimlari) VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @a, @kod, '
            'CAST(@s AS date), CAST(@o AS uuid), CAST(@asil AS uuid), CAST(@y AS uuid), CAST(@b AS date), CAST(@adim AS jsonb)) '
            'RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'd': dosyaId,
          'a': aciklama,
          'kod': kural.kod,
          's': sonuc.sonGun.isoBicim,
          'o': k.kullaniciId,
          'asil': d.first[0],
          'y': d.first[1],
          'b': sonuc.baslangic.isoBicim,
          'adim': jsonEncode([
            for (final a in sonuc.adimlar) {'tarih': a.tarih.isoBicim, 'aciklama': a.aciklama},
          ]),
        },
      );
      final sureId = rs.first[0]! as String;
      await denetim(tx, k, 'olusturma', 'sure', sureId, '$aciklama · son gün ${sonuc.sonGun.turkceBicim}');
      return sureId;
    });
    return jsonYanit({
      'id': id,
      'sonGun': sonuc.sonGun.isoBicim,
      'baslangic': sonuc.baslangic.isoBicim,
      'adimlar': [
        for (final a in sonuc.adimlar) {'tarih': a.tarih.isoBicim, 'aciklama': a.aciklama},
      ],
      'uyarilar': sonuc.uyarilar,
      'durum': 'teyitBekliyor',
    }, durum: 201);
  }

  Future<Response> _teyit(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named("UPDATE hukuk.sure_kaydi SET durum = 'teyitli', teyit_eden = CAST(@u AS uuid), teyit_zamani = now() "
            "WHERE id = CAST(@id AS uuid) AND durum = 'teyitBekliyor'"),
        parameters: {'u': k.kullaniciId, 'id': id},
      );
      if (rs.affectedRows == 1) await denetim(tx, k, 'sureTeyit', 'sure', id);
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Teyit bekleyen süre bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'durum': 'teyitli'});
  }

  Future<Response> _tamamla(Request istek, String id) async {
    final k = kimlik(istek);
    final kanit = zorunluMetin(await jsonGovde(istek), 'kanit');
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named("UPDATE hukuk.sure_kaydi SET durum = 'tamamlandi', kanit = @kanit "
            "WHERE id = CAST(@id AS uuid) AND durum = 'teyitli'"),
        parameters: {'kanit': kanit, 'id': id},
      );
      if (rs.affectedRows == 1) await denetim(tx, k, 'degisiklik', 'sure', id, 'Tamamlandı: $kanit');
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Teyitli süre bulunamadı; önce teyit edilmeli.', kod: 'bulunamadi');
    return jsonYanit({'durum': 'tamamlandi'});
  }

  Future<Response> _denetimDogrula(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT hukuk.denetim_dogrula(CAST(@k AS uuid))'),
            parameters: {'k': k.kiraciId}));
    final bozuk = rs.first[0];
    return jsonYanit({'saglam': bozuk == null, 'bozukSira': bozuk});
  }
}
