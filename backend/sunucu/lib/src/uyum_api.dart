import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'dosya_api.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Uyum uçları: ihbar (açık form ve takip kodu dahil), iç soruşturma, kişisel veri ihlali.
///
/// Gizlilik veritabanında zorlanır: ihbarı ve soruşturmayı yalnızca soruşturmanın sorumlusu ve ekibi (soruşturma
/// açılmadan önce hukuk direktörü / uyum sorumlusu) görür; ihbar edilen kişi ekipte yer alamaz.
class UyumApi {
  UyumApi(this.vt);

  final Veritabani vt;

  Router get router => Router()
    ..post('/acik/ihbar/<kiraciId>', _acikIhbar)
    ..post('/acik/ihbar-durumu', _acikDurum)
    ..get('/ihbarlar', _ihbarlar)
    ..post('/ihbarlar', _ihbarEkle)
    ..post('/ihbarlar/<id>/sorusturma', _sorusturmaAc)
    ..post('/sorusturmalar/<id>/ekip', _ekipEkle)
    ..post('/sorusturmalar/<id>/not', _notEkle)
    ..post('/sorusturmalar/<id>/geri-bildirim', _geriBildirim)
    ..post('/sorusturmalar/<id>/durum', _sorusturmaDurum)
    ..get('/veri-ihlalleri', _ihlaller)
    ..post('/veri-ihlalleri', _ihlalEkle)
    ..post('/veri-ihlalleri/<id>/bildirim', _ihlalBildirim);

  static String _kodOzeti(String kod) => sha256.convert(utf8.encode(kod.trim().toUpperCase())).toString();

  static String _aciklama(Map<String, dynamic> j) {
    final a = zorunluMetin(j, 'aciklama');
    if (a.length < 20) throw const ApiHatasi(400, 'İhbarı en az 20 karakterle açıklayın.', kod: 'gecersiz_istek');
    if (a.length > 20000) throw const ApiHatasi(413, 'Açıklama çok uzun.');
    return a;
  }

  // ---------------------------------------------------------------------------
  // Açık (oturumsuz) ihbar formu
  // ---------------------------------------------------------------------------

  /// Takip kodu yalnızca bu yanıtta gösterilir; sunucuda özeti saklanır.
  Future<Response> _acikIhbar(Request istek, String kiraciId) async {
    final j = await jsonGovde(istek);
    final kategori = enumAlani(j, 'kategori', IhbarKategorisi.values);
    final aciklama = _aciklama(j);
    final iletisim = (j['iletisim'] as String?)?.trim();
    final kod = Ihbar.takipKoduUret();
    await vt.genel((tx) => tx.execute(
          Sql.named('SELECT hukuk.ihbar_formu(CAST(@k AS uuid), @kat, @a, @i, @o)'),
          parameters: {
            'k': kiraciId,
            'kat': kategori.name,
            'a': aciklama,
            'i': iletisim == null || iletisim.isEmpty ? null : iletisim,
            'o': _kodOzeti(kod),
          },
        ));
    return jsonYanit({
      'takipKodu': kod,
      'bilgi': 'Bu kodu saklayın; ihbarınızın durumunu yalnızca bu kodla öğrenebilirsiniz. Kod tekrar gösterilmez.',
    }, durum: 201);
  }

  Future<Response> _acikDurum(Request istek) async {
    final j = await jsonGovde(istek);
    final kod = zorunluMetin(j, 'takipKodu');
    final rs = await vt.genel((tx) => tx.execute(Sql.named('SELECT durum, geri_bildirim, alinma FROM hukuk.ihbar_durumu(@o)'),
        parameters: {'o': _kodOzeti(kod)}));
    if (rs.isEmpty) throw const ApiHatasi(404, 'Bu takip koduyla kayıt bulunamadı.', kod: 'bulunamadi');
    final r = rs.first;
    final durum = r[0]! as String;
    final ad = durum == 'alindi'
        ? 'Alındı, ön değerlendirme bekliyor'
        : SorusturmaDurumu.values.where((d) => d.name == durum).map((d) => d.ad).firstOrNull ?? durum;
    return jsonYanit({'durum': durum, 'durumAdi': ad, 'geriBildirimVerildi': r[1], 'alinma': (r[2]! as DateTime).toIso8601String()});
  }

