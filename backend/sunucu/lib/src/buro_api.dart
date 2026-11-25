import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Büro işleri: dosya tarafları, görevler, duruşmalar (çakışma kontrolüyle), tebligatlar ve vekâletnameler.
class BuroApi {
  BuroApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..get('/taraflar', _taraflar)
    ..post('/dosyalar/<id>/taraflar', _tarafEkle)
    ..get('/gorevler', _gorevler)
    ..post('/gorevler', _gorevEkle)
    ..post('/gorevler/<id>/kapat', _gorevKapat)
    ..post('/gorevler/<id>/iptal', _gorevIptal)
    ..get('/durusmalar', _durusmalar)
    ..post('/durusmalar', _durusmaEkle)
    ..delete('/durusmalar/<id>', _durusmaSil)
    ..get('/tebligatlar', _tebligatlar)
    ..post('/tebligatlar', _tebligatEkle)
    ..post('/tebligatlar/<id>/bagla', _tebligatBagla)
    ..get('/vekaletnameler', _vekaletnameler)
    ..post('/vekaletnameler', _vekaletnameEkle)
    ..post('/vekaletnameler/<id>/durum', _vekaletDurum)
    ..get('/etik-duvarlar', _etikDuvarlar)
    ..post('/dosyalar/<id>/etik-duvar', _etikDuvarKur)
    ..post('/dosyalar/<id>/etik-duvar/kaldir', _etikDuvarKaldir);

  // ---------------------------------------------------------------------------
  // Taraflar
  // ---------------------------------------------------------------------------

