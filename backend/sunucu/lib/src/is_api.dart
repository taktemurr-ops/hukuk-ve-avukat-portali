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
    ..get('/kisiler/<id>/cari', _cari)
    ..post('/cari', _cariEkle)
    ..get('/emanet', _emanet)
    ..post('/emanet', _emanetEkle)
    ..get('/zaman', _zaman)
    ..post('/zaman', _zamanEkle)
    ..post('/zaman/<id>/onayla', _zamanOnayla)
    ..get('/icra', _icraListe)
    ..post('/icra', _icraEkle)
    ..get('/icra/<id>', _icraAyrinti)
    ..post('/icra/<id>/tahsilat', _icraTahsilat);

  // ---------------------------------------------------------------------------
  // Kişiler
  // ---------------------------------------------------------------------------

  Future<Response> _kisiler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k, (tx) => tx.execute('SELECT id::text, tur, ad, kimlik_no, eposta FROM hukuk.kisi ORDER BY ad LIMIT 2000'));
    return jsonYanit([
      for (final r in rs) {'id': r[0], 'tur': r[1], 'ad': r[2], 'kimlikNo': r[3], 'eposta': r[4]},
    ]);
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
        Sql.named('INSERT INTO hukuk.kisi (kiraci_id, tur, ad, kimlik_no, eposta) '
            'VALUES (CAST(@k AS uuid), @t, @a, @n, @e) RETURNING id::text'),
        parameters: {
          'k': k.kiraciId,
          't': tur.name,
          'a': ad,
          'n': no == null || no.isEmpty ? null : no,
          'e': eposta == null || eposta.isEmpty ? null : eposta,
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

  Future<Response> _emanet(Request istek) async {
    final k = kimlik(istek);
    final m = istek.url.queryParameters['muvekkil'];
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named("SELECT muvekkil_id::text, dosya_id::text, sum(CASE WHEN tur = 'giris' THEN tutar_kurus "
                  'ELSE -tutar_kurus END)::bigint, min(tarih) FILTER (WHERE tur = \'giris\') '
                  'FROM hukuk.emanet_hareket WHERE (CAST(@m AS uuid) IS NULL OR muvekkil_id = CAST(@m AS uuid)) '
                  'GROUP BY muvekkil_id, dosya_id ORDER BY 3 DESC'),
              parameters: {'m': m},
            ));
    return jsonYanit([
      for (final r in rs) {'muvekkilId': r[0], 'dosyaId': r[1], 'bakiyeKurus': r[2], 'ilkGiris': tarihMetni(r[3])},
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

  Future<Response> _icraListe(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT $_icraSutunlari FROM hukuk.icra_dosyasi ORDER BY takip_tarihi DESC'));
    return jsonYanit([
      for (final r in rs)
        {'id': r[0], 'dosyaId': r[1], 'icraDairesi': r[2], 'esasNo': r[3], 'borclu': r[4], 'takipTuru': r[5],
          'asilKurus': r[6], 'takipTarihi': tarihMetni(r[8]), 'durum': r[10]},
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
}
