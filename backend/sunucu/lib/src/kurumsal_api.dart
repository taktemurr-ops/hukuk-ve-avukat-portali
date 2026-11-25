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

/// Kurumsal hukuk birimi uçları: grup şirketleri, sözleşmeler ve onay zinciri, hukuk talepleri.
///
/// Durum geçişleri, SLA ve onay zinciri kuralları hukuk_cekirdek'ten gelir (uygulamadakiyle aynı);
/// veritabanı ayrıca onay turunu, kişi başına tek onayı ve kapanış/ret gerekçesini zorlar.
class KurumsalApi {
  KurumsalApi(this.vt);

  final Veritabani vt;

  static final _isGunu = IsGunuHesabi(TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar));

  /// Talepleri yürütebilen roller.
  static const hukukRolleri = {'hukukDirektoru', 'sirketAvukati', 'hukukUzmani'};

  Router get router => Router()
    ..get('/sirketler', _sirketler)
    ..post('/sirketler', _sirketEkle)
    ..get('/sozlesmeler', _sozlesmeler)
    ..post('/sozlesmeler', _sozlesmeEkle)
    ..post('/sozlesmeler/<id>/durum', _sozlesmeDurum)
    ..get('/sozlesmeler/<id>/onay', _onayDurumu)
    ..post('/sozlesmeler/<id>/onay', _onayKarari)
    ..post('/sozlesmeler/<id>/yukumlulukler', _yukumlulukEkle)
    ..post('/yukumlulukler/<id>/tamamla', _yukumlulukTamamla)
    ..get('/talepler', _talepler)
    ..post('/talepler', _talepEkle)
    ..post('/talepler/<id>/durum', _talepDurum)
    ..post('/talepler/<id>/ata', _talepAta);

  static Future<Set<String>> _roller(TxSession tx, String kullaniciId) async {
    final rs = await tx.execute(Sql.named('SELECT rol FROM hukuk.kullanici_rol WHERE kullanici_id = CAST(@u AS uuid)'),
        parameters: {'u': kullaniciId});
    return {for (final r in rs) r[0]! as String};
  }

  static Future<void> _hukukEkibiOlmali(TxSession tx, KimlikBaglami k) async {
    final roller = await _roller(tx, k.kullaniciId);
    if (roller.intersection(hukukRolleri).isEmpty) {
      throw const ApiHatasi(403, 'Bu işlem hukuk ekibine açıktır.', kod: 'yetkisiz_islem');
    }
  }

  /// Yıl bazında sıra numarası (SZ-2026-0001). Aynı kurumda eşzamanlı oluşturmada çakışmayı önlemek için kilit alınır.
  static Future<String> _yeniNo(TxSession tx, KimlikBaglami k, String tablo, String onek) async {
    final yil = DateTime.now().year;
    await tx.execute(Sql.named('SELECT pg_advisory_xact_lock(hashtextextended(@a, 0))'),
        parameters: {'a': '${k.kiraciId}/$onek'});
    final sorgu = tablo == 'sozlesme'
        ? "SELECT coalesce(max(CAST(substring(no from '[0-9]+\$') AS integer)), 0) + 1 FROM hukuk.sozlesme WHERE no LIKE @o"
        : "SELECT coalesce(max(CAST(substring(no from '[0-9]+\$') AS integer)), 0) + 1 FROM hukuk.hukuk_talebi WHERE no LIKE @o";
    final rs = await tx.execute(Sql.named(sorgu), parameters: {'o': '$onek-$yil-%'});
    return '$onek-$yil-${(rs.first[0]! as int).toString().padLeft(4, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Grup şirketleri
  // ---------------------------------------------------------------------------

  Future<Response> _sirketler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k, (tx) => tx.execute('SELECT id::text, unvan, kisa_ad, vkn, ana_sirket_id::text FROM hukuk.sirket ORDER BY unvan'));
    return jsonYanit([
      for (final r in rs) {'id': r[0], 'unvan': r[1], 'kisaAd': r[2], 'vkn': r[3], 'anaSirketId': r[4]},
    ]);
  }

  Future<Response> _sirketEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final vkn = (j['vkn'] as String?)?.trim();
    if (vkn != null && vkn.isNotEmpty && !Dogrulayicilar.vknGecerli(vkn)) {
      throw const ApiHatasi(400, 'Vergi kimlik numarası geçersiz.', kod: 'gecersiz_istek');
    }
    final id = await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.sirket (kiraci_id, unvan, kisa_ad, vkn, ana_sirket_id) '
            'VALUES (CAST(@k AS uuid), @u, @ka, @v, CAST(@a AS uuid)) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'u': zorunluMetin(j, 'unvan'),
          'ka': j['kisaAd'] as String?,
          'v': vkn == null || vkn.isEmpty ? null : vkn,
          'a': j['anaSirketId'] as String?,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'sirket', yeni, j['unvan'] as String);
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  // ---------------------------------------------------------------------------
  // Sözleşmeler
  // ---------------------------------------------------------------------------

  static const _sozlesmeSutunlari = 'id::text, no, sirket_id::text, baslik, tur, karsi_taraf, sorumlu::text, durum, baslangic, '
      'bitis, otomatik_yenileme, ihbar_gun, bedel_kurus, para_birimi, birim, yenileme_suresi_ay, onay_turu, tarama';

  static Sozlesme _sozlesme(List<Object?> r) => Sozlesme(
        id: r[0]! as String,
        no: r[1]! as String,
        sirketId: r[2] as String?,
        baslik: r[3]! as String,
        tur: SozlesmeTuru.values.firstWhere((t) => t.name == r[4], orElse: () => SozlesmeTuru.diger),
        karsiTaraf: r[5]! as String,
        sorumlu: r[6]! as String,
        durum: SozlesmeDurumu.values.byName(r[7]! as String),
        baslangic: r[8] == null ? null : tarihDegeri(r[8]),
        bitis: r[9] == null ? null : tarihDegeri(r[9]),
        otomatikYenileme: r[10]! as bool,
        ihbarSuresiGun: r[11] as int?,
        bedel: r[12] == null ? null : Para.kurus(r[12]! as int, birim: (r[13]! as String).trim()),
        birim: r[14]! as String,
        yenilemeSuresiAy: r[15]! as int,
        tarama: _taramaOku(r[17]),
      );

  static TaramaSonucu? _taramaOku(Object? v) {
    final j = v is String ? jsonDecode(v) : v;
    return j is Map<String, dynamic> ? TaramaSonucu.fromJson(j) : null;
  }

  static Map<String, Object?> _sozlesmeJson(Sozlesme s, int onayTuru, Tarih bugun) => {
        'id': s.id,
        'no': s.no,
        'sirketId': s.sirketId,
        'baslik': s.baslik,
        'tur': s.tur.name,
        'karsiTaraf': s.karsiTaraf,
        'sorumlu': s.sorumlu,
        'birim': s.birim,
        'durum': s.durum.name,
        'baslangic': s.baslangic?.isoBicim,
        'bitis': s.bitis?.isoBicim,
        'otomatikYenileme': s.otomatikYenileme,
        'yenilemeSuresiAy': s.yenilemeSuresiAy,
        'ihbarSuresiGun': s.ihbarSuresiGun,
        'ihbarSonGunu': s.ihbarSonGunu?.isoBicim,
        'bedelKurus': s.bedel?.kurus,
        'paraBirimi': s.bedel?.birim,
        'onayTuru': onayTuru,
        'tarama': s.tarama?.toJson(),
        'yukumlulukler': [
          for (final y in s.yukumlulukler)
            {
              'id': y.id,
              'aciklama': y.aciklama,
              'taraf': y.taraf.name,
              'sonTarih': y.sonTarih.isoBicim,
              'sorumlu': y.sorumlu.isEmpty ? null : y.sorumlu,
              'tamamlandi': y.tamamlandi,
            },
        ],
        'uyarilar': [
          for (final u in s.uyarilar(bugun)) {'tur': u.tur.name, 'mesaj': u.mesaj},
        ],
      };

  Future<Response> _sozlesmeler(Request istek) async {
    final k = kimlik(istek);
    final (rs, yk) = await vt.kiraciIcin(k, (tx) async {
      final s = await tx.execute('SELECT $_sozlesmeSutunlari FROM hukuk.sozlesme ORDER BY no DESC');
      final y = await tx.execute('SELECT id::text, sozlesme_id::text, aciklama, taraf, son_tarih, sorumlu::text, '
          'tamamlanma IS NOT NULL FROM hukuk.sozlesme_yukumluluk ORDER BY son_tarih');
      return (s, y);
    });
    final yukumlulukler = <String, List<Yukumluluk>>{};
    for (final y in yk) {
      (yukumlulukler[y[1]! as String] ??= []).add(Yukumluluk(
        id: y[0]! as String,
        aciklama: y[2]! as String,
        taraf: YukumlulukTarafi.values.byName(y[3]! as String),
        sonTarih: tarihDegeri(y[4]),
        sorumlu: (y[5] as String?) ?? '',
        tamamlandi: y[6]! as bool,
      ));
    }
    final bugun = Tarih.from(DateTime.now());
    return jsonYanit([
      for (final r in rs)
        _sozlesmeJson(_sozlesme(r)..yukumlulukler.addAll(yukumlulukler[r[0]] ?? const []), r[16]! as int, bugun),
    ]);
  }

  Future<Response> _yukumlulukEkle(Request istek, String sozlesmeId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final taraf = enumAlani(j, 'taraf', YukumlulukTarafi.values);
    final sonTarih = tarihAlani(j, 'sonTarih');
    final id = await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.sozlesme_yukumluluk (kiraci_id, sozlesme_id, aciklama, taraf, son_tarih, sorumlu) '
            'VALUES (CAST(@k AS uuid), CAST(@s AS uuid), @a, @t, CAST(@st AS date), CAST(@so AS uuid)) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          's': sozlesmeId,
          'a': zorunluMetin(j, 'aciklama'),
          't': taraf.name,
          'st': sonTarih.isoBicim,
          'so': (j['sorumlu'] as String?) ?? k.kullaniciId,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'yukumluluk', sozlesmeId, j['aciklama'] as String);
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _yukumlulukTamamla(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.sozlesme_yukumluluk SET tamamlanma = now(), tamamlayan = CAST(@u AS uuid) '
            'WHERE id = CAST(@id AS uuid) AND tamamlanma IS NULL RETURNING sozlesme_id::text, aciklama'),
        parameters: {'u': k.kullaniciId, 'id': id},
      );
      if (rs.isNotEmpty) {
        await DosyaApi.denetim(tx, k, 'degisiklik', 'yukumluluk', rs.first[0]! as String, 'Tamamlandı: ${rs.first[1]}');
      }
      return rs.length;
    });
    if (n == 0) throw const ApiHatasi(404, 'Açık yükümlülük bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'tamamlandi': true});
  }

  Future<Response> _sozlesmeEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'tur', SozlesmeTuru.values);
    final baslangic = j['baslangic'] == null ? null : tarihAlani(j, 'baslangic');
    final bitis = j['bitis'] == null ? null : tarihAlani(j, 'bitis');
    if (baslangic != null && bitis != null && bitis.isBefore(baslangic)) {
      throw const ApiHatasi(400, 'Bitiş tarihi başlangıçtan önce olamaz.', kod: 'gecersiz_istek');
    }
    final bedel = j['bedelKurus'];
    if (bedel != null && (bedel is! int || bedel < 0)) {
      throw const ApiHatasi(400, '"bedelKurus" sıfır veya pozitif tam sayı olmalı.', kod: 'gecersiz_istek');
    }
    final paraBirimi = ((j['paraBirimi'] as String?) ?? 'TRY').toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(paraBirimi)) {
      throw const ApiHatasi(400, 'Para birimi üç harfli kod olmalı (TRY, USD, EUR).', kod: 'gecersiz_istek');
    }
    // Metin gönderildiyse kural tabanlı tarama sunucuda yapılır (metin yurt dışına çıkmaz); bulunan alanlar
    // yalnızca kullanıcının boş bıraktığı alanlara uygulanır.
    final taslak = Sozlesme(
      id: '',
      no: '',
      baslik: zorunluMetin(j, 'baslik'),
      tur: tur,
      karsiTaraf: (j['karsiTaraf'] as String?)?.trim() ?? '',
      sorumlu: (j['sorumlu'] as String?) ?? k.kullaniciId,
      baslangic: baslangic,
      bitis: bitis,
      otomatikYenileme: j['otomatikYenileme'] == true,
      ihbarSuresiGun: j['ihbarSuresiGun'] as int?,
      bedel: bedel is int ? Para.kurus(bedel, birim: paraBirimi) : null,
    );
    final metin = (j['metin'] as String?) ?? '';
    if (metin.length > 2000000) throw const ApiHatasi(413, 'Sözleşme metni çok uzun.');
    if (metin.trim().isNotEmpty) taslak.taramayiUygula(const SozlesmeTarayici().tara(metin));
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final no = await _yeniNo(tx, k, 'sozlesme', 'SZ');
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.sozlesme (kiraci_id, no, sirket_id, baslik, tur, karsi_taraf, sorumlu, birim, baslangic, '
            'bitis, otomatik_yenileme, yenileme_suresi_ay, ihbar_gun, bedel_kurus, para_birimi, tarama) VALUES (CAST(@k AS uuid), '
            '@no, CAST(@s AS uuid), @b, @t, @kt, CAST(@so AS uuid), @bi, CAST(@ba AS date), CAST(@bt AS date), @oy, @ya, @ig, @be, '
            '@pb, CAST(@tr AS jsonb)) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'no': no,
          's': j['sirketId'] as String?,
          'b': taslak.baslik,
          't': taslak.tur.name,
          'kt': taslak.karsiTaraf,
          'so': taslak.sorumlu,
          'bi': (j['birim'] as String?)?.trim() ?? '',
          'ba': taslak.baslangic?.isoBicim,
          'bt': taslak.bitis?.isoBicim,
          'oy': taslak.otomatikYenileme,
          'ya': j['yenilemeSuresiAy'] is int ? j['yenilemeSuresiAy'] as int : 12,
          'ig': taslak.ihbarSuresiGun,
          'be': taslak.bedel?.kurus,
          'pb': taslak.bedel?.birim ?? paraBirimi,
          'tr': taslak.tarama == null ? null : jsonEncode(taslak.tarama!.toJson()),
        },
      );
      final id = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'sozlesme', id,
          '$no · ${taslak.baslik}${taslak.tarama == null ? '' : ' · risk ${taslak.tarama!.riskPuani}'}');
      return (id, no);
    });
    return jsonYanit({'id': sonuc.$1, 'no': sonuc.$2}, durum: 201);
  }

  /// Durum geçişi (çekirdekteki geçiş tablosuyla). "Onayda"ya her geçiş yeni bir onay turu başlatır;
  /// onaydan imzaya yalnızca onay zinciri tamamlanınca geçilir.
  Future<Response> _sozlesmeDurum(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final hedef = enumAlani(j, 'durum', SozlesmeDurumu.values);
    final baslangic = j['baslangic'] == null ? null : tarihAlani(j, 'baslangic');
    await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final rs = await tx.execute(
          Sql.named('SELECT $_sozlesmeSutunlari FROM hukuk.sozlesme WHERE id = CAST(@id AS uuid) FOR UPDATE'),
          parameters: {'id': id});
      if (rs.isEmpty) throw ApiHatasi.bulunamadi;
      final s = _sozlesme(rs.first);
      final onayTuru = rs.first[16]! as int;
      if (baslangic != null) s.baslangic = baslangic;
      if (s.durum == SozlesmeDurumu.onayda && hedef == SozlesmeDurumu.imzada) {
        final surec = await _surec(tx, s, onayTuru);
        if (surec.durum != OnaySurecDurumu.onaylandi) {
          throw const ApiHatasi(409, 'Onay zinciri tamamlanmadan imzaya geçilemez.', kod: 'kural');
        }
      }
      try {
        s.durumDegistir(hedef);
      } on StateError catch (e) {
        throw ApiHatasi(409, e.message, kod: 'kural');
      }
      await tx.execute(
        Sql.named('UPDATE hukuk.sozlesme SET durum = @d, baslangic = CAST(@b AS date), '
            'onay_turu = onay_turu + CASE WHEN @d = \'onayda\' THEN 1 ELSE 0 END WHERE id = CAST(@id AS uuid)'),
        parameters: {'d': hedef.name, 'b': s.baslangic?.isoBicim, 'id': id},
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'sozlesme', id, 'Durum: ${hedef.ad}');
    });
    return jsonYanit({'durum': hedef.name});
  }

  /// Kurumun onay politikası rollerden kurulur: hukuk ekibi, direktör, finans ve onaycı (genel müdür).
  static Future<OnayPolitikasi> _politika(TxSession tx) async {
    final rs = await tx.execute('SELECT r.kullanici_id::text, r.rol FROM hukuk.kullanici_rol r '
        'JOIN hukuk.kullanici u ON u.id = r.kullanici_id WHERE u.aktif');
    Set<String> rol(Set<String> adlar) => {for (final r in rs) if (adlar.contains(r[1])) r[0]! as String};
    return OnayPolitikasi(
      hukukEkibi: rol(hukukRolleri),
      hukukDirektoru: rol({'hukukDirektoru'}),
      finans: rol({'finansVeSatinAlma'}),
      genelMudur: rol({'onayci'}),
    );
  }

  /// Güncel turun kararlarıyla onay süreci (kararlar sırayla yeniden uygulanmaz; saklanan hâli yüklenir).
  static Future<OnaySureci> _surec(TxSession tx, Sozlesme s, int tur) async {
    final politika = await _politika(tx);
    final surec = OnaySureci(sozlesmeId: s.id, adimlar: politika.adimlar(s), baslatan: s.sorumlu);
    final rs = await tx.execute(
      Sql.named('SELECT adim_kodu, kullanici_id::text, karar, notu, zaman FROM hukuk.sozlesme_onay '
          'WHERE sozlesme_id = CAST(@id AS uuid) AND tur_no = @t ORDER BY adim_sira'),
      parameters: {'id': s.id, 't': tur},
    );
    for (final r in rs) {
      final karar = OnayKarariTuru.values.byName(r[2]! as String);
      surec.kararlar.add(OnayKarari(
          adimKodu: r[0]! as String, kullanici: r[1]! as String, tur: karar, not: r[3]! as String, zaman: r[4]! as DateTime));
      surec.durum = switch (karar) {
        OnayKarariTuru.ret => OnaySurecDurumu.reddedildi,
        OnayKarariTuru.revizyon => OnaySurecDurumu.revizyon,
        OnayKarariTuru.onay => surec.kararlar.where((x) => x.tur == OnayKarariTuru.onay).length >= surec.adimlar.length
            ? OnaySurecDurumu.onaylandi
            : OnaySurecDurumu.devam,
      };
    }
    return surec;
  }

  static Map<String, Object?> _surecJson(OnaySureci s, int tur, String kullanici) => {
        'tur': tur,
        'durum': s.durum.name,
        'siradaki': s.siradaki?.kod,
        'onaylayabilir': s.onaylayabilir(kullanici),
        'adimlar': [
          for (final a in s.adimlar) {'kod': a.kod, 'ad': a.ad, 'neden': a.neden, 'onaycilar': a.onaycilar.toList()..sort()},
        ],
        'kararlar': [
          for (final x in s.kararlar)
            {'adimKodu': x.adimKodu, 'kullanici': x.kullanici, 'karar': x.tur.name, 'not': x.not, 'zaman': x.zaman.toIso8601String()},
        ],
      };

  Future<(Sozlesme, int)> _sozlesmeOku(TxSession tx, String id, {bool kilitle = false}) async {
    final rs = await tx.execute(
        Sql.named('SELECT $_sozlesmeSutunlari FROM hukuk.sozlesme WHERE id = CAST(@id AS uuid)${kilitle ? ' FOR UPDATE' : ''}'),
        parameters: {'id': id});
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    return (_sozlesme(rs.first), rs.first[16]! as int);
  }

  Future<Response> _onayDurumu(Request istek, String id) async {
    final k = kimlik(istek);
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final (s, tur) = await _sozlesmeOku(tx, id);
      if (tur == 0) return <String, Object?>{'tur': 0, 'durum': null, 'adimlar': <Object>[], 'kararlar': <Object>[]};
      return _surecJson(await _surec(tx, s, tur), tur, k.kullaniciId);
    });
    return jsonYanit(sonuc);
  }

  Future<Response> _onayKarari(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final karar = enumAlani(j, 'karar', OnayKarariTuru.values);
    final not = (j['not'] as String?) ?? '';
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final (s, tur) = await _sozlesmeOku(tx, id, kilitle: true);
      if (s.durum != SozlesmeDurumu.onayda || tur == 0) {
        throw const ApiHatasi(409, 'Sözleşme onay aşamasında değil.', kod: 'kural');
      }
      final surec = await _surec(tx, s, tur);
      final adimSira = surec.kararlar.length;
      try {
        surec.karar(k.kullaniciId, karar, DateTime.now(), not: not);
      } on StateError catch (e) {
        throw ApiHatasi(409, e.message, kod: 'kural');
      } on ArgumentError catch (e) {
        throw ApiHatasi(400, '${e.message}', kod: 'gecersiz_istek');
      }
      final son = surec.kararlar.last;
      await tx.execute(
        Sql.named('INSERT INTO hukuk.sozlesme_onay (kiraci_id, sozlesme_id, tur_no, adim_sira, adim_kodu, kullanici_id, karar, notu) '
            'VALUES (CAST(@k AS uuid), CAST(@s AS uuid), @t, @a, @ak, CAST(@u AS uuid), @karar, @n)'),
        parameters: {
          'k': k.kiraciId,
          's': id,
          't': tur,
          'a': adimSira,
          'ak': son.adimKodu,
          'u': k.kullaniciId,
          'karar': karar.name,
          'n': son.not,
        },
      );
      // Süreç sonuçlanınca sözleşme imzaya veya müzakereye geçer.
      final yeniDurum = switch (surec.durum) {
        OnaySurecDurumu.onaylandi => SozlesmeDurumu.imzada,
        OnaySurecDurumu.reddedildi || OnaySurecDurumu.revizyon => SozlesmeDurumu.muzakere,
        OnaySurecDurumu.devam => null,
      };
      if (yeniDurum != null) {
        await tx.execute(Sql.named('UPDATE hukuk.sozlesme SET durum = @d WHERE id = CAST(@id AS uuid)'),
            parameters: {'d': yeniDurum.name, 'id': id});
      }
      await DosyaApi.denetim(tx, k, 'degisiklik', 'sozlesme', id, 'Onay (${son.adimKodu}): ${karar.ad}');
      return _surecJson(surec, tur, k.kullaniciId);
    });
    return jsonYanit(sonuc);
  }

  // ---------------------------------------------------------------------------
  // Hukuk talepleri
  // ---------------------------------------------------------------------------

  static const _talepSutunlari = 'id::text, no, sirket_id::text, baslik, aciklama, tur, oncelik, talep_eden, birim, '
      'atanan::text, durum, sla_son_gun, olusturma, kapanis, sozlesme_id::text, bekleme_baslangici, ret_gerekcesi';

  static HukukTalebi _talep(List<Object?> r) => HukukTalebi(
        id: r[0]! as String,
        no: r[1]! as String,
        sirketId: r[2] as String?,
        baslik: r[3]! as String,
        aciklama: r[4]! as String,
        tur: TalepTuru.values.firstWhere((t) => t.name == r[5], orElse: () => TalepTuru.diger),
        oncelik: Oncelik.values.byName(r[6]! as String),
        talepEden: r[7]! as String,
        birim: r[8]! as String,
        olusturma: tarihDegeri(r[12]),
        slaSonGun: tarihDegeri(r[11]),
        sozlesmeId: r[14] as String?,
        beklemeBaslangici: r[15] == null ? null : tarihDegeri(r[15]),
      )
        ..atanan = (r[9] as String?) ?? ''
        ..durum = TalepDurumu.values.byName(r[10]! as String)
        ..kapanis = r[13] == null ? null : tarihDegeri(r[13]);

  static Map<String, Object?> _talepJson(HukukTalebi t, Tarih bugun, List<Map<String, Object?>> gecmis) => {
        'id': t.id,
        'no': t.no,
        'sirketId': t.sirketId,
        'baslik': t.baslik,
        'aciklama': t.aciklama,
        'tur': t.tur.name,
        'oncelik': t.oncelik.name,
        'talepEden': t.talepEden,
        'birim': t.birim,
        'atanan': t.atanan.isEmpty ? null : t.atanan,
        'durum': t.durum.name,
        'slaSonGun': t.slaSonGun.isoBicim,
        'slaDurumu': t.slaDurumu(bugun, _isGunu).name,
        'olusturma': t.olusturma.isoBicim,
        'kapanis': t.kapanis?.isoBicim,
        'sozlesmeId': t.sozlesmeId,
        'beklemeBaslangici': t.beklemeBaslangici?.isoBicim,
        'gecmis': gecmis,
      };

  Future<Response> _talepler(Request istek) async {
    final k = kimlik(istek);
    final (talepler, olaylar) = await vt.kiraciIcin(k, (tx) async {
      final t = await tx.execute('SELECT $_talepSutunlari FROM hukuk.hukuk_talebi ORDER BY olusturma DESC, no DESC LIMIT 2000');
      final o = await tx.execute('SELECT talep_id::text, tarih, kullanici, aciklama FROM hukuk.talep_olayi ORDER BY id');
      return (t, o);
    });
    final gecmis = <String, List<Map<String, Object?>>>{};
    for (final o in olaylar) {
      (gecmis[o[0]! as String] ??= []).add({'tarih': tarihMetni(o[1]), 'kullanici': o[2], 'aciklama': o[3]});
    }
    final bugun = Tarih.from(DateTime.now());
    return jsonYanit([for (final r in talepler) _talepJson(_talep(r), bugun, gecmis[r[0]] ?? const [])]);
  }

  static Future<void> _olay(TxSession tx, KimlikBaglami k, String talepId, String aciklama) => tx.execute(
        Sql.named('INSERT INTO hukuk.talep_olayi (kiraci_id, talep_id, kullanici, aciklama) '
            'VALUES (CAST(@k AS uuid), CAST(@t AS uuid), @u, @a)'),
        parameters: {'k': k.kiraciId, 't': talepId, 'u': k.kullaniciId, 'a': aciklama},
      );

  static Future<void> _talepYaz(TxSession tx, HukukTalebi t, {String? retGerekcesi}) => tx.execute(
        Sql.named('UPDATE hukuk.hukuk_talebi SET durum = @d, atanan = CAST(@a AS uuid), sla_son_gun = CAST(@s AS date), '
            'kapanis = CAST(@kp AS date), bekleme_baslangici = CAST(@bb AS date), '
            'ret_gerekcesi = coalesce(@r, ret_gerekcesi) WHERE id = CAST(@id AS uuid)'),
        parameters: {
          'd': t.durum.name,
          'a': t.atanan.isEmpty ? null : t.atanan,
          's': t.slaSonGun.isoBicim,
          'kp': t.kapanis?.isoBicim,
          'bb': t.beklemeBaslangici?.isoBicim,
          'r': retGerekcesi,
          'id': t.id,
        },
      );

  /// Yeni talep: SLA son günü iş günü takvimiyle sunucuda hesaplanır; açık işi en az olan hukuk ekibi üyesine atanır.
  Future<Response> _talepEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'tur', TalepTuru.values);
    final oncelik = enumAlani(j, 'oncelik', Oncelik.values);
    final baslik = zorunluMetin(j, 'baslik');
    final bugun = Tarih.from(DateTime.now());
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final no = await _yeniNo(tx, k, 'talep', 'HT');
      final adRs = await tx.execute(Sql.named('SELECT ad_soyad FROM hukuk.kullanici WHERE id = CAST(@u AS uuid)'),
          parameters: {'u': k.kullaniciId});
      final talepEden = adRs.isEmpty ? k.kullaniciId : adRs.first[0]! as String;
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.hukuk_talebi (kiraci_id, no, sirket_id, baslik, aciklama, tur, oncelik, talep_eden, '
            'talep_eden_kullanici, birim, sla_son_gun, olusturma, sozlesme_id) VALUES (CAST(@k AS uuid), @no, CAST(@s AS uuid), '
            '@b, @a, @t, @o, @te, CAST(@u AS uuid), @bi, CAST(@sla AS date), CAST(@bg AS date), CAST(@sz AS uuid)) '
            'RETURNING $_talepSutunlari'),
        parameters: {
          'k': k.kiraciId,
          'no': no,
          's': j['sirketId'] as String?,
          'b': baslik,
          'a': (j['aciklama'] as String?)?.trim() ?? '',
          't': tur.name,
          'o': oncelik.name,
          'te': talepEden,
          'u': k.kullaniciId,
          'bi': zorunluMetin(j, 'birim'),
          'sla': _isGunu.ekle(bugun, oncelik.slaIsGunu(tur)).isoBicim,
          'bg': bugun.isoBicim,
          'sz': j['sozlesmeId'] as String?,
        },
      );
      final t = _talep(rs.first);
      await _olay(tx, k, t.id, 'Talep oluşturuldu');
      final aday = await tx.execute(
        Sql.named("SELECT r.kullanici_id::text, u.ad_soyad FROM hukuk.kullanici_rol r JOIN hukuk.kullanici u ON u.id = r.kullanici_id "
            "WHERE u.aktif AND r.rol IN ('sirketAvukati', 'hukukUzmani') GROUP BY r.kullanici_id, u.ad_soyad "
            "ORDER BY (SELECT count(*) FROM hukuk.hukuk_talebi h WHERE h.atanan = r.kullanici_id "
            "AND h.durum NOT IN ('tamamlandi', 'reddedildi')), r.kullanici_id LIMIT 1"),
      );
      if (aday.isNotEmpty) {
        t.atanan = aday.first[0]! as String;
        t.durumDegistir(TalepDurumu.atandi, kullanici: 'sistem', bugun: bugun, hesap: _isGunu, not: aday.first[1]! as String);
        await _talepYaz(tx, t);
        await _olay(tx, k, t.id, 'Otomatik atandı: ${aday.first[1]}');
      }
      await DosyaApi.denetim(tx, k, 'olusturma', 'talep', t.id, '$no · $baslik');
      return (t.id, no, t.slaSonGun);
    });
    return jsonYanit({'id': sonuc.$1, 'no': sonuc.$2, 'slaSonGun': sonuc.$3.isoBicim}, durum: 201);
  }

  Future<HukukTalebi> _talepOku(TxSession tx, String id) async {
    final rs = await tx.execute(
        Sql.named('SELECT $_talepSutunlari FROM hukuk.hukuk_talebi WHERE id = CAST(@id AS uuid) FOR UPDATE'),
        parameters: {'id': id});
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    return _talep(rs.first);
  }

  Future<Response> _talepDurum(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final hedef = enumAlani(j, 'durum', TalepDurumu.values);
    final not = ((j['not'] as String?) ?? '').trim();
    final bugun = Tarih.from(DateTime.now());
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final t = await _talepOku(tx, id);
      try {
        t.durumDegistir(hedef, kullanici: k.kullaniciId, bugun: bugun, hesap: _isGunu, not: not);
      } on StateError catch (e) {
        throw ApiHatasi(409, e.message, kod: 'kural');
      } on ArgumentError catch (e) {
        throw ApiHatasi(400, '${e.message}', kod: 'gecersiz_istek');
      }
      await _talepYaz(tx, t, retGerekcesi: hedef == TalepDurumu.reddedildi ? not : null);
      await _olay(tx, k, id, '${hedef.ad}${not.isEmpty ? '' : ': $not'}');
      await DosyaApi.denetim(tx, k, 'degisiklik', 'talep', id, 'Durum: ${hedef.ad}');
      return t;
    });
    return jsonYanit({'durum': sonuc.durum.name, 'slaSonGun': sonuc.slaSonGun.isoBicim});
  }

  Future<Response> _talepAta(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kisi = zorunluMetin(j, 'kullaniciId');
    final bugun = Tarih.from(DateTime.now());
    await vt.kiraciIcin(k, (tx) async {
      await _hukukEkibiOlmali(tx, k);
      final roller = await _roller(tx, kisi);
      if (roller.intersection(hukukRolleri).isEmpty) {
        throw const ApiHatasi(400, 'Talep yalnızca hukuk ekibinden birine atanabilir.', kod: 'gecersiz_istek');
      }
      final t = await _talepOku(tx, id);
      if (t.durum.kapali) throw const ApiHatasi(409, 'Kapanmış talep yeniden atanamaz.', kod: 'kural');
      final ad = await tx.execute(Sql.named('SELECT ad_soyad FROM hukuk.kullanici WHERE id = CAST(@u AS uuid)'),
          parameters: {'u': kisi});
      final adSoyad = ad.isEmpty ? kisi : ad.first[0]! as String;
      t.atanan = kisi;
      if (t.durum == TalepDurumu.yeni) {
        t.durumDegistir(TalepDurumu.atandi, kullanici: k.kullaniciId, bugun: bugun, hesap: _isGunu, not: adSoyad);
      }
      await _talepYaz(tx, t);
      await _olay(tx, k, id, 'Atandı: $adSoyad');
      await DosyaApi.denetim(tx, k, 'degisiklik', 'talep', id, 'Atandı: $adSoyad');
    });
    return jsonYanit({'atanan': kisi});
  }
}