  /// Görünür dosyaların tarafları (çıkar çatışması taraması ve tebligat eşleştirmesi için).
  Future<Response> _taraflar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT t.dosya_id::text, t.kisi_id::text, t.sifat, d.ic_no || \' · \' || d.baslik, d.gizli, '
            'd.kapanis IS NOT NULL FROM hukuk.dosya_taraf t JOIN hukuk.dosya d ON d.id = t.dosya_id'));
    return jsonYanit([
      for (final r in rs)
        {'dosyaId': r[0], 'kisiId': r[1], 'sifat': r[2], 'dosyaAdi': r[3], 'gizli': r[4], 'kapali': r[5]},
    ]);
  }

  Future<Response> _tarafEkle(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final sifat = enumAlani(j, 'sifat', TarafSifati.values);
    final kisi = zorunluMetin(j, 'kisiId');
    await vt.kiraciIcin(k, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO hukuk.dosya_taraf (kiraci_id, dosya_id, kisi_id, sifat) '
            'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), CAST(@p AS uuid), @s)'),
        parameters: {'k': k.kiraciId, 'd': dosyaId, 'p': kisi, 's': sifat.name},
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'dosya', dosyaId, 'Taraf eklendi (${sifat.name})');
    });
    return jsonYanit({'durum': 'eklendi'}, durum: 201);
  }

  // ---------------------------------------------------------------------------
  // Görevler
  // ---------------------------------------------------------------------------

  static const _gorevSutunlari = 'id::text, baslik, atanan::text, dosya_id::text, yedek::text, son_tarih, oncelik, durum, '
      'kaynak_sure_id::text, kanit_gerekir, kapanis_kaniti';

  static Gorev _gorev(List<Object?> r) => Gorev(
        id: r[0]! as String,
        baslik: r[1]! as String,
        atanan: r[2]! as String,
        dosyaId: r[3] as String?,
        yedek: r[4] as String?,
        sonTarih: r[5] == null ? null : tarihDegeri(r[5]),
        oncelik: GorevOnceligi.values.byName(r[6]! as String),
        durum: GorevDurumu.values.byName(r[7]! as String),
        kaynakSureId: r[8] as String?,
        kanitGerekir: r[9]! as bool,
        kapanisKaniti: r[10] as String?,
      );

  static Map<String, Object?> _gorevJson(Gorev g, Tarih bugun) => {
        'id': g.id,
        'baslik': g.baslik,
        'atanan': g.atanan,
        'dosyaId': g.dosyaId,
        'yedek': g.yedek,
        'sonTarih': g.sonTarih?.isoBicim,
        'oncelik': g.oncelik.name,
        'durum': g.durum.name,
        'kaynakSureId': g.kaynakSureId,
        'kanitGerekir': g.kanitGerekir,
        'kapanisKaniti': g.kapanisKaniti,
        'gecikti': g.gecikti(bugun),
      };

  Future<Response> _gorevler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k, (tx) => tx.execute('SELECT $_gorevSutunlari FROM hukuk.gorev ORDER BY son_tarih NULLS LAST, baslik LIMIT 5000'));
    final bugun = Tarih.from(DateTime.now());
    return jsonYanit([for (final r in rs) _gorevJson(_gorev(r), bugun)]);
  }

  Future<Response> _gorevEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final oncelik = j['oncelik'] == null ? GorevOnceligi.normal : enumAlani(j, 'oncelik', GorevOnceligi.values);
    final sonTarih = j['sonTarih'] == null ? null : tarihAlani(j, 'sonTarih');
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.gorev (kiraci_id, dosya_id, baslik, atanan, yedek, son_tarih, oncelik, kaynak_sure_id, '
            'kanit_gerekir) VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @b, CAST(@a AS uuid), CAST(@y AS uuid), '
            'CAST(@st AS date), @o, CAST(@ks AS uuid), @kg) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'd': j['dosyaId'] as String?,
          'b': zorunluMetin(j, 'baslik'),
          'a': (j['atanan'] as String?) ?? k.kullaniciId,
          'y': j['yedek'] as String?,
          'st': sonTarih?.isoBicim,
          'o': oncelik.name,
          'ks': j['kaynakSureId'] as String?,
          'kg': j['kanitGerekir'] == true || j['kaynakSureId'] != null,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'gorev', yeni, j['baslik'] as String);
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Gorev> _gorevOku(TxSession tx, String id) async {
    final rs = await tx.execute(Sql.named('SELECT $_gorevSutunlari FROM hukuk.gorev WHERE id = CAST(@id AS uuid) FOR UPDATE'),
        parameters: {'id': id});
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    return _gorev(rs.first);
  }

  Future<Response> _gorevKapat(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kanit = j['kanit'] as String?;
    await vt.kiraciIcin(k, (tx) async {
      final g = await _gorevOku(tx, id);
      final Gorev kapali;
      try {
        kapali = g.kapat(kanit: kanit);
      } on StateError catch (e) {
        throw ApiHatasi(409, e.message, kod: 'kural');
      } on ArgumentError catch (e) {
        throw ApiHatasi(400, '${e.message}', kod: 'gecersiz_istek');
      }
      await tx.execute(
        Sql.named("UPDATE hukuk.gorev SET durum = 'tamamlandi', kapanis = now(), kapanis_kaniti = @kn "
            'WHERE id = CAST(@id AS uuid)'),
        parameters: {'kn': kapali.kapanisKaniti, 'id': id},
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'gorev', id, 'Tamamlandı${kapali.kapanisKaniti == null ? '' : ': ${kapali.kapanisKaniti}'}');
    });
    return jsonYanit({'durum': 'tamamlandi'});
  }

  Future<Response> _gorevIptal(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final gerekce = zorunluMetin(j, 'gerekce');
    await vt.kiraciIcin(k, (tx) async {
      final g = await _gorevOku(tx, id);
      if (g.durum != GorevDurumu.acik) throw const ApiHatasi(409, 'Görev zaten kapalı.', kod: 'kural');
      // Kritik süreden doğan görev iptal edilemez; süre ayrıca tamamlanmalı veya yeniden hesaplanmalıdır.
      if (g.kaynakSureId != null) {
        throw const ApiHatasi(409, 'Kritik süreden doğan görev iptal edilemez.', kod: 'kural');
      }
      await tx.execute(Sql.named("UPDATE hukuk.gorev SET durum = 'iptal', kapanis = now() WHERE id = CAST(@id AS uuid)"),
          parameters: {'id': id});
      await DosyaApi.denetim(tx, k, 'degisiklik', 'gorev', id, 'İptal: $gerekce');
    });
    return jsonYanit({'durum': 'iptal'});
  }

  // ---------------------------------------------------------------------------
  // Duruşmalar
  // ---------------------------------------------------------------------------

  static const _durusmaSutunlari = 'id::text, dosya_id::text, baslangic, yer, katilan::text, sure_dakika, tur';

  static Durusma _durusma(List<Object?> r) => Durusma(
        id: r[0]! as String,
        dosyaId: r[1]! as String,
        baslangic: r[2]! as DateTime,
        yer: r[3]! as String,
        katilan: r[4]! as String,
        sureDakika: r[5]! as int,
        tur: r[6]! as String,
      );

  static Map<String, Object?> _durusmaJson(Durusma d) => {
        'id': d.id,
        'dosyaId': d.dosyaId,
        'baslangic': d.baslangic.toUtc().toIso8601String(),
        'yer': d.yer,
        'katilan': d.katilan,
        'sureDakika': d.sureDakika,
        'tur': d.tur,
      };

  Future<Response> _durusmalar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute("SELECT $_durusmaSutunlari FROM hukuk.durusma WHERE baslangic > now() - interval '180 days' "
            'ORDER BY baslangic'));
    return jsonYanit([for (final r in rs) _durusmaJson(_durusma(r))]);
  }

  /// Yeni duruşma; aynı avukatın üst üste binen veya yetişilemeyecek etkinlikleri uyarı olarak döner (kayıt engellenmez).
  Future<Response> _durusmaEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final bas = DateTime.tryParse(zorunluMetin(j, 'baslangic'));
    if (bas == null) throw const ApiHatasi(400, '"baslangic" ISO 8601 zaman olmalı.', kod: 'gecersiz_istek');
    final sure = j['sureDakika'] is int ? j['sureDakika'] as int : 60;
    final katilan = (j['katilan'] as String?) ?? k.kullaniciId;
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.durusma (kiraci_id, dosya_id, baslangic, sure_dakika, yer, katilan, tur) '
            'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @b, @s, @y, CAST(@a AS uuid), @t) RETURNING $_durusmaSutunlari'),
        parameters: {
          'k': k.kiraciId,
          'd': zorunluMetin(j, 'dosyaId'),
          'b': bas.toUtc(),
          's': sure,
          'y': zorunluMetin(j, 'yer'),
          'a': katilan,
          't': (j['tur'] as String?)?.trim().isNotEmpty == true ? (j['tur'] as String).trim() : 'Duruşma',
        },
      );
      final yeni = _durusma(rs.first);
      // Çakışma kontrolü kaydedenin görebildiği duruşmalara bakar; yanıtta yalnızca saat ve yer döner.
      final ayniGun = await tx.execute(
        Sql.named("SELECT id::text, dosya_id::text, baslangic, yer, katilan::text, sure_dakika, tur FROM hukuk.durusma "
            "WHERE katilan = CAST(@a AS uuid) AND baslangic BETWEEN CAST(@b AS timestamptz) - interval '1 day' "
            "AND CAST(@b AS timestamptz) + interval '1 day'"),
        parameters: {'a': katilan, 'b': bas.toUtc()},
      );
      final cakismalar = CakismaKontrolu.bul([for (final r in ayniGun) _durusma(r)])
          .where((c) => c.a.id == yeni.id || c.b.id == yeni.id)
          .toList();
      await DosyaApi.denetim(tx, k, 'olusturma', 'durusma', yeni.id, '${yeni.tur} · ${yeni.yer}');
      return {
        'durusma': _durusmaJson(yeni),
        'cakismalar': [
          for (final c in cakismalar)
            {
              'neden': c.neden,
              'diger': {
                'baslangic': (c.a.id == yeni.id ? c.b : c.a).baslangic.toUtc().toIso8601String(),
                'yer': (c.a.id == yeni.id ? c.b : c.a).yer,
              },
            },
        ],
      };
    });
    return jsonYanit(sonuc, durum: 201);
  }

  Future<Response> _durusmaSil(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
          Sql.named('DELETE FROM hukuk.durusma WHERE id = CAST(@id AS uuid) RETURNING dosya_id::text, yer, baslangic'),
          parameters: {'id': id});
      if (rs.isNotEmpty) {
        await DosyaApi.denetim(tx, k, 'silme', 'durusma', id, '${rs.first[1]} · ${(rs.first[2]! as DateTime).toIso8601String()}');
      }
      return rs.length;
    });
    if (n == 0) throw ApiHatasi.bulunamadi;
    return jsonYanit({'silindi': true});
  }

  // ---------------------------------------------------------------------------
  // Tebligatlar
  // ---------------------------------------------------------------------------

  static const _tebligatSutunlari = 'id::text, kanal, ulasma_tarihi, teblig_tarihi, gonderen, konu, esas_no, taraflar, '
      'belge_ozeti, dosya_id::text';

  static Map<String, Object?> _tebligatJson(List<Object?> r) => {
        'id': r[0],
        'kanal': r[1],
        'ulasmaTarihi': tarihMetni(r[2]),
        'tebligTarihi': tarihMetni(r[3]),
        'gonderen': r[4],
        'konu': r[5],
        'esasNo': r[6],
        'taraflar': r[7],
        'belgeOzeti': (r[8] as String?)?.trim(),
        'dosyaId': r[9],
      };

  Future<Response> _tebligatlar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k,
        (tx) => tx.execute('SELECT $_tebligatSutunlari FROM hukuk.tebligat ORDER BY teblig_tarihi DESC, zaman DESC LIMIT 2000'));
    return jsonYanit([for (final r in rs) _tebligatJson(r)]);
  }

  /// Tebliğ tarihi sunucuda hesaplanır (elektronik tebligatta ulaşmayı izleyen 5. gün); aynı evrak ikinci kez kaydedilmez.
  Future<Response> _tebligatEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kanal = enumAlani(j, 'kanal', TebligatKanali.values);
    final ulasma = tarihAlani(j, 'ulasmaTarihi');
    if (ulasma.isAfter(Tarih.from(DateTime.now()))) {
      throw const ApiHatasi(400, 'Ulaşma tarihi ileri bir tarih olamaz.', kod: 'gecersiz_istek');
    }
    final ozet = (j['belgeOzeti'] as String?)?.toLowerCase();
    if (ozet != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(ozet)) {
      throw const ApiHatasi(400, '"belgeOzeti" SHA-256 (64 onaltılık karakter) olmalı.', kod: 'gecersiz_istek');
    }
    final t = Tebligat(
      id: '',
      kiraciId: k.kiraciId,
      kanal: kanal,
      ulasmaTarihi: ulasma,
      tebligTarihi: j['tebligTarihi'] == null ? null : tarihAlani(j, 'tebligTarihi'),
      gonderen: zorunluMetin(j, 'gonderen'),
      konu: zorunluMetin(j, 'konu'),
      esasNo: (j['esasNo'] as String?)?.trim(),
      taraflar: [for (final x in (j['taraflar'] as List? ?? const [])) '$x'],
      belgeOzeti: ozet,
      dosyaId: j['dosyaId'] as String?,
    );
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.tebligat (kiraci_id, kanal, ulasma_tarihi, teblig_tarihi, gonderen, konu, esas_no, taraflar, '
            'belge_ozeti, tekillik, dosya_id) VALUES (CAST(@k AS uuid), @kn, CAST(@u AS date), CAST(@tt AS date), @g, @ko, @e, '
            'CAST(@tr AS text[]), @bo, @tk, CAST(@d AS uuid)) RETURNING $_tebligatSutunlari'),
        parameters: {
          'k': k.kiraciId,
          'kn': kanal.name,
          'u': t.ulasmaTarihi.isoBicim,
          'tt': t.tebligTarihi.isoBicim,
          'g': t.gonderen,
          'ko': t.konu,
          'e': t.esasNo,
          'tr': t.taraflar,
          'bo': t.belgeOzeti,
          'tk': t.tekillikAnahtari,
          'd': t.dosyaId,
        },
      );
      await DosyaApi.denetim(tx, k, 'olusturma', 'tebligat', rs.first[0]! as String, '${kanal.ad} · ${t.gonderen}');
      return _tebligatJson(rs.first);
    });
    return jsonYanit(sonuc, durum: 201);
  }

  Future<Response> _tebligatBagla(Request istek, String id) async {
    final k = kimlik(istek);
    final dosyaId = zorunluMetin(await jsonGovde(istek), 'dosyaId');
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.tebligat SET dosya_id = CAST(@d AS uuid) WHERE id = CAST(@id AS uuid) AND dosya_id IS NULL'),
        parameters: {'d': dosyaId, 'id': id},
      );
      if (rs.affectedRows == 1) await DosyaApi.denetim(tx, k, 'degisiklik', 'tebligat', id, 'Dosyaya bağlandı');
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Eşleşmemiş tebligat bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'dosyaId': dosyaId});
  }

  // ---------------------------------------------------------------------------
  // Vekâletnameler
  // ---------------------------------------------------------------------------

  static const _vekaletSutunlari = 'id::text, muvekkil_id::text, CAST(avukatlar AS text[]), duzenleme, noter, yevmiye_no, genel, '
      'ozel_yetkiler, CAST(dosyalar AS text[]), bitis, durum, durum_tarihi, asil_evrak_yeri';

  static Map<String, Object?> _vekaletJson(List<Object?> r) => {
        'id': r[0],
        'muvekkilId': r[1],
        'avukatlar': r[2],
        'duzenlemeTarihi': tarihMetni(r[3]),
        'noter': r[4],
        'yevmiyeNo': r[5],
        'genel': r[6],
        'ozelYetkiler': r[7],
        'dosyalar': r[8],
        'bitisTarihi': r[9] == null ? null : tarihMetni(r[9]),
        'durum': r[10],
        'durumTarihi': r[11] == null ? null : tarihMetni(r[11]),
        'asilEvrakYeri': r[12],
      };

  Future<Response> _vekaletnameler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT $_vekaletSutunlari FROM hukuk.vekaletname ORDER BY duzenleme DESC'));
    return jsonYanit([for (final r in rs) _vekaletJson(r)]);
  }

  Future<Response> _vekaletnameEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final avukatlar = [for (final x in (j['avukatlar'] as List? ?? const [])) '$x'];
    if (avukatlar.isEmpty) throw const ApiHatasi(400, 'En az bir vekil avukat seçin.', kod: 'eksik_alan');
    final yetkiler = <String>[];
    for (final x in (j['ozelYetkiler'] as List? ?? const [])) {
      if (!OzelYetki.values.any((y) => y.name == x)) {
        throw ApiHatasi(400, 'Bilinmeyen özel yetki: $x', kod: 'gecersiz_istek');
      }
      yetkiler.add('$x');
    }
    final genel = j['genel'] != false;
    final dosyalar = [for (final x in (j['dosyalar'] as List? ?? const [])) '$x'];
    final duzenleme = tarihAlani(j, 'duzenlemeTarihi');
    final bitis = j['bitisTarihi'] == null ? null : tarihAlani(j, 'bitisTarihi');
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.vekaletname (kiraci_id, muvekkil_id, avukatlar, duzenleme, noter, yevmiye_no, genel, '
            'ozel_yetkiler, dosyalar, bitis, asil_evrak_yeri) VALUES (CAST(@k AS uuid), CAST(@m AS uuid), '
            "CAST(@a AS uuid[]), CAST(@du AS date), @n, @y, @g, CAST(@oy AS text[]), CAST(@ds AS uuid[]), CAST(@b AS date), @ae) "
            'RETURNING $_vekaletSutunlari'),
        parameters: {
          'k': k.kiraciId,
          'm': zorunluMetin(j, 'muvekkilId'),
          'a': '{${avukatlar.join(',')}}',
          'du': duzenleme.isoBicim,
          'n': j['noter'] as String?,
          'y': j['yevmiyeNo'] as String?,
          'g': genel,
          'oy': yetkiler,
          'ds': '{${dosyalar.join(',')}}',
          'b': bitis?.isoBicim,
          'ae': j['asilEvrakYeri'] as String?,
        },
      );
      await DosyaApi.denetim(tx, k, 'olusturma', 'vekaletname', rs.first[0]! as String,
          '${genel ? 'Genel' : 'Özel'} vekâletname · ${yetkiler.length} özel yetki');
      return _vekaletJson(rs.first);
    });
    return jsonYanit(sonuc, durum: 201);
  }

  /// Azil, istifa veya sürenin dolması. Sona eren vekâletname veritabanında kilitlenir.
  Future<Response> _vekaletDurum(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final durum = enumAlani(j, 'durum', VekaletDurumu.values);
    if (durum == VekaletDurumu.gecerli) {
      throw const ApiHatasi(400, 'Vekâletname yeniden geçerli yapılamaz; yeni vekâletname kaydedin.', kod: 'gecersiz_istek');
    }
    final tarih = tarihAlani(j, 'tarih', varsayilan: Tarih.from(DateTime.now()));
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.vekaletname SET durum = @d, durum_tarihi = CAST(@t AS date) WHERE id = CAST(@id AS uuid)'),
        parameters: {'d': durum.name, 't': tarih.isoBicim, 'id': id},
      );
      if (rs.affectedRows == 1) await DosyaApi.denetim(tx, k, 'degisiklik', 'vekaletname', id, 'Durum: ${durum.name}');
      return rs.affectedRows;
    });
    if (n == 0) throw ApiHatasi.bulunamadi;
    return jsonYanit({'durum': durum.name});
  }

  // ---------------------------------------------------------------------------
  // Etik duvar (kurma ve kaldırma yalnızca tüm dosyalara yetkili yöneticilere açık; veritabanında zorlanır)
  // ---------------------------------------------------------------------------

  Future<Response> _etikDuvarlar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT dosya_id::text, kullanici_id::text, gerekce, kuran::text, kurma, kaldiran::text, '
            'kaldirma_gerekcesi, kaldirma FROM hukuk.etik_duvar ORDER BY kurma'));
    return jsonYanit([
      for (final r in rs)
        {
          'dosyaId': r[0],
          'kullanici': r[1],
          'gerekce': r[2],
          'kuran': r[3],
          'tarih': tarihMetni(r[4]),
          'kaldiran': r[5],
          'kaldirmaGerekcesi': r[6],
          'kaldirmaTarihi': r[7] == null ? null : tarihMetni(r[7]),
        },
    ]);
  }

  static String _gerekce(Map<String, dynamic> j) {
    final g = zorunluMetin(j, 'gerekce');
    if (g.length < EtikDuvarDefteri.asgariGerekce) {
      throw const ApiHatasi(400, 'Gerekçe en az ${EtikDuvarDefteri.asgariGerekce} karakter olmalı.', kod: 'gecersiz_istek');
    }
    return g;
  }

  Future<Response> _etikDuvarKur(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kisi = zorunluMetin(j, 'kullaniciId');
    final gerekce = _gerekce(j);
    if (kisi == k.kullaniciId) throw const ApiHatasi(400, 'Kendinize etik duvar kuramazsınız.', kod: 'gecersiz_istek');
    await vt.kiraciIcin(k, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO hukuk.etik_duvar (kiraci_id, dosya_id, kullanici_id, gerekce, kuran) '
            'VALUES (CAST(@k AS uuid), CAST(@d AS uuid), CAST(@u AS uuid), @g, CAST(@ku AS uuid))'),
        parameters: {'k': k.kiraciId, 'd': dosyaId, 'u': kisi, 'g': gerekce, 'ku': k.kullaniciId},
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'etik_duvar', dosyaId, 'Engellendi: $kisi · $gerekce');
    });
    return jsonYanit({'durum': 'kuruldu'}, durum: 201);
  }

  Future<Response> _etikDuvarKaldir(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kisi = zorunluMetin(j, 'kullaniciId');
    final gerekce = _gerekce(j);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.etik_duvar SET kaldiran = CAST(@ku AS uuid), kaldirma_gerekcesi = @g, kaldirma = now() '
            'WHERE dosya_id = CAST(@d AS uuid) AND kullanici_id = CAST(@u AS uuid) AND kaldirma IS NULL'),
        parameters: {'ku': k.kullaniciId, 'g': gerekce, 'd': dosyaId, 'u': kisi},
      );
      if (rs.affectedRows == 1) {
        await DosyaApi.denetim(tx, k, 'degisiklik', 'etik_duvar', dosyaId, 'Engel kaldırıldı: $kisi · $gerekce');
      }
      return rs.affectedRows;
    });
    // Yetkisiz kullanıcı için RLS satırı gizler; yanıt da "bulunamadı" olur.
    if (n == 0) throw const ApiHatasi(404, 'Etkin etik duvar bulunamadı veya kaldırma yetkiniz yok.', kod: 'bulunamadi');
    return jsonYanit({'durum': 'kaldirildi'});
  }
}
