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
    ..post('/dosyalar/toplu', _topluAktar)
    ..get('/dosyalar/<id>', _ayrinti)
    ..get('/dosyalar/<id>/sureler', _sureler)
    ..post('/dosyalar/<id>/sureler', _sureHesapla)
    ..post('/sureler/<id>/teyit', _teyit)
    ..post('/sureler/<id>/tamamla', _tamamla)
    ..get('/denetim', _denetimListe)
    ..post('/denetim/kayit', _denetimKayit)
    ..get('/denetim/dogrula', _denetimDogrula);

  static Future<void> denetim(TxSession tx, KimlikBaglami k, String islem, String nesneTuru, String nesneId,
      [String aciklama = '']) =>
      tx.execute(
        Sql.named('INSERT INTO hukuk.denetim_kaydi (kiraci_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet) '
            "VALUES (CAST(@k AS uuid), @i, @t, @n, @a, '', '')"),
        parameters: {'k': k.kiraciId, 'i': islem, 't': nesneTuru, 'n': nesneId, 'a': aciklama},
      );

  /// "2026/123", "2026/123 E" ve "2026/123 E." aynı kayda çevrilir ("2026/123 E."); boşsa null.
  static String? esasNoBicimle(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d{4})\s*/\s*(\d{1,7})\s*(E|D|Tal|Talimat)?\.?$', caseSensitive: false).firstMatch(t);
    if (m == null) throw const ApiHatasi(400, 'Esas numarası "2026/123 E." biçiminde olmalıdır.', kod: 'gecersiz_istek');
    final ek = (m[3] ?? 'E').toUpperCase() == 'D' ? 'D.' : (m[3] ?? 'E').toUpperCase() == 'E' ? 'E.' : 'Tal.';
    return '${m[1]}/${m[2]} $ek';
  }

  /// Şablon adımlarından görevler: sorumlu/yedek dosyadan, stajyer kiracının ilk aktif stajyeri (yoksa sorumlu).
  static Future<int> gorevleriOlustur(TxSession tx, KimlikBaglami k, String dosyaId, GorevSablonu sablon,
      {required String sorumlu, String? yedek}) async {
    final st = await tx.execute("SELECT r.kullanici_id::text FROM hukuk.kullanici_rol r JOIN hukuk.kullanici u "
        "ON u.id = r.kullanici_id WHERE r.rol = 'stajyer' AND u.aktif ORDER BY u.ad_soyad LIMIT 1");
    var sira = 0;
    final gorevler = sablon.uygula(
      dosyaId: dosyaId,
      baslangic: Tarih.from(DateTime.now()),
      roller: {'sorumlu': sorumlu, if (yedek != null) 'yedek': yedek, if (st.isNotEmpty) 'stajyer': st.first[0]! as String},
      idUret: () => '${sira++}',
    );
    for (final g in gorevler) {
      await tx.execute(
        Sql.named('INSERT INTO hukuk.gorev (kiraci_id, dosya_id, baslik, atanan, yedek, son_tarih, oncelik) '
            'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @b, CAST(@a AS uuid), CAST(@y AS uuid), CAST(@t AS date), @o)'),
        parameters: {
          'k': k.kiraciId,
          'd': dosyaId,
          'b': g.baslik,
          'a': g.atanan,
          'y': g.yedek == g.atanan ? null : g.yedek,
          't': g.sonTarih?.isoBicim,
          'o': g.oncelik.name,
        },
      );
    }
    await denetim(tx, k, 'olusturma', 'gorev', dosyaId, '"${sablon.ad}" şablonundan ${gorevler.length} görev');
    return gorevler.length;
  }

  static String _tarih(Object? v) {
    if (v is DateTime) return Tarih.from(v).isoBicim;
    return v?.toString() ?? '';
  }

  Future<Response> _liste(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, ic_no, tur, baslik, sorumlu::text, yedek_sorumlu::text, gizli, asama, acilis, '
            'kapanis, mahkeme, esas_no FROM hukuk.dosya ORDER BY acilis DESC, ic_no DESC LIMIT 2000'));
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
          'kapanis': r[9] == null ? null : _tarih(r[9]),
          'mahkeme': r[10],
          'esasNo': r[11],
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
    final mahkeme = (j['mahkeme'] as String?)?.trim();
    final esasNo = DosyaApi.esasNoBicimle(j['esasNo'] as String?);
    // Görev şablonu içerikle gelir (hazır ya da büronun kayıtlı şablonu); kurallar çekirdekte.
    GorevSablonu? sablon;
    if (j['gorevSablonu'] is Map) {
      try {
        sablon = GorevSablonu.json((j['gorevSablonu'] as Map).cast<String, dynamic>());
      } on FormatException catch (e) {
        throw ApiHatasi(400, e.message, kod: 'gecersiz_istek');
      }
    }
    // Taraflar: [{"kisiId": "...", "sifat": "muvekkil" | "karsiTaraf" | "diger"}]
    final taraflar = <(String, String)>[
      for (final t in (j['taraflar'] as List? ?? const []))
        if (t is Map && t['kisiId'] is String && const {'muvekkil', 'karsiTaraf', 'diger'}.contains(t['sifat']))
          (t['kisiId'] as String, t['sifat'] as String)
        else
          throw const ApiHatasi(400, 'Taraf: kisiId ve sifat (muvekkil, karsiTaraf, diger) gerekli.', kod: 'gecersiz_istek'),
    ];
    final id = await vt.kiraciIcin(k, (tx) async {
      // Yıl bazında sıra numarası; aynı anda açılan dosyalar için kiracı kilidi. Sayım gizli dosyaları da kapsar
      // (SECURITY DEFINER fonksiyon), yoksa görmediği dosya numarasıyla çakışırdı.
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('dosya_no' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      final noRs = await tx.execute(Sql.named('SELECT hukuk.sonraki_dosya_no(@y)'), parameters: {'y': DateTime.now().year});
      final icNo = noRs.first[0]! as String;
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.dosya (kiraci_id, ic_no, tur, baslik, sorumlu, yedek_sorumlu, gizli, mahkeme, esas_no) '
            'VALUES (CAST(@k AS uuid), @n, @t, @b, CAST(@s AS uuid), CAST(@y AS uuid), @g, @m, @e) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'n': icNo,
          't': tur,
          'b': baslik,
          's': sorumlu,
          'y': yedek,
          'g': gizli,
          'm': mahkeme == null || mahkeme.isEmpty ? null : mahkeme,
          'e': esasNo,
        },
      );
      final yeniId = rs.first[0]! as String;
      if (sablon != null) await gorevleriOlustur(tx, k, yeniId, sablon, sorumlu: sorumlu, yedek: yedek);
      for (final t in taraflar) {
        await tx.execute(
          Sql.named('INSERT INTO hukuk.dosya_taraf (kiraci_id, dosya_id, kisi_id, sifat) '
              'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), CAST(@p AS uuid), @s)'),
          parameters: {'k': k.kiraciId, 'd': yeniId, 'p': t.$1, 's': t.$2},
        );
      }
      await denetim(tx, k, 'olusturma', 'dosya', yeniId, '$icNo · $baslik');
      return yeniId;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  /// UYAP/Excel dosya listesi aktarımı: önizlemeden geçen satırlar tek işlemde; aynı mahkeme + esas no zaten
  /// varsa (görünmeyen gizli dosyalar dahil, veritabanı tekilliği) satır atlanır. Geçersiz satırda hiçbiri eklenmez.
  Future<Response> _topluAktar(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final sorumlu = (j['sorumlu'] as String?) ?? k.kullaniciId;
    final yedek = j['yedekSorumlu'] as String?;
    final liste = (j['dosyalar'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (liste.isEmpty) throw const ApiHatasi(400, 'Aktarılacak dosya yok.', kod: 'eksik_alan');
    if (liste.length > 2000) throw const ApiHatasi(400, 'Tek seferde en fazla 2000 dosya aktarılabilir.', kod: 'gecersiz_istek');
    final satirlar = <Map<String, Object?>>[];
    for (var i = 0; i < liste.length; i++) {
      final d = liste[i];
      try {
        final tur = zorunluMetin(d, 'tur');
        if (!DosyaTuru.values.any((t) => t.name == tur)) throw const ApiHatasi(400, 'Geçersiz dosya türü.');
        final baslik = zorunluMetin(d, 'baslik');
        final mahkeme = zorunluMetin(d, 'mahkeme');
        if (baslik.length > 200 || mahkeme.length > 200) throw const ApiHatasi(400, 'Başlık ya da mahkeme çok uzun.');
        final esas = esasNoBicimle(zorunluMetin(d, 'esasNo'));
        final acilis = d['acilis'] == null ? null : Tarih.parse(d['acilis'] as String);
        satirlar.add({'t': tur, 'b': baslik, 'm': mahkeme, 'e': esas, 'a': acilis?.isoBicim});
      } on ApiHatasi catch (e) {
        throw ApiHatasi(400, '${d['satirNo'] ?? i + 1}. satır: ${e.mesaj}', kod: 'gecersiz_istek');
      } on FormatException {
        throw ApiHatasi(400, '${d['satirNo'] ?? i + 1}. satır: açılış tarihi geçersiz.', kod: 'gecersiz_istek');
      }
    }
    final (eklenen, atlanan) = await vt.kiraciIcin(k, (tx) async {
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('dosya_no' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      var n = 0;
      var atla = 0;
      for (final s in satirlar) {
        // Gizli dosyalar RLS ile görünmez; tekillik veritabanında da zorlanır, çakışmada satır atlanır.
        final mevcut = await tx.execute(
            Sql.named('SELECT hukuk.dosya_esas_var(CAST(@k AS uuid), @m, @e)'), parameters: {'k': k.kiraciId, 'm': s['m'], 'e': s['e']});
        if (mevcut.first[0] == true) {
          atla++;
          continue;
        }
        final yil = s['a'] == null ? DateTime.now().year : int.parse((s['a']! as String).substring(0, 4));
        final no = (await tx.execute(Sql.named('SELECT hukuk.sonraki_dosya_no(@y)'), parameters: {'y': yil})).first[0]! as String;
        await tx.execute(
          Sql.named('INSERT INTO hukuk.dosya (kiraci_id, ic_no, tur, baslik, sorumlu, yedek_sorumlu, mahkeme, esas_no, acilis) '
              'VALUES (CAST(@k AS uuid), @n, @t, @b, CAST(@s AS uuid), CAST(@y AS uuid), @m, @e, '
              'coalesce(CAST(@a AS date), current_date))'),
          parameters: {'k': k.kiraciId, 'n': no, 's': sorumlu, 'y': yedek, ...s},
        );
        n++;
      }
      await denetim(tx, k, 'aktarim', 'dosya', '-', 'Gönderilen ${satirlar.length}, eklenen $n, zaten kayıtlı $atla');
      return (n, atla);
    });
    return jsonYanit({'eklenen': eklenen, 'atlanan': atlanan}, durum: 201);
  }

  Future<Response> _ayrinti(Request istek, String id) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) async {
      final r = await tx.execute(
        Sql.named('SELECT id::text, ic_no, tur, baslik, sorumlu::text, yedek_sorumlu::text, gizli, asama, acilis, kapanis, '
            'mahkeme, esas_no FROM hukuk.dosya WHERE id = CAST(@id AS uuid)'),
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
      'mahkeme': r[10],
      'esasNo': r[11],
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

  /// Yalnızca yöneticiler (RLS); yöneticisi olmayan boş liste değil 403 alsın diye önce yetki sorulur.
  /// `once`: bu sıradan küçük kayıtlar (sayfalama), en yeniden eskiye en çok 200.
  Future<Response> _denetimListe(Request istek) async {
    final k = kimlik(istek);
    final once = int.tryParse(istek.url.queryParameters['once'] ?? '');
    final rs = await vt.kiraciIcin(k, (tx) async {
      final y = await tx.execute('SELECT hukuk.tum_yetkili()');
      if (y.first[0] != true) throw const ApiHatasi(403, 'Denetim kaydını yalnızca yöneticiler görebilir.', kod: 'yasak');
      return tx.execute(
        Sql.named('SELECT sira, zaman, coalesce(kullanici_id::text, \'\'), islem, nesne_turu, nesne_id, aciklama, ozet '
            'FROM hukuk.denetim_kaydi WHERE (CAST(@o AS bigint) IS NULL OR sira < CAST(@o AS bigint)) '
            'ORDER BY sira DESC LIMIT 200'),
        parameters: {'o': once},
      );
    });
    return jsonYanit([
      for (final r in rs)
        {
          'sira': r[0],
          'zaman': (r[1]! as DateTime).toUtc().toIso8601String(),
          'kullanici': r[2],
          'islem': r[3],
          'nesneTuru': r[4],
          'nesneId': r[5],
          'aciklama': r[6],
          'ozet': r[7],
        },
    ]);
  }

  /// İstemcide gerçekleşen okuma olayları (rapor dışa aktarma, ekranda görüntüleme). Değişiklik türü işlemler
  /// yalnızca sunucunun kendi uçlarınca yazılır; istemci onları uyduramaz.
  static const _istemciIslemleri = {'goruntuleme', 'indirme', 'disaAktarma', 'paylasim'};

  Future<Response> _denetimKayit(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final islem = '${j['islem']}';
    if (!_istemciIslemleri.contains(islem)) {
      throw const ApiHatasi(400, 'Bu işlem türü istemciden kaydedilemez.', kod: 'gecersiz_istek');
    }
    String alan(String ad, int azami) {
      final v = '${j[ad] ?? ''}'.trim();
      if (v.length > azami) throw ApiHatasi(400, '$ad çok uzun.', kod: 'gecersiz_istek');
      return v;
    }

    final tur = alan('nesneTuru', 50);
    final id = alan('nesneId', 200);
    if (tur.isEmpty || id.isEmpty) throw const ApiHatasi(400, 'Nesne belirtilmedi.', kod: 'eksik_alan');
    await vt.kiraciIcin(k, (tx) => denetim(tx, k, islem, tur, id, alan('aciklama', 500)));
    return jsonYanit({'kaydedildi': true}, durum: 201);
  }
}
