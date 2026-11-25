import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Kişiler, finans (cari ve emanet), zaman kaydı ve icra uçları.
/// Kurallar veritabanında da zorlanır (emanet eksiye düşmez, zaman kaydı 24 saat sınırı, kendi kaydını onaylayamama…);
/// hesaplamalar (cari özet, icra dosya hesabı) hukuk_cekirdek ile sunucuda yapılır.
class IsApi {
  IsApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..get('/kisiler', _kisiler)
    ..post('/kisiler', _kisiEkle)
    ..put('/kisiler/<id>', _kisiGuncelle)
    ..post('/kisiler/toplu', _kisiTopluEkle)
    ..get('/kisi-iliskileri', _iliskiler)
    ..post('/kisi-iliskileri', _iliskiEkle)
    ..delete('/kisi-iliskileri/<id>', _iliskiSil)
    ..get('/kisiler/<id>/cari', _cari)
    ..get('/cari', _cariTumu)
    ..post('/cari', _cariEkle)
    ..get('/emanet', _emanet)
    ..post('/emanet', _emanetEkle)
    ..get('/zaman', _zaman)
    ..post('/zaman', _zamanEkle)
    ..post('/zaman/<id>/onayla', _zamanOnayla)
    ..delete('/zaman/<id>', _zamanSil)
    ..post('/dosyalar/<id>/zaman-faturasi', _zamanFaturasi)
    ..get('/icra', _icraListe)
    ..post('/icra', _icraEkle)
    ..post('/icra/toplu', _topluTakip)
    ..get('/icra/<id>', _icraAyrinti)
    ..post('/icra/<id>/tahsilat', _icraTahsilat)
    ..post('/icra/<id>/durum', _icraDurum);

  // ---------------------------------------------------------------------------
  // Kişiler
  // ---------------------------------------------------------------------------