  // ---------------------------------------------------------------------------
  // İhbar ve soruşturma (oturumlu)
  // ---------------------------------------------------------------------------

  Future<Response> _ihbarEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final kategori = enumAlani(j, 'kategori', IhbarKategorisi.values);
    final kanal = j['kanal'] == null ? IhbarKanali.web : enumAlani(j, 'kanal', IhbarKanali.values);
    final aciklama = _aciklama(j);
    final iletisim = (j['iletisim'] as String?)?.trim();
    final ilgili = [for (final x in (j['ilgiliKisiler'] as List? ?? const [])) '$x'];
    final kod = Ihbar.takipKoduUret();
    await vt.kiraciIcin(k, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO hukuk.ihbar (kiraci_id, takip_kodu_ozet, kanal, kategori, aciklama, anonim, iletisim, '
            'ilgili_kisiler, sirket_id) VALUES (CAST(@k AS uuid), @o, @kn, @kat, @a, @an, @i, CAST(@il AS uuid[]), '
            'CAST(@s AS uuid))'),
        parameters: {
          'k': k.kiraciId,
          'o': _kodOzeti(kod),
          'kn': kanal.name,
          'kat': kategori.name,
          'a': aciklama,
          'an': iletisim == null || iletisim.isEmpty,
          'i': iletisim == null || iletisim.isEmpty ? null : iletisim,
          'il': '{${ilgili.join(',')}}',
          's': j['sirketId'] as String?,
        },
      );
      // Kaydeden, ihbarı sonradan göremeyebilir; denetim kaydına içerik yazılmaz.
      await DosyaApi.denetim(tx, k, 'olusturma', 'ihbar', '', kategori.ad);
    });
    return jsonYanit({'takipKodu': kod}, durum: 201);
  }

  static const _sutunlar = 'i.id::text, i.zaman, i.kanal, i.kategori, i.aciklama, i.anonim, i.iletisim, '
      'CAST(i.ilgili_kisiler AS text[]), i.sirket_id::text, s.id::text, s.sorumlu::text, CAST(s.ekip AS text[]), s.durum, '
      's.sonuc, s.sonuc_ozeti, s.acilis, s.ilk_geri_bildirim';

  Future<Response> _ihbarlar(Request istek) async {
    final k = kimlik(istek);
    final (ihbarlar, notlar) = await vt.kiraciIcin(k, (tx) async {
      final i = await tx.execute('SELECT $_sutunlar FROM hukuk.ihbar i LEFT JOIN hukuk.sorusturma s ON s.ihbar_id = i.id '
          'ORDER BY i.zaman DESC');
      final n = await tx.execute('SELECT sorusturma_id::text, kullanici_id::text, metin, zaman FROM hukuk.sorusturma_notu '
          'ORDER BY id');
      return (i, n);
    });
    final notMap = <String, List<Map<String, Object?>>>{};
    for (final n in notlar) {
      (notMap[n[0]! as String] ??= [])
          .add({'kullanici': n[1], 'metin': n[2], 'zaman': (n[3]! as DateTime).toIso8601String()});
    }
    final simdi = DateTime.now();
    return jsonYanit([
      for (final r in ihbarlar)
        {
          'id': r[0],
          'zaman': (r[1]! as DateTime).toIso8601String(),
          'kanal': r[2],
          'kategori': r[3],
          'aciklama': r[4],
          'anonim': r[5],
          'iletisim': r[6],
          'ilgiliKisiler': r[7],
          'sirketId': r[8],
          'sorusturma': r[9] == null
              ? null
              : () {
                  final s = _sorusturma(r);
                  return {
                    'id': s.id,
                    'sorumlu': s.sorumlu,
                    'ekip': s.ekip.toList(),
                    'durum': s.durum.name,
                    'sonuc': s.sonuc?.name,
                    'sonucOzeti': s.sonucOzeti,
                    'acilis': s.acilis.toIso8601String(),
                    'ilkGeriBildirim': s.ilkGeriBildirim?.toIso8601String(),
                    'geriBildirimSonu': s.geriBildirimSonu.toIso8601String(),
                    'sonucSonu': s.sonucSonu.toIso8601String(),
                    'geriBildirimGecikti': s.geriBildirimGecikti(simdi),
                    'sonucGecikti': s.sonucGecikti(simdi),
                    'notlar': notMap[s.id] ?? const [],
                  };
                }(),
        },
    ]);
  }

  /// Satırdan çekirdek nesnesi (takip kodu sunucuda tutulmadığı için boştur).
  static Sorusturma _sorusturma(List<Object?> r) {
    final ihbar = Ihbar(
      id: r[0]! as String,
      takipKodu: '',
      zaman: r[1]! as DateTime,
      kanal: IhbarKanali.values.firstWhere((x) => x.name == r[2], orElse: () => IhbarKanali.web),
      kategori: IhbarKategorisi.values.firstWhere((x) => x.name == r[3], orElse: () => IhbarKategorisi.diger),
      aciklama: r[4]! as String,
      anonim: r[5]! as bool,
      ihbarciIletisim: r[6] as String?,
      ilgiliKisiler: {...(r[7] as List? ?? const []).map((x) => '$x')},
      sirketId: r[8] as String?,
    );
    final s = Sorusturma(id: r[9]! as String, ihbar: ihbar, sorumlu: r[10]! as String, acilis: r[15]! as DateTime)
      ..durum = SorusturmaDurumu.values.byName(r[12]! as String)
      ..sonuc = r[13] == null ? null : SorusturmaSonucu.values.byName(r[13]! as String)
      ..sonucOzeti = r[14] as String?
      ..ilkGeriBildirim = r[16] as DateTime?;
    s.ekip.addAll((r[11] as List? ?? const []).map((x) => '$x'));
    return s;
  }

  Future<Sorusturma> _sorusturmaOku(TxSession tx, String sorusturmaId) async {
    final rs = await tx.execute(
      Sql.named('SELECT $_sutunlar FROM hukuk.sorusturma s JOIN hukuk.ihbar i ON i.id = s.ihbar_id '
          'WHERE s.id = CAST(@id AS uuid) FOR UPDATE OF s'),
      parameters: {'id': sorusturmaId},
    );
    if (rs.isEmpty) throw ApiHatasi.bulunamadi;
    return _sorusturma(rs.first);
  }

  Future<Response> _sorusturmaAc(Request istek, String ihbarId) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final sorumlu = (j['sorumlu'] as String?) ?? k.kullaniciId;
    final id = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.sorusturma (kiraci_id, ihbar_id, sorumlu) '
            'VALUES (CAST(@k AS uuid), CAST(@i AS uuid), CAST(@s AS uuid)) RETURNING id::text'),
        parameters: {'k': k.kiraciId, 'i': ihbarId, 's': sorumlu},
      );
      final yeni = rs.first[0]! as String;
      await DosyaApi.denetim(tx, k, 'olusturma', 'sorusturma', yeni, 'Soruşturma açıldı');
      return yeni;
    });
    return jsonYanit({'id': id}, durum: 201);
  }

  /// Çekirdek kuralıyla işlemi uygular, ardından satırı yazar.
  Future<void> _sorusturmaIslemi(KimlikBaglami k, String id, String aciklama, void Function(Sorusturma s) islem) =>
      vt.kiraciIcin(k, (tx) async {
        final s = await _sorusturmaOku(tx, id);
        try {
          islem(s);
        } on StateError catch (e) {
          throw ApiHatasi(409, e.message, kod: 'kural');
        } on ArgumentError catch (e) {
          throw ApiHatasi(400, '${e.message}', kod: 'gecersiz_istek');
        }
        await tx.execute(
          Sql.named('UPDATE hukuk.sorusturma SET ekip = CAST(@e AS uuid[]), durum = @d, sonuc = @so, sonuc_ozeti = @oz, '
              'ilk_geri_bildirim = @g WHERE id = CAST(@id AS uuid)'),
          parameters: {
            'e': '{${s.ekip.join(',')}}',
            'd': s.durum.name,
            'so': s.sonuc?.name,
            'oz': s.sonucOzeti,
            'g': s.ilkGeriBildirim,
            'id': id,
          },
        );
        await DosyaApi.denetim(tx, k, 'degisiklik', 'sorusturma', id, aciklama);
      });

  Future<Response> _ekipEkle(Request istek, String id) async {
    final k = kimlik(istek);
    final kisi = zorunluMetin(await jsonGovde(istek), 'kullaniciId');
    await _sorusturmaIslemi(k, id, 'Ekibe eklendi', (s) => s.ekipEkle(kisi, ekleyen: k.kullaniciId));
    return jsonYanit({'eklendi': kisi});
  }

  Future<Response> _geriBildirim(Request istek, String id) async {
    final k = kimlik(istek);
    await _sorusturmaIslemi(k, id, 'İhbarcıya ilk geri bildirim verildi', (s) => s.geriBildirimVer(k.kullaniciId, DateTime.now()));
    return jsonYanit({'durum': 'kaydedildi'});
  }

  Future<Response> _sorusturmaDurum(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final islem = zorunluMetin(j, 'islem');
    final gerekce = (j['gerekce'] as String?) ?? '';
    await _sorusturmaIslemi(k, id, 'İşlem: $islem', (s) {
      switch (islem) {
        case 'sorusturmayaAl':
          s.sorusturmayaAl(k.kullaniciId);
        case 'raporlamayaGec':
          s.raporlamayaGec(k.kullaniciId);
        case 'reddet':
          s.reddet(k.kullaniciId, gerekce);
        case 'kapat':
          s.kapat(k.kullaniciId, enumAlani(j, 'sonuc', SorusturmaSonucu.values), gerekce);
        default:
          throw const ApiHatasi(400, 'İşlem: sorusturmayaAl, raporlamayaGec, reddet veya kapat.', kod: 'gecersiz_istek');
      }
    });
    return jsonYanit({'islem': islem});
  }

  Future<Response> _notEkle(Request istek, String id) async {
    final k = kimlik(istek);
    final metin = zorunluMetin(await jsonGovde(istek), 'metin');
    await vt.kiraciIcin(k, (tx) async {
      // Erişim RLS ile de denetlenir; görmediği soruşturmaya not yazan 404/403 alır.
      final s = await _sorusturmaOku(tx, id);
      if (!s.erisebilir(k.kullaniciId)) throw const ApiHatasi(403, 'Bu soruşturmaya erişim yetkiniz yok.', kod: 'yasak');
      await tx.execute(
        Sql.named('INSERT INTO hukuk.sorusturma_notu (kiraci_id, sorusturma_id, metin) VALUES (CAST(@k AS uuid), '
            'CAST(@s AS uuid), @m)'),
        parameters: {'k': k.kiraciId, 's': id, 'm': metin},
      );
    });
    return jsonYanit({'durum': 'eklendi'}, durum: 201);
  }

  // ---------------------------------------------------------------------------
  // Kişisel veri ihlali
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _ihlalJson(List<Object?> r, DateTime simdi) {
    final v = VeriIhlali(
      id: r[0]! as String,
      ogrenilme: r[1]! as DateTime,
      aciklama: r[2]! as String,
      etkilenenKisiSayisi: r[3] as int?,
    )
      ..kurulaBildirim = r[4] as DateTime?
      ..ilgililereBildirim = r[5] as DateTime?;
    return {
      'id': v.id,
      'ogrenilme': v.ogrenilme.toIso8601String(),
      'aciklama': v.aciklama,
      'etkilenenKisiSayisi': v.etkilenenKisiSayisi,
      'kurulaBildirim': v.kurulaBildirim?.toIso8601String(),
      'ilgililereBildirim': v.ilgililereBildirim?.toIso8601String(),
      'kurulSonZaman': v.kurulSonZaman.toIso8601String(),
      'kalanDakika': v.kalan(simdi).inMinutes,
      'gecikti': v.gecikti(simdi),
    };
  }

  static const _ihlalSutunlari = 'id::text, ogrenilme, aciklama, etkilenen_sayi, kurula_bildirim, ilgililere_bildirim';

  Future<Response> _ihlaller(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT $_ihlalSutunlari FROM hukuk.veri_ihlali ORDER BY ogrenilme DESC'));
    final simdi = DateTime.now();
    return jsonYanit([for (final r in rs) _ihlalJson(r, simdi)]);
  }

  static DateTime _zaman(Map<String, dynamic> j, String alan, {DateTime? varsayilan}) {
    final v = j[alan];
    if (v == null && varsayilan != null) return varsayilan;
    final t = v is String ? DateTime.tryParse(v) : null;
    if (t == null) throw ApiHatasi(400, '"$alan" ISO 8601 zaman olmalı (ör. 2026-11-25T14:30:00+03:00).', kod: 'gecersiz_istek');
    return t;
  }

  Future<Response> _ihlalEkle(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final ogrenilme = _zaman(j, 'ogrenilme', varsayilan: DateTime.now());
    final etkilenen = j['etkilenenKisiSayisi'];
    if (etkilenen != null && (etkilenen is! int || etkilenen < 0)) {
      throw const ApiHatasi(400, '"etkilenenKisiSayisi" sıfır veya pozitif tam sayı olmalı.', kod: 'gecersiz_istek');
    }
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.veri_ihlali (kiraci_id, ogrenilme, aciklama, etkilenen_sayi) '
            'VALUES (CAST(@k AS uuid), @o, @a, @e) RETURNING $_ihlalSutunlari'),
        parameters: {'k': k.kiraciId, 'o': ogrenilme.toUtc(), 'a': zorunluMetin(j, 'aciklama'), 'e': etkilenen as int?},
      );
      await DosyaApi.denetim(tx, k, 'olusturma', 'veri_ihlali', rs.first[0]! as String, 'Veri ihlali kaydı');
      return _ihlalJson(rs.first, DateTime.now());
    });
    return jsonYanit(sonuc, durum: 201);
  }

  /// Kurul'a veya ilgili kişilere bildirim zamanı (bir kez yazılır).
  Future<Response> _ihlalBildirim(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final hedef = zorunluMetin(j, 'hedef');
    if (hedef != 'kurul' && hedef != 'ilgililer') {
      throw const ApiHatasi(400, '"hedef": kurul veya ilgililer.', kod: 'gecersiz_istek');
    }
    final zaman = _zaman(j, 'zaman', varsayilan: DateTime.now());
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named(hedef == 'kurul'
            ? 'UPDATE hukuk.veri_ihlali SET kurula_bildirim = @z WHERE id = CAST(@id AS uuid) AND kurula_bildirim IS NULL '
                'RETURNING $_ihlalSutunlari'
            : 'UPDATE hukuk.veri_ihlali SET ilgililere_bildirim = @z WHERE id = CAST(@id AS uuid) '
                'AND ilgililere_bildirim IS NULL RETURNING $_ihlalSutunlari'),
        parameters: {'z': zaman.toUtc(), 'id': id},
      );
      if (rs.isEmpty) throw const ApiHatasi(404, 'Kayıt bulunamadı veya bu bildirim zaten kaydedilmiş.', kod: 'bulunamadi');
      await DosyaApi.denetim(tx, k, 'degisiklik', 'veri_ihlali', id, hedef == 'kurul' ? 'Kurula bildirildi' : 'İlgililere bildirildi');
      return _ihlalJson(rs.first, DateTime.now());
    });
    return jsonYanit(sonuc);
  }
}
