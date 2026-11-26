import 'dart:convert';
import 'dart:typed_data';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'belge_servisi.dart';
import 'dosya_api.dart';
import 'guvenlik.dart';
import 'hata.dart';
import 'kimlik_api.dart';
import 'nesne_deposu.dart';
import 'virus_tarama.dart';
import 'veritabani.dart';

/// Dosyanın ilk baytları, uzantısının söylediği türle uyuşuyor mu? Uyuşmuyorsa hata iletisi döner.
/// (Uzantısı değiştirilmiş çalıştırılabilir dosyaları ve bozuk yüklemeleri ayıklar; virüs taraması ayrıca yapılır.)
String? icerikTuruKontrol(String uzanti, List<int> b) {
  bool basi(List<int> imza, [int kayma = 0]) {
    if (b.length < kayma + imza.length) return false;
    for (var i = 0; i < imza.length; i++) {
      if (b[kayma + i] != imza[i]) return false;
    }
    return true;
  }

  const zip = [0x50, 0x4B, 0x03, 0x04];
  const ole = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  // Çalıştırılabilir dosya imzaları her uzantıda reddedilir (MZ: Windows, ELF, Mach-O).
  if (basi([0x4D, 0x5A]) || basi([0x7F, 0x45, 0x4C, 0x46]) || basi([0xCF, 0xFA, 0xED, 0xFE]) || basi([0xFE, 0xED, 0xFA, 0xCF])) {
    return 'Çalıştırılabilir dosyalar yüklenemez.';
  }
  final uygun = switch (uzanti) {
    'pdf' => basi(utf8.encode('%PDF-')),
    'docx' || 'xlsx' || 'odt' || 'zip' || 'udf' => basi(zip),
    'doc' || 'xls' || 'msg' => basi(ole),
    'png' => basi([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    'jpg' || 'jpeg' => basi([0xFF, 0xD8, 0xFF]),
    'tif' || 'tiff' => basi([0x49, 0x49, 0x2A, 0x00]) || basi([0x4D, 0x4D, 0x00, 0x2A]),
    'heic' => basi(utf8.encode('ftyp'), 4),
    'rtf' => basi(utf8.encode(r'{\rtf')),
    // Metin türleri: NUL baytı içermemeli (ilk 8 KB).
    'txt' || 'eml' => !b.take(8192).contains(0),
    _ => false,
  };
  return uygun ? null : 'Dosya içeriği ".$uzanti" türüyle uyuşmuyor.';
}

/// Belge yükleme, sürüm ve indirme. İçerik nesne deposunda, kayıt ve SHA-256 özeti veritabanında tutulur;
/// belgeye erişim dosyanın görünürlüğüne bağlıdır (RLS) ve her indirme denetim kaydına yazılır.
class BelgeApi {
  BelgeApi(this.vt, this.depo, {this.azamiBoyut = 50 * 1024 * 1024, this.tarayici, this.belgeServisi});

  /// Word üretimi ve metin çıkarma için iç ağdaki belge servisi (yoksa bu özellikler kapalı).
  final BelgeServisi? belgeServisi;

  final Veritabani vt;
  final NesneDeposu depo;
  final int azamiBoyut;

  /// Tanımlıysa her yükleme depoya yazılmadan önce taranır; tarayıcıya ulaşılamazsa yükleme reddedilir.
  final VirusTarayici? tarayici;

  Router get router => Router()
    ..get('/dosyalar/<id>/belgeler', _liste)
    ..post('/dosyalar/<id>/belgeler', _yukle)
    ..post('/dosyalar/<id>/belgeler/word', _wordOlustur)
    ..get('/belgeler/ara', _ara)
    ..post('/raporlar/disa-aktar', _raporDisaAktar)
    ..post('/belgeler/<id>/surumler', _yeniSurum)
    ..get('/belgeler/<id>/surumler/<no>/icerik', _indir);

  Future<Uint8List> _govde(Request istek) async {
    final beyan = int.tryParse(istek.headers['content-length'] ?? '');
    if (beyan != null && beyan > azamiBoyut) {
      throw ApiHatasi(413, 'Dosya ${azamiBoyut ~/ (1024 * 1024)} MB sınırını aşıyor.');
    }
    final b = BytesBuilder(copy: false);
    await for (final parca in istek.read()) {
      b.add(parca);
      if (b.length > azamiBoyut) throw ApiHatasi(413, 'Dosya ${azamiBoyut ~/ (1024 * 1024)} MB sınırını aşıyor.');
    }
    return b.takeBytes();
  }

  /// Dosya adı başlıkta URL kodlamalı gelir (Türkçe karakterler için).
  static String _dosyaAdi(Request istek) {
    final ham = istek.headers['x-dosya-adi'];
    if (ham == null || ham.isEmpty) throw const ApiHatasi(400, '"X-Dosya-Adi" başlığı zorunludur.', kod: 'eksik_alan');
    final ad = basliktanCoz(ham).split(RegExp(r'[/\\]')).last.trim();
    if (ad.isEmpty || ad.length > 255) throw const ApiHatasi(400, 'Dosya adı geçersiz.', kod: 'gecersiz_istek');
    return ad;
  }

  /// Yükleme kontrolleri: uzantı, boyut, içerik imzası, zararlı yazılım taraması; dönen özet SHA-256.
  Future<(String, String)> _kontrol(String dosyaAdi, List<int> icerik) async {
    final hata = yuklemeKontrol(dosyaAdi: dosyaAdi, boyut: icerik.length);
    if (hata != null) throw ApiHatasi(400, hata, kod: 'gecersiz_dosya');
    final uzanti = dosyaAdi.substring(dosyaAdi.lastIndexOf('.') + 1).toLowerCase();
    final turHatasi = icerikTuruKontrol(uzanti, icerik);
    if (turHatasi != null) throw ApiHatasi(400, turHatasi, kod: 'gecersiz_dosya');
    final t = tarayici;
    if (t != null) {
      final VirusTaramaSonucu sonuc;
      try {
        sonuc = await t.tara(icerik);
      } on Object {
        throw const ApiHatasi(503, 'Dosya güvenlik taraması şu anda yapılamıyor; lütfen biraz sonra tekrar deneyin.',
            kod: 'tarama_yok');
      }
      if (!sonuc.temiz) {
        throw const ApiHatasi(422, 'Dosyada zararlı yazılım bulundu; yüklenmedi.', kod: 'zararli_dosya');
      }
    }
    return (uzanti, sha256Ozeti(icerik));
  }

  Future<Response> _liste(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(
              Sql.named('SELECT b.id::text, b.ad, b.tur, b.gizli, s.no, s.sha256, s.boyut, s.dosya_adi, s.yukleyen::text, s.zaman '
                  'FROM hukuk.belge b JOIN hukuk.belge_surum s ON s.belge_id = b.id '
                  'WHERE b.dosya_id = CAST(@d AS uuid) ORDER BY b.ad, s.no'),
              parameters: {'d': dosyaId},
            ));
    final belgeler = <String, Map<String, Object?>>{};
    for (final r in rs) {
      final b = belgeler.putIfAbsent(
          r[0]! as String, () => {'id': r[0], 'ad': r[1], 'tur': r[2], 'gizli': r[3], 'surumler': <Map<String, Object?>>[]});
      (b['surumler']! as List<Map<String, Object?>>).add({
        'no': r[4],
        'sha256': (r[5]! as String).trim(),
        'boyut': r[6],
        'dosyaAdi': r[7],
        'yukleyen': r[8],
        'zaman': (r[9]! as DateTime).toIso8601String(),
      });
    }
    return jsonYanit(belgeler.values.toList());
  }

  /// Gövde: dosyanın ham baytları. Başlıklar: X-Dosya-Adi (URL kodlamalı), X-Belge-Adi (isteğe bağlı), X-Belge-Turu.
  Future<Response> _yukle(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final dosyaAdi = _dosyaAdi(istek);
    final tur = BelgeTuru.values.where((t) => t.name == istek.headers['x-belge-turu']).firstOrNull ?? BelgeTuru.diger;
    final belgeAdi = basliktanCoz(istek.headers['x-belge-adi'] ?? '').trim();
    final icerik = await _govde(istek);
    final (_, ozet) = await _kontrol(dosyaAdi, icerik);
    final sonuc = await _kaydet(k, dosyaId, dosyaAdi, belgeAdi, tur, icerik, ozet);
    return jsonYanit({'id': sonuc, 'no': 1, 'sha256': ozet}, durum: 201);
  }

  /// Belgelerin içinde Türkçe tam metin arama (kök eşleşmesi: "tazminat" → "tazminatı"). Yalnızca görülebilen
  /// dosyaların belgeleri (veritabanı kuralı). Aranan sözcükler denetime yazılmaz (kişisel veri içerebilir).
  Future<Response> _ara(Request istek) async {
    final k = kimlik(istek);
    final q = (istek.url.queryParameters['q'] ?? '').trim();
    if (q.length < 2) throw const ApiHatasi(400, 'En az 2 karakter yazın.', kod: 'gecersiz_istek');
    if (q.length > 200) throw const ApiHatasi(400, 'Arama çok uzun.', kod: 'gecersiz_istek');
    final rs = await vt.kiraciIcin(k, (tx) async {
      final r = await tx.execute(
        Sql.named("SELECT b.id::text, b.ad, b.dosya_id::text, d.ic_no, d.baslik, m.ocr, "
            "ts_headline('turkish', left(m.metin, 200000), websearch_to_tsquery('turkish', @q), "
            "'StartSel=«,StopSel=»,MaxFragments=2,MaxWords=18,MinWords=6,FragmentDelimiter= … ') "
            "FROM hukuk.belge_metni m JOIN hukuk.belge b ON b.id = m.belge_id "
            "LEFT JOIN hukuk.dosya d ON d.id = b.dosya_id "
            "WHERE m.arama @@ websearch_to_tsquery('turkish', @q) "
            "ORDER BY ts_rank(m.arama, websearch_to_tsquery('turkish', @q)) DESC LIMIT 50"),
        parameters: {'q': q},
      );
      await DosyaApi.denetim(tx, k, 'goruntuleme', 'belge_arama', '-', '${r.length} sonuç');
      return r;
    });
    final durum = await vt.kiraciIcin(
        k,
        (tx) => tx.execute("SELECT count(*) FILTER (WHERE m.belge_id IS NULL), count(*) FILTER (WHERE m.durum = 'hata') "
            'FROM hukuk.belge b LEFT JOIN hukuk.belge_metni m ON m.belge_id = b.id'));
    return jsonYanit({
      'sonuclar': [
        for (final r in rs)
          {'belgeId': r[0], 'ad': r[1], 'dosyaId': r[2], 'dosyaNo': r[3], 'dosyaBaslik': r[4], 'ocr': r[5], 'ozet': r[6]},
      ],
      'bekleyen': durum.first[0],
      'okunamayan': durum.first[1],
    });
  }

  /// Rapor tablosunu (istemcide yetkiye göre süzülmüş veriden) Excel ya da PDF olarak döner; dosya saklanmaz,
  /// dışa aktarma denetim kaydına yazılır.
  Future<Response> _raporDisaAktar(Request istek) async {
    final k = kimlik(istek);
    final servis = belgeServisi;
    if (servis == null) throw const ApiHatasi(503, 'Excel/PDF çıktısı bu kurulumda açık değil.', kod: 'hizmet_yok');
    final j = await jsonGovde(istek);
    final baslik = zorunluMetin(j, 'baslik');
    final pdf = j['bicim'] == 'pdf';
    final sayfalar = [for (final s in (j['sayfalar'] as List? ?? const [])) (s as Map).cast<String, Object?>()];
    if (sayfalar.isEmpty) throw const ApiHatasi(400, 'Rapor boş.', kod: 'gecersiz_istek');
    final icerik = await servis.rapor(baslik, sayfalar, pdf: pdf);
    await vt.kiraciIcin(k, (tx) => DosyaApi.denetim(tx, k, 'disaAktarma', 'rapor', baslik, pdf ? 'PDF' : 'Excel'));
    final ad = Uri.encodeComponent('$baslik.${pdf ? 'pdf' : 'xlsx'}');
    return Response.ok(icerik, headers: {
      'content-type': pdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'content-disposition': "attachment; filename*=UTF-8''$ad",
      'cache-control': 'no-store',
    });
  }

  /// Şablondan üretilen metni Word belgesine çevirip dosyaya ilk sürüm olarak kaydeder. Eksik alan varsa reddedilir.
  Future<Response> _wordOlustur(Request istek, String dosyaId) async {
    final k = kimlik(istek);
    final servis = belgeServisi;
    if (servis == null) {
      throw const ApiHatasi(503, 'Word üretimi bu kurulumda açık değil.', kod: 'hizmet_yok');
    }
    final j = await jsonGovde(istek);
    final ad = zorunluMetin(j, 'ad');
    final metin = zorunluMetin(j, 'metin');
    if (ad.length > 150 || metin.length > 500000) throw const ApiHatasi(400, 'Belge çok uzun.', kod: 'gecersiz_istek');
    if (metin.contains('[EKSİK:')) {
      throw const ApiHatasi(400, 'Eksik alanlar doldurulmadan belge kaydedilemez.', kod: 'eksik_alan');
    }
    final tur = BelgeTuru.values.where((t) => t.name == j['tur']).firstOrNull ?? BelgeTuru.diger;
    final pdf = j['bicim'] == 'pdf';
    final (docx, _) = await servis.docx(ad, metin, pdf: pdf);
    final dosyaAdi = '${ad.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')}.${pdf ? 'pdf' : 'docx'}';
    final (_, ozet) = await _kontrol(dosyaAdi, docx);
    final id = await _kaydet(k, dosyaId, dosyaAdi, ad, tur, docx, ozet);
    return jsonYanit({'id': id, 'no': 1, 'sha256': ozet, 'dosyaAdi': dosyaAdi}, durum: 201);
  }

  Future<String> _kaydet(KimlikBaglami k, String dosyaId, String dosyaAdi, String belgeAdi, BelgeTuru tur, List<int> icerik,
      String ozet) async {
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('INSERT INTO hukuk.belge (kiraci_id, dosya_id, ad, tur) VALUES (CAST(@k AS uuid), CAST(@d AS uuid), @a, @t) '
            'RETURNING id::text'),
        parameters: {'k': k.kiraciId, 'd': dosyaId, 'a': belgeAdi.isEmpty ? dosyaAdi : belgeAdi, 't': tur.name},
      );
      final belgeId = rs.first[0]! as String;
      final anahtar = '${k.kiraciId}/$belgeId/1';
      // Önce içerik yazılır, sonra kayıt işlenir: işlem geri alınırsa depoda sahipsiz bir nesne kalabilir
      // (temizlik işi siler), ama kaydı olup içeriği olmayan belge oluşmaz.
      await depo.yaz(anahtar, icerik);
      await tx.execute(
        Sql.named('INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) '
            'VALUES (CAST(@b AS uuid), CAST(@k AS uuid), 1, @o, @s, @da, CAST(@u AS uuid), @an)'),
        parameters: {'b': belgeId, 'k': k.kiraciId, 'o': ozet, 's': icerik.length, 'da': dosyaAdi, 'u': k.kullaniciId, 'an': anahtar},
      );
      await DosyaApi.denetim(tx, k, 'olusturma', 'belge', belgeId, '$dosyaAdi · sha256 $ozet');
      return belgeId;
    });
    return sonuc;
  }

  Future<Response> _yeniSurum(Request istek, String belgeId) async {
    final k = kimlik(istek);
    final dosyaAdi = _dosyaAdi(istek);
    final icerik = await _govde(istek);
    final (_, ozet) = await _kontrol(dosyaAdi, icerik);
    final no = await vt.kiraciIcin(k, (tx) async {
      // Belge görünür mü (dosya RLS'i) ve sıradaki sürüm numarası; aynı belgeye eşzamanlı yüklemeye karşı kilit.
      final b = await tx.execute(Sql.named('SELECT id FROM hukuk.belge WHERE id = CAST(@b AS uuid) FOR UPDATE'),
          parameters: {'b': belgeId});
      if (b.isEmpty) throw ApiHatasi.bulunamadi;
      final mevcut = await tx.execute(
          Sql.named('SELECT no FROM hukuk.belge_surum WHERE belge_id = CAST(@b AS uuid) AND sha256 = @o'),
          parameters: {'b': belgeId, 'o': ozet});
      if (mevcut.isNotEmpty) {
        throw ApiHatasi(409, 'Bu içerik zaten sürüm ${mevcut.first[0]} olarak kayıtlı.', kod: 'mukerrer');
      }
      final s = await tx.execute(
          Sql.named('SELECT coalesce(max(no), 0) + 1 FROM hukuk.belge_surum WHERE belge_id = CAST(@b AS uuid)'),
          parameters: {'b': belgeId});
      final yeniNo = s.first[0]! as int;
      final anahtar = '${k.kiraciId}/$belgeId/$yeniNo';
      await depo.yaz(anahtar, icerik);
      await tx.execute(
        Sql.named('INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) '
            'VALUES (CAST(@b AS uuid), CAST(@k AS uuid), @n, @o, @s, @da, CAST(@u AS uuid), @an)'),
        parameters: {
          'b': belgeId,
          'k': k.kiraciId,
          'n': yeniNo,
          'o': ozet,
          's': icerik.length,
          'da': dosyaAdi,
          'u': k.kullaniciId,
          'an': anahtar,
        },
      );
      await DosyaApi.denetim(tx, k, 'degisiklik', 'belge', belgeId, 'Sürüm $yeniNo · sha256 $ozet');
      return yeniNo;
    });
    return jsonYanit({'id': belgeId, 'no': no, 'sha256': ozet}, durum: 201);
  }

  /// İndirme: içerik depodan okunur ve kayıtlı özetle yeniden karşılaştırılır (bütünlük); her indirme denetime yazılır.
  Future<Response> _indir(Request istek, String belgeId, String no) async {
    final k = kimlik(istek);
    final surumNo = int.tryParse(no);
    if (surumNo == null) throw ApiHatasi.bulunamadi;
    final (anahtar, ozet, dosyaAdi) = await vt.kiraciIcin(k, (tx) async {
      final rs = await tx.execute(
        Sql.named('SELECT depo_anahtari, sha256, dosya_adi FROM hukuk.belge_surum '
            'WHERE belge_id = CAST(@b AS uuid) AND no = @n'),
        parameters: {'b': belgeId, 'n': surumNo},
      );
      if (rs.isEmpty) throw ApiHatasi.bulunamadi;
      await DosyaApi.denetim(tx, k, 'goruntuleme', 'belge', belgeId, 'Sürüm $surumNo indirildi');
      return (rs.first[0]! as String, (rs.first[1]! as String).trim(), rs.first[2]! as String);
    });
    final icerik = await depo.oku(anahtar);
    if (sha256Ozeti(icerik) != ozet) {
      // Depodaki içerik değişmiş veya bozulmuş: kullanıcıya verilmez.
      throw const ApiHatasi(500, 'Belge bütünlük denetiminden geçemedi; yöneticinize bildirildi.', kod: 'butunluk');
    }
    return Response.ok(icerik, headers: {
      'content-type': 'application/octet-stream',
      'content-disposition': "attachment; filename*=UTF-8''${Uri.encodeComponent(dosyaAdi)}",
      'x-sha256': ozet,
      'cache-control': 'no-store',
    });
  }
}