  Future<Response> _kisiler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, tur, ad, kimlik_no, eposta, mersis_no, telefon, adres, iletisim_tercihi, '
            'notlar, unvan_gecmisi FROM hukuk.kisi ORDER BY ad LIMIT 5000'));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'tur': r[1],
          'ad': r[2],
          'kimlikNo': r[3],
          'eposta': r[4],
          'mersisNo': r[5],
          'telefon': r[6],
          'adres': r[7],
          'iletisimTercihi': r[8],
          'notlar': r[9],
          'unvanGecmisi': r[10],
        },
    ]);
  }

  /// Boş metin alanı `null` olarak saklanır; çok uzun alan reddedilir.
  static String? _istegeBagli(Map<String, dynamic> j, String ad, int azami) {
    final v = (j[ad] as String?)?.trim();
    if (v == null || v.isEmpty) return null;
    if (v.length > azami) throw ApiHatasi(400, '$ad çok uzun.', kod: 'gecersiz_istek');
    return v;
  }

  static void _kisiAlanlariniDogrula(KisiTuru tur, String? no, String? eposta, String? mersis) {
    if (no != null) {
      final gecerli = tur == KisiTuru.gercek ? Dogrulayicilar.tcknGecerli(no) : Dogrulayicilar.vknGecerli(no);
      if (!gecerli) throw const ApiHatasi(400, 'Kimlik/vergi numarası geçersiz.', kod: 'gecersiz_istek');
    }
    if (eposta != null && Dogrulayicilar.eposta(eposta) != null) {
      throw const ApiHatasi(400, 'E-posta adresi geçersiz.', kod: 'gecersiz_istek');
    }
    if (mersis != null && !RegExp(r'^[0-9]{16}$').hasMatch(mersis)) {
      throw const ApiHatasi(400, 'MERSİS numarası 16 haneli olmalıdır.', kod: 'gecersiz_istek');
    }
  }

  /// Excel/CSV aktarımı: önizlemeden geçen satırlar tek işlemde eklenir. Geçersiz satır varsa hiçbiri eklenmez
  /// (satır numarasıyla hata döner); kimlik numarası zaten kayıtlı olan satır atlanır (eşzamanlı ekleme için).
  Future<Response> _kisiTopluEkle(Request istek) async {
    final k = kimlik(istek);
    final liste = ((await jsonGovde(istek))['kisiler'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (liste.isEmpty) throw const ApiHatasi(400, 'Aktarılacak kayıt yok.', kod: 'eksik_alan');
    if (liste.length > 5000) throw const ApiHatasi(400, 'Tek seferde en fazla 5000 kayıt aktarılabilir.', kod: 'gecersiz_istek');
    final satirlar = <Map<String, Object?>>[];
    for (var i = 0; i < liste.length; i++) {
      final j = liste[i];
      try {
        final tur = enumAlani(j, 'tur', KisiTuru.values);
        final ad = zorunluMetin(j, 'ad');
        if (ad.length > 300) throw const ApiHatasi(400, 'Ad çok uzun.');
        final no = _istegeBagli(j, 'kimlikNo', 11)?.replaceAll(' ', '');
        final eposta = _istegeBagli(j, 'eposta', 200);
        _kisiAlanlariniDogrula(tur, no, eposta, null);
        satirlar.add({
          't': tur.name,
          'a': ad,
          'n': no,
          'e': eposta,
          'tel': _istegeBagli(j, 'telefon', 30),
          'adr': _istegeBagli(j, 'adres', 500),
        });
      } on ApiHatasi catch (e) {
        final no = j['satirNo'] ?? i + 1;
        throw ApiHatasi(400, '$no. satır: ${e.mesaj}', kod: 'gecersiz_istek');
      }
    }
    final eklenen = await vt.kiraciIcin(k, (tx) async {
      var n = 0;
      for (final s in satirlar) {
        final rs = await tx.execute(
          Sql.named('INSERT INTO hukuk.kisi (kiraci_id, tur, ad, kimlik_no, eposta, telefon, adres) '
              'VALUES (CAST(@k AS uuid), @t, @a, @n, @e, @tel, @adr) '
              'ON CONFLICT (kiraci_id, kimlik_no) WHERE kimlik_no IS NOT NULL DO NOTHING'),
          parameters: {'k': k.kiraciId, ...s},
        );
        n += rs.affectedRows;
      }
      await DosyaApi.denetim(tx, k, 'aktarim', 'kisi', '-', 'Gönderilen ${satirlar.length}, eklenen $n');
      return n;
    });
    return jsonYanit({'eklenen': eklenen, 'atlanan': satirlar.length - eklenen}, durum: 201);
  }

  /// Kartın tamamı gönderilir (gönderilmeyen alan boşaltılır). Tür değişmez; ad değişirse eski ad unvan geçmişine
  /// veritabanında eklenir.
  Future<Response> _kisiGuncelle(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final ad = zorunluMetin(j, 'ad');
    final no = _istegeBagli(j, 'kimlikNo', 11);
    final eposta = _istegeBagli(j, 'eposta', 200);
    final mersis = _istegeBagli(j, 'mersisNo', 16);
    final tercih = j['iletisimTercihi'] == null ? IletisimTercihi.eposta : enumAlani(j, 'iletisimTercihi', IletisimTercihi.values);
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final t = await tx.execute(Sql.named('SELECT tur, ad FROM hukuk.kisi WHERE id = CAST(@i AS uuid)'), parameters: {'i': id});
      if (t.isEmpty) throw ApiHatasi.bulunamadi;
      final tur = KisiTuru.values.byName(t.first[0]! as String);
      _kisiAlanlariniDogrula(tur, no, eposta, mersis);
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.kisi SET ad = @a, kimlik_no = @n, eposta = @e, mersis_no = @m, telefon = @t, adres = @adr, '
            'iletisim_tercihi = @it, notlar = @not WHERE id = CAST(@i AS uuid) RETURNING unvan_gecmisi'),
        parameters: {
          'i': id,
          'a': ad,
          'n': no,
          'e': eposta,
          'm': mersis,
          't': _istegeBagli(j, 'telefon', 30),
          'adr': _istegeBagli(j, 'adres', 500),
          'it': tercih.name,
          'not': _istegeBagli(j, 'notlar', 2000),
        },
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'kisi', id, t.first[1] == ad ? 'Kart güncellendi' : 'Unvan: ${t.first[1]} → $ad');
      return rs.first[0];
    });
    return jsonYanit({'unvanGecmisi': sonuc});
  }

  Future<Response> _iliskiler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k, (tx) => tx.execute('SELECT id::text, kisi_a::text, kisi_b::text, tur FROM hukuk.kisi_iliski ORDER BY olusturma'));
    return jsonYanit([
      for (final r in rs) {'id': r[0], 'kisiA': r[1], 'kisiB': r[2], 'tur': r[3]},
    ]);
  }

  Future<Response> _iliskiEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final a = zorunluMetin(j, 'kisiA');
    final b = zorunluMetin(j, 'kisiB');
    if (a == b) throw const ApiHatasi(400, 'Kişi kendisiyle ilişkilendirilemez.', kod: 'gecersiz_istek');
    final tur = enumAlani(j, 'tur', IliskiTuru.values);
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.kisi_iliski (kiraci_id, kisi_a, kisi_b, tur) '
            'VALUES (CAST(@k AS uuid), CAST(@a AS uuid), CAST(@b AS uuid), @t) RETURNING id::text'),
        parameters: {'k': k.kiraciId, 'a': a, 'b': b, 't': tur.name},
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'kisi_iliski', yeni, '$a ↔ $b (${tur.name})');
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _iliskiSil(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(Sql.named('DELETE FROM hukuk.kisi_iliski WHERE id = CAST(@i AS uuid) '
          "RETURNING kisi_a::text || ' ↔ ' || kisi_b::text || ' (' || tur || ')'"), parameters: {'i': id});
      if (rs.isNotEmpty) await DosyaApi.denetim(tx, k, 'silme', 'kisi_iliski', id, rs.first[0]! as String);
      return rs.length;
    });
    if (n == 0) throw ApiHatasi.bulunamadi;
    return jsonYanit({'silindi': true});
  }

  Future<Response> _kisiEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'tur', KisiTuru.values);
    final ad = zorunluMetin(j, 'ad');
    final no = (j['kimlikNo'] as String?)?.trim();
    if (no != null && no.isNotEmpty) {
      final gecerli = tur == KisiTuru.gercek ? Dogrulayicilar.tcknGecerli(no) : Dogrulayicilar.vknGecerli(no);
      if (!gecerli) throw const ApiHatasi(400, 'Kimlik/vergi numarası geçersiz.', kod: 'gecersiz_istek');
    }
    final eposta = (j['eposta'] as String?)?.trim();
    if (eposta != null && eposta.isNotEmpty && Dogrulayicilar.eposta(eposta) != null) {
      throw const ApiHatasi(400, 'E-posta adresi geçersiz.', kod: 'gecersiz_istek');
    }
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.kisi (kiraci_id, tur, ad, kimlik_no, eposta, telefon, adres) '
            'VALUES (CAST(@k AS uuid), @t, @a, @n, @e, @tel, @adr) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          't': tur.name,
          'a': ad,
          'n': no == null || no.isEmpty ? null : no,
          'e': eposta == null || eposta.isEmpty ? null : eposta,
          'tel': _istegeBagli(j, 'telefon', 30),
          'adr': _istegeBagli(j, 'adres', 500),
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'kisi', yeni, ad);
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  // ---------------------------------------------------------------------------
  // Cari ve emanet
  // ---------------------------------------------------------------------------

  Future<Response> _cari(Request istek, String muvekkilId) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id::text, dosya_id::text, tur, tutar_kurus, tarih, aciklama, belge_no '
                  'FROM hukuk.cari_hareket WHERE muvekkil_id = CAST(@m AS uuid) ORDER BY tarih, zaman'),
              parameters: {'m': muvekkilId},
            ));
    final hareketler = [
      for (final r in rs)
        CariHareket(
          id: r[0]! as String,
          muvekkilId: muvekkilId,
          dosyaId: r[1] as String?,
          tur: CariHareketTuru.values.byName(r[2]! as String),
          tutar: Para.kurus(r[3]! as int),
          tarih: tarihDegeri(r[4]),
          aciklama: r[5]! as String,
          belge: r[6] as String?,
        ),
    ];
    final ozet = CariOzet(hareketler);
    return jsonYanit({
      'avansBakiyesiKurus': ozet.avansBakiyesi.kurus,
      'toplamMasrafKurus': ozet.toplamMasraf.kurus,
      'ucretAlacagiKurus': ozet.ucretAlacagi.kurus,
      'hareketler': [
        for (final h in hareketler.reversed)
          {
            'id': h.id,
            'dosyaId': h.dosyaId,
            'tur': h.tur.name,
            'tutarKurus': h.tutar.kurus,
            'tarih': h.tarih.isoBicim,
            'aciklama': h.aciklama,
            'belgeNo': h.belge,
          },
      ],
    });
  }

  Future<Response> _cariEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'tur', CariHareketTuru.values);
    final tutar = kurusAlani(j, 'tutarKurus');
    final tarih = tarihAlani(j, 'tarih', varsayilan: Tarih.from(DateTime.now()));
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.cari_hareket (kiraci_id, muvekkil_id, dosya_id, tur, tutar_kurus, tarih, aciklama, belge_no) '
            'VALUES (CAST(@k AS uuid), CAST(@m AS uuid), CAST(@d AS uuid), @t, @tutar, CAST(@tarih AS date), @a, @b) '
            'RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'm': zorunluMetin(j, 'muvekkilId'),
          'd': j['dosyaId'] as String?,
          't': tur.name,
          'tutar': tutar,
          'tarih': tarih.isoBicim,
          'a': zorunluMetin(j, 'aciklama'),
          'b': j['belgeNo'] as String?,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'cari', yeni, '${tur.ad} · ${Para.kurus(tutar).bicimli}');
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  /// Emanet hareketleri (bakiye istemcide çekirdekteki EmanetHesabi ile hesaplanır; sunucuda da tetikleyici zorlar).
  Future<Response> _emanet(Request istek) async {
    final k = kimlik(istek);
    final m = istek.url.queryParameters['muvekkil'];
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id::text, muvekkil_id::text, dosya_id::text, tur, tutar_kurus, tarih, aciklama, mahsup_onayi '
                  'FROM hukuk.emanet_hareket WHERE (CAST(@m AS uuid) IS NULL OR muvekkil_id = CAST(@m AS uuid)) '
                  'ORDER BY tarih, id LIMIT 10000'),
              parameters: {'m': m},
            ));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'muvekkilId': r[1],
          'dosyaId': r[2],
          'tur': r[3],
          'tutarKurus': r[4],
          'tarih': tarihMetni(r[5]),
          'aciklama': r[6],
          'mahsupOnayi': r[7],
        },
    ]);
  }

  /// Tüm cari hareketler (istemci önbelleği için; en yeni 10.000).
  Future<Response> _cariTumu(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT id::text, muvekkil_id::text, dosya_id::text, tur, tutar_kurus, tarih, aciklama, belge_no '
            'FROM hukuk.cari_hareket ORDER BY tarih DESC, zaman DESC LIMIT 10000'));
    return jsonYanit([
      for (final r in rs)
        {
          'id': r[0],
          'muvekkilId': r[1],
          'dosyaId': r[2],
          'tur': r[3],
          'tutarKurus': r[4],
          'tarih': tarihMetni(r[5]),
          'aciklama': r[6],
          'belgeNo': r[7],
        },
    ]);
  }

  Future<Response> _emanetEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'tur', EmanetHareketTuru.values);
    final tutar = kurusAlani(j, 'tutarKurus');
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.emanet_hareket (kiraci_id, muvekkil_id, dosya_id, tur, tutar_kurus, tarih, aciklama, '
            'mahsup_onayi) VALUES (CAST(@k AS uuid), CAST(@m AS uuid), CAST(@d AS uuid), @t, @tutar, CAST(@tarih AS date), '
            '@a, @o) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'm': zorunluMetin(j, 'muvekkilId'),
          'd': zorunluMetin(j, 'dosyaId'),
          't': tur.name,
          'tutar': tutar,
          'tarih': tarihAlani(j, 'tarih', varsayilan: Tarih.from(DateTime.now())).isoBicim,
          'a': zorunluMetin(j, 'aciklama'),
          'o': j['mahsupOnayi'] as String?,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'emanet', yeni, '${tur.ad} · ${Para.kurus(tutar).bicimli}');
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  // ---------------------------------------------------------------------------
  // Zaman kaydı
  // ---------------------------------------------------------------------------

  Future<Response> _zaman(Request istek) async {
    final k = kimlik(istek);
    final q = istek.url.queryParameters;
    final bugun = Tarih.from(DateTime.now());
    final bas = q['bas'] == null ? bugun.gunEkle(-30) : tarihAlani(q, 'bas');
    final son = q['son'] == null ? bugun : tarihAlani(q, 'son');
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT id::text, kullanici_id::text, dosya_id::text, tarih, dakika, aciklama, saatlik_kurus, '
                  'faturalanabilir, durum, onaylayan::text, fatura_no FROM hukuk.zaman_kaydi '
                  'WHERE tarih BETWEEN CAST(@b AS date) AND CAST(@s AS date) ORDER BY tarih DESC'),
              parameters: {'b': bas.isoBicim, 's': son.isoBicim},
            ));
    return jsonYanit([
      for (final r in rs)
        () {
          final kayit = ZamanKaydi(
            id: r[0]! as String,
            kullanici: r[1]! as String,
            dosyaId: r[2]! as String,
            tarih: tarihDegeri(r[3]),
            dakika: r[4]! as int,
            aciklama: r[5]! as String,
            saatlikUcret: Para.kurus(r[6]! as int),
            faturalanabilir: r[7]! as bool,
            durum: ZamanDurumu.values.byName(r[8]! as String),
            onaylayan: r[9] as String?,
            faturaNo: r[10] as String?,
          );
          return {
            'id': kayit.id,
            'kullanici': kayit.kullanici,
            'dosyaId': kayit.dosyaId,
            'tarih': kayit.tarih.isoBicim,
            'dakika': kayit.dakika,
            'faturaDakikasi': kayit.faturaDakikasi(),
            'aciklama': kayit.aciklama,
            'saatlikKurus': kayit.saatlikUcret.kurus,
            'tutarKurus': kayit.tutar().kurus,
            'faturalanabilir': kayit.faturalanabilir,
            'durum': kayit.durum.name,
            'onaylayan': kayit.onaylayan,
            'faturaNo': kayit.faturaNo,
          };
        }(),
    ]);
  }

  Future<Response> _zamanEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final dakika = j['dakika'];
    if (dakika is! int) throw const ApiHatasi(400, '"dakika" tam sayı olmalı.', kod: 'gecersiz_istek');
    final id = await vt.kiraciIcin(k, (tx) async {
      // Saatlik ücret istemciden alınmaz: kullanıcının kurumdaki tarifesi (şimdilik kurum varsayılanı) kullanılır.
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.zaman_kaydi (kiraci_id, kullanici_id, dosya_id, tarih, dakika, aciklama, saatlik_kurus, '
            'faturalanabilir) VALUES (CAST(@k AS uuid), CAST(@u AS uuid), CAST(@d AS uuid), CAST(@t AS date), @dk, @a, '
            '@ucret, @f) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'u': k.kullaniciId,
          'd': zorunluMetin(j, 'dosyaId'),
          't': tarihAlani(j, 'tarih', varsayilan: Tarih.from(DateTime.now())).isoBicim,
          'dk': dakika,
          'a': zorunluMetin(j, 'aciklama'),
          'ucret': 200000,
          'f': j['faturalanabilir'] != false,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'zaman', yeni, '$dakika dk');
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _zamanOnayla(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named("UPDATE hukuk.zaman_kaydi SET durum = 'onaylandi', onaylayan = CAST(@u AS uuid) "
            "WHERE id = CAST(@id AS uuid) AND durum = 'taslak'"),
        parameters: {'u': k.kullaniciId, 'id': id},
      );
      if (rs.affectedRows == 1) await DosyaApi.denetim(tx, k, 'degisiklik', 'zaman', id, 'Onaylandı');
      return rs.affectedRows;
    });
    if (n == 0) throw const ApiHatasi(404, 'Onay bekleyen zaman kaydı bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'durum': 'onaylandi'});
  }

  /// Yalnızca kendi taslak kaydı silinebilir (onaylı kaydı silme veritabanında da engellenir).
  Future<Response> _zamanSil(Request istek, String id) async {
    final k = kimlik(istek);
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named("DELETE FROM hukuk.zaman_kaydi WHERE id = CAST(@id AS uuid) AND kullanici_id = CAST(@u AS uuid) "
            "AND durum = 'taslak' RETURNING dakika, aciklama"),
        parameters: {'id': id, 'u': k.kullaniciId},
      );
      if (rs.isNotEmpty) await DosyaApi.denetim(tx, k, 'silme', 'zaman', id, '${rs.first[0]} dk · ${rs.first[1]}');
      return rs.length;
    });
    if (n == 0) throw const ApiHatasi(404, 'Silinebilecek taslak kaydınız bulunamadı.', kod: 'bulunamadi');
    return jsonYanit({'silindi': true});
  }

  // ---------------------------------------------------------------------------
  // İcra
  // ---------------------------------------------------------------------------

  static const _icraSutunlari = 'id::text, dosya_id::text, icra_dairesi, esas_no, borclu, takip_turu, asil_kurus, temerrut, '
      'takip_tarihi, faiz_turu, durum, vekalet_kurus, takip_oncesi_masraf_kurus, takip_sonrasi_masraf_kurus, '
      'islemis_faiz_elle_kurus, teblig_tarihi, CAST(akdi_oran AS float8)';

  static FaizTablosu _faizTablosu(List<Object?> r) => switch (r[9]) {
        'avans' => FaizTablosu.avans,
        'akdi' => FaizTablosu.sabit((r[16] as num?)?.toDouble() ?? 0),
        _ => FaizTablosu.yasal,
      };

  static IcraDosyasi _icraSatiri(List<Object?> r, List<Tahsilat> tahsilatlar) => IcraDosyasi(
        id: r[0]! as String,
        dosyaId: r[1]! as String,
        icraDairesi: r[2]! as String,
        esasNo: r[3] as String?,
        borclu: r[4]! as String,
        talep: TakipTalebi(
          tur: TakipTuru.values.byName(r[5]! as String),
          asilAlacak: Para.kurus(r[6]! as int),
          temerrutTarihi: tarihDegeri(r[7]),
          takipTarihi: tarihDegeri(r[8]),
          takipOncesiMasraf: Para.kurus(r[12]! as int),
          islemisFaizElle: r[14] == null ? null : Para.kurus(r[14]! as int),
        ),
        durum: IcraDurumu.values.any((d) => d.name == r[10]) ? IcraDurumu.values.byName(r[10]! as String) : IcraDurumu.takipAcildi,
        tebligTarihi: r[15] == null ? null : tarihDegeri(r[15]),
        vekaletUcreti: Para.kurus(r[11]! as int),
        takipSonrasiMasraf: Para.kurus(r[13]! as int),
        tahsilatlar: tahsilatlar,
      );

  static Map<String, Object?> _kapakJson(KapakHesabi h) => {
        'hesapTarihi': h.hesapTarihi.isoBicim,
        'asilAlacakKurus': h.asilAlacak.kurus,
        'islemisFaizKurus': h.islemisFaiz.kurus,
        'takipSonrasiFaizKurus': h.takipSonrasiFaiz.kurus,
        'masraflarKurus': h.masraflar.kurus,
        'vekaletUcretiKurus': h.vekaletUcreti.kurus,
        'tahsilEdilenKurus': h.tahsilEdilen.kurus,
        'kalanAnaparaKurus': h.kalanAnapara.kurus,
        'kalanFaizKurus': h.kalanFaiz.kurus,
        'kalanMasrafKurus': h.kalanMasraf.kurus,
        'kalanBorcKurus': h.kalanBorc.kurus,
        'tahsilHarciKurus': h.tahsilHarci.kurus,
        'pesinHarcMahsubuKurus': h.pesinHarcMahsubu.kurus,
        'cezaeviHarciKurus': h.cezaeviHarci.kurus,
        'borcluyaToplamKurus': h.borcluyaToplam.kurus,
        'mahsuplar': [
          for (final m in h.mahsuplar)
            {
              'tahsilatId': m.tahsilat.id,
              'masrafaKurus': m.masrafa.kurus,
              'faizeKurus': m.faize.kurus,
              'anaparayaKurus': m.anaparaya.kurus,
              'fazlaKurus': m.fazla.kurus,
            },
        ],
        'uyarilar': h.uyarilar,
      };

  /// İcra dosyaları, takip talebi alanları ve tahsilatlarıyla (istemci kapak hesabını çekirdekle yerelde de gösterebilir).
  Future<Response> _icraListe(Request istek) async {
    final k = kimlik(istek);
    final (dosyalar, tahsilatlar) = await vt.kiraciIcin(k, (tx) async {
      final d = await tx.execute('SELECT $_icraSutunlari FROM hukuk.icra_dosyasi ORDER BY takip_tarihi DESC');
      final t = await tx.execute('SELECT id::text, icra_id::text, tarih, tutar_kurus, aciklama FROM hukuk.icra_tahsilat '
          'ORDER BY tarih');
      return (d, t);
    });
    final tahsilatMap = <String, List<Map<String, Object?>>>{};
    for (final t in tahsilatlar) {
      (tahsilatMap[t[1]! as String] ??= []).add(
          {'id': t[0], 'tarih': tarihMetni(t[2]), 'tutarKurus': t[3], 'aciklama': t[4]});
    }
    return jsonYanit([
      for (final r in dosyalar)
        {
          'id': r[0],
          'dosyaId': r[1],
          'icraDairesi': r[2],
          'esasNo': r[3],
          'borclu': r[4],
          'takipTuru': r[5],
          'asilKurus': r[6],
          'temerrut': tarihMetni(r[7]),
          'takipTarihi': tarihMetni(r[8]),
          'faizTuru': r[9],
          'durum': r[10],
          'vekaletKurus': r[11],
          'takipOncesiMasrafKurus': r[12],
          'takipSonrasiMasrafKurus': r[13],
          'islemisFaizElleKurus': r[14],
          'tebligTarihi': r[15] == null ? null : tarihMetni(r[15]),
          'akdiOran': r[16],
          'tahsilatlar': tahsilatMap[r[0]] ?? const [],
        },
    ]);
  }

  Future<Response> _icraEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'takipTuru', TakipTuru.values);
    final faiz = enumAlani(j, 'faizTuru', FaizTuru.values);
    final asil = kurusAlani(j, 'asilKurus');
    final temerrut = tarihAlani(j, 'temerrut');
    final takip = tarihAlani(j, 'takipTarihi', varsayilan: Tarih.from(DateTime.now()));
    if (temerrut.isAfter(takip)) throw const ApiHatasi(400, 'Temerrüt tarihi takip tarihinden sonra olamaz.');
    final akdiOran = j['akdiOran'];
    if (faiz == FaizTuru.akdi && (akdiOran is! num || akdiOran < 0)) {
      throw const ApiHatasi(400, 'Sözleşmesel faizde "akdiOran" (yıllık %) zorunludur.', kod: 'eksik_alan');
    }
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.icra_dosyasi (kiraci_id, dosya_id, icra_dairesi, esas_no, borclu, takip_turu, asil_kurus, '
            'temerrut, takip_tarihi, faiz_turu, akdi_oran, vekalet_kurus, takip_oncesi_masraf_kurus) VALUES (CAST(@k AS uuid), '
            'CAST(@d AS uuid), @daire, @esas, @b, @tur, @asil, CAST(@tem AS date), CAST(@tak AS date), @faiz, '
            'CAST(@oran AS numeric), @vek, @om) '
            'RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          'd': zorunluMetin(j, 'dosyaId'),
          'daire': zorunluMetin(j, 'icraDairesi'),
          'esas': j['esasNo'] as String?,
          'b': zorunluMetin(j, 'borclu'),
          'tur': tur.name,
          'asil': asil,
          'tem': temerrut.isoBicim,
          'tak': takip.isoBicim,
          'faiz': faiz.name,
          'oran': faiz == FaizTuru.akdi ? (akdiOran! as num).toDouble() : null,
          'vek': j['vekaletKurus'] is int ? j['vekaletKurus'] as int : 0,
          'om': j['takipOncesiMasrafKurus'] is int ? j['takipOncesiMasrafKurus'] as int : 0,
        },
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'icra', yeni, Para.kurus(asil).bicimli);
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  Future<Response> _icraAyrinti(Request istek, String id) async {
    final k = kimlik(istek);
    final hesapTarihi = istek.url.queryParameters['tarih'] == null
        ? Tarih.from(DateTime.now())
        : tarihAlani(istek.url.queryParameters, 'tarih');
    final (satir, tahsilat) = await vt.kiraciIcin(k, (tx) async {
      final s = await tx.execute(Sql.named('SELECT $_icraSutunlari FROM hukuk.icra_dosyasi WHERE id = CAST(@id AS uuid)'),
          parameters: {'id': id});
      final t = await tx.execute(
        Sql.named('SELECT id::text, tarih, tutar_kurus, aciklama FROM hukuk.icra_tahsilat WHERE icra_id = CAST(@id AS uuid) '
            'ORDER BY tarih'),
        parameters: {'id': id},
      );
      return (s, t);
    });
    if (satir.isEmpty) throw ApiHatasi.bulunamadi;
    final r = satir.first;
    final icra = _icraSatiri(r, [
      for (final t in tahsilat)
        Tahsilat(id: t[0]! as String, tarih: tarihDegeri(t[1]), tutar: Para.kurus(t[2]! as int), aciklama: t[3]! as String),
    ]);
    final tarih = hesapTarihi.isBefore(icra.talep.takipTarihi) ? icra.talep.takipTarihi : hesapTarihi;
    final hesap = icra.hesap(tarih, _faizTablosu(r));
    return jsonYanit({
      'id': icra.id,
      'dosyaId': icra.dosyaId,
      'icraDairesi': icra.icraDairesi,
      'esasNo': icra.esasNo,
      'borclu': icra.borclu,
      'takipTuru': icra.talep.tur.name,
      'faizTuru': r[9],
      'durum': icra.durum.name,
      'hesap': _kapakJson(hesap),
    });
  }

  Future<Response> _icraTahsilat(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tutar = kurusAlani(j, 'tutarKurus');
    final tarih = tarihAlani(j, 'tarih', varsayilan: Tarih.from(DateTime.now()));
    final yeni = await vt.kiraciIcin(k, (tx) async {
      final mevcut = await tx.execute(Sql.named('SELECT 1 FROM hukuk.icra_dosyasi WHERE id = CAST(@id AS uuid)'),
          parameters: {'id': id});
      if (mevcut.isEmpty) throw ApiHatasi.bulunamadi;
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.icra_tahsilat (kiraci_id, icra_id, tarih, tutar_kurus, aciklama) '
            'VALUES (CAST(@k AS uuid), CAST(@id AS uuid), CAST(@t AS date), @tutar, @a) RETURNING id::text'),
        parameters: {'k': k.kiraciId, 'id': id, 't': tarih.isoBicim, 'tutar': tutar, 'a': (j['aciklama'] as String?) ?? ''},
      );
      final tId = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'icra_tahsilat', id, Para.kurus(tutar).bicimli);
      return tId;
    });
    return jsonYanit({'id': yeni}, durum: 201);
  }

  Future<Response> _icraDurum(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final durum = enumAlani(j, 'durum', IcraDurumu.values);
    final teblig = j['tebligTarihi'] == null ? null : tarihAlani(j, 'tebligTarihi');
    final n = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('UPDATE hukuk.icra_dosyasi SET durum = @d, teblig_tarihi = coalesce(CAST(@t AS date), teblig_tarihi) '
            'WHERE id = CAST(@id AS uuid)'),
        parameters: {'d': durum.name, 't': teblig?.isoBicim, 'id': id},
      );
      if (rs.affectedRows == 1) await DosyaApi.denetim(tx, k, 'degisiklik', 'icra', id, 'Durum: ${durum.ad}');
      return rs.affectedRows;
    });
    if (n == 0) throw ApiHatasi.bulunamadi;
    return jsonYanit({'durum': durum.name});
  }

  /// Toplu takip: satırlar (borçlu; kimlik/vergi no; alacak; temerrüt GG.AA.YYYY) sunucuda yeniden doğrulanır.
  /// Hatalı satır varsa hiçbir takip açılmaz (hepsi ya da hiçbiri); her satır için icra dosyası, müvekkil tarafı ve
  /// takip tek işlemde açılır. En fazla 500 satır.
  Future<Response> _topluTakip(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final tur = enumAlani(j, 'takipTuru', TakipTuru.values);
    final faiz = j['faizTuru'] == null ? FaizTuru.yasal : enumAlani(j, 'faizTuru', FaizTuru.values);
    if (faiz == FaizTuru.akdi) {
      throw const ApiHatasi(400, 'Toplu takipte sözleşmesel faiz desteklenmez; takipleri tek tek açın.', kod: 'gecersiz_istek');
    }
    final muvekkilId = zorunluMetin(j, 'muvekkilId');
    final daire = zorunluMetin(j, 'icraDairesi');
    final hamSatirlar = [
      for (final r in (j['satirlar'] as List? ?? const []))
        if (r is List) [for (final x in r) '$x'] else throw const ApiHatasi(400, 'Satırlar liste olmalı.', kod: 'gecersiz_istek'),
    ];
    if (hamSatirlar.isEmpty) throw const ApiHatasi(400, 'En az bir satır gerekli.', kod: 'eksik_alan');
    if (hamSatirlar.length > 500) throw const ApiHatasi(400, 'Tek seferde en fazla 500 takip açılabilir.', kod: 'gecersiz_istek');
    final bugun = Tarih.from(DateTime.now());
    final satirlar = TopluTakip.dogrula(hamSatirlar, bugun,
        kimlikGecerli: (no) => no.length == 11 ? Dogrulayicilar.tcknGecerli(no) : Dogrulayicilar.vknGecerli(no));
    final hatali = satirlar.where((s) => !s.gecerli).toList();
    if (hatali.isNotEmpty) {
      return jsonYanit({
        'hata': 'satir_hatasi',
        'mesaj': '${hatali.length} satırda hata var; hiçbir takip açılmadı.',
        'satirlar': [for (final s in hatali) {'satir': s.satir, 'hatalar': s.hatalar}],
      }, durum: 400);
    }
    final sorumlu = (j['sorumlu'] as String?) ?? k.kullaniciId;
    final acilan = await vt.kiraciIcin(k, (tx) async {
      final m = await tx.execute(Sql.named('SELECT ad FROM hukuk.kisi WHERE id = CAST(@m AS uuid)'), parameters: {'m': muvekkilId});
      if (m.isEmpty) throw const ApiHatasi(400, 'Müvekkil bulunamadı.', kod: 'gecersiz_istek');
      final muvekkilAdi = m.first[0]! as String;
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('dosya_no' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      final idler = <String>[];
      for (final s in satirlar) {
        final no = await tx.execute(Sql.named('SELECT hukuk.sonraki_dosya_no(@y)'), parameters: {'y': bugun.yil});
        final d = await tx.execute(
          Sql.named("INSERT INTO hukuk.dosya (kiraci_id, ic_no, tur, baslik, sorumlu) VALUES (CAST(@k AS uuid), @n, 'icra', "
              '@b, CAST(@s AS uuid)) RETURNING id::text'),
          parameters: {'k': k.kiraciId, 'n': no.first[0], 'b': '$muvekkilAdi - ${s.borclu}', 's': sorumlu},
        );
        final dosyaId = d.first[0]! as String;
        await tx.execute(
          Sql.named("INSERT INTO hukuk.dosya_taraf (kiraci_id, dosya_id, kisi_id, sifat) VALUES (CAST(@k AS uuid), "
              "CAST(@d AS uuid), CAST(@m AS uuid), 'muvekkil')"),
          parameters: {'k': k.kiraciId, 'd': dosyaId, 'm': muvekkilId},
        );
        final i = await tx.execute(
          Sql.named('INSERT INTO hukuk.icra_dosyasi (kiraci_id, dosya_id, icra_dairesi, borclu, takip_turu, asil_kurus, temerrut, '
              'takip_tarihi, faiz_turu) VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @daire, @b, @t, @a, CAST(@tem AS date), '
              'CAST(@tak AS date), @f) RETURNING id::text'),
          parameters: {
            'k': k.kiraciId,
            'd': dosyaId,
            'daire': daire,
            'b': s.borclu,
            't': tur.name,
            'a': s.alacak!.kurus,
            'tem': s.temerrut!.isoBicim,
            'tak': bugun.isoBicim,
            'f': faiz.name,
          },
        );
        idler.add(i.first[0]! as String);
      }
      await DosyaApi.denetim(tx, k, 'aktarim', 'icra', '-', 'Toplu takip: ${idler.length} dosya · $muvekkilAdi');
      return idler;
    });
    return jsonYanit({'acilan': acilan.length, 'icraIdleri': acilan}, durum: 201);
  }

  /// Dosyanın onaylı ve faturalanabilir zaman kayıtlarını faturalar: kayıtlar "faturalandı" olur (artık değişmez),
  /// müvekkil carisine ücret tahakkuku yazılır. Tutar çekirdek kuralıyla (6 dk'ya yukarı yuvarlama) sunucuda hesaplanır.
  Future<Response> _zamanFaturasi(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final bugun = Tarih.from(DateTime.now());
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final m = await tx.execute(
        Sql.named("SELECT kisi_id::text FROM hukuk.dosya_taraf WHERE dosya_id = CAST(@d AS uuid) AND sifat = 'muvekkil' LIMIT 1"),
        parameters: {'d': dosyaId},
      );
      if (m.isEmpty) throw const ApiHatasi(409, 'Dosyada müvekkil kaydı yok.', kod: 'kural');
      await tx.execute(Sql.named("SELECT pg_advisory_xact_lock(hashtextextended('zaman_fatura' || @k, 0))"),
          parameters: {'k': k.kiraciId});
      final rs = await tx.execute(
        Sql.named("SELECT id::text, kullanici_id::text, tarih, dakika, aciklama, saatlik_kurus FROM hukuk.zaman_kaydi "
            "WHERE dosya_id = CAST(@d AS uuid) AND durum = 'onaylandi' AND faturalanabilir ORDER BY tarih FOR UPDATE"),
        parameters: {'d': dosyaId},
      );
      if (rs.isEmpty) throw const ApiHatasi(409, 'Faturalanacak onaylı kayıt yok.', kod: 'kural');
      var toplam = Para.sifir;
      var dakika = 0;
      for (final r in rs) {
        final z = ZamanKaydi(
          id: r[0]! as String,
          kullanici: r[1]! as String,
          dosyaId: dosyaId,
          tarih: tarihDegeri(r[2]),
          dakika: r[3]! as int,
          aciklama: r[4]! as String,
          saatlikUcret: Para.kurus(r[5]! as int),
          durum: ZamanDurumu.onaylandi,
        );
        toplam = toplam + z.tutar();
        dakika += z.faturaDakikasi();
      }
      final no = (await tx.execute(Sql.named('SELECT hukuk.sonraki_zaman_fatura_no(@y)'), parameters: {'y': bugun.yil}))
          .first[0]! as String;
      await tx.execute(
        Sql.named("UPDATE hukuk.zaman_kaydi SET durum = 'faturalandi', fatura_no = @n WHERE id = ANY(CAST(@i AS uuid[]))"),
        parameters: {'n': no, 'i': '{${[for (final r in rs) r[0]].join(',')}}'},
      );
      await tx.execute(
        Sql.named("INSERT INTO hukuk.cari_hareket (kiraci_id, muvekkil_id, dosya_id, tur, tutar_kurus, tarih, aciklama, belge_no) "
            "VALUES (CAST(@k AS uuid), CAST(@m AS uuid), CAST(@d AS uuid), 'ucretTahakkuku', @t, CAST(@g AS date), @a, @n)"),
        parameters: {
          'k': k.kiraciId,
          'm': m.first[0],
          'd': dosyaId,
          't': toplam.kurus,
          'g': bugun.isoBicim,
          'a': 'Zaman kaydı faturası $no (${rs.length} kalem)',
          'n': no,
        },
      );
      await DosyaApi.denetim(tx, k, 'olusturma', 'zaman_fatura', no, '${toplam.bicimli} · ${rs.length} kalem');
      return {'faturaNo': no, 'kalem': rs.length, 'dakika': dakika, 'toplamKurus': toplam.kurus};
    });
    return jsonYanit(sonuc, durum: 201);
  }
}
