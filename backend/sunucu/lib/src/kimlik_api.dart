import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'sifre.dart';
import 'veritabani.dart';

const _kimlikAnahtari = 'hukuk.kimlik';

String tokenOzeti(String token) => sha256.convert(utf8.encode(token)).toString();

KimlikBaglami kimlik(Request istek) {
  final k = istek.context[_kimlikAnahtari];
  if (k is KimlikBaglami) return k;
  throw ApiHatasi.yetkisiz;
}

/// `Authorization: Bearer <token>` başlığını veritabanındaki oturumla doğrular.
/// Açık yollar (giriş, sağlık) dışında her istek oturum ister.
Middleware oturumDogrula(Veritabani vt, {Set<String> acikYollar = const {'giris', 'kayit', 'saglik'}}) =>
    (ic) => (istek) async {
          if (acikYollar.contains(istek.url.path)) return ic(istek);
          final baslik = istek.headers['authorization'] ?? '';
          if (!baslik.startsWith('Bearer ')) throw ApiHatasi.yetkisiz;
          final ozet = tokenOzeti(baslik.substring(7).trim());
          final satirlar = await vt.genel((tx) => tx.execute(
                Sql.named('SELECT kullanici_id::text, kiraci_id::text FROM hukuk.oturum_coz(@o)'),
                parameters: {'o': ozet},
              ));
          if (satirlar.isEmpty) throw ApiHatasi.yetkisiz;
          final s = satirlar.first;
          return ic(istek.change(context: {
            _kimlikAnahtari: KimlikBaglami(kullaniciId: s[0]! as String, kiraciId: s[1]! as String),
          }));
        };

class KimlikApi {
  KimlikApi(this.vt, {Random? rastgele, this.oturumSuresi = const Duration(hours: 8)})
      : _rastgele = rastgele ?? Random.secure();

  final Veritabani vt;
  final Random _rastgele;
  final Duration oturumSuresi;

  /// Kullanıcı yokken de aynı sürede yanıt vermek için sahte özet (kullanıcı varlığı sızmasın).
  static final _sahteOzet = SifreOzeti.olustur('sahte-sifre', tuz: Uint8List.fromList(List.filled(16, 7)));

  Router get router => Router()
    ..post('/giris', _giris)
    ..post('/kayit', _kayit)
    ..post('/cikis', _cikis)
    ..get('/ben', _ben)
    ..get('/kullanicilar', _kullanicilar);

  Future<Response> _giris(Request istek) async {
    final j = await jsonGovde(istek);
    final eposta = zorunluMetin(j, 'eposta').toLowerCase();
    final sifre = zorunluMetin(j, 'sifre');
    final secilenKiraci = j['kiraciId'] as String?;

    final adaylar = await vt.genel((tx) => tx.execute(
          Sql.named('SELECT kullanici_id::text, kiraci_id::text, kiraci_adi, sifre_ozeti, iki_adimli '
              'FROM hukuk.giris_adaylari(@e)'),
          parameters: {'e': eposta},
        ));
    final eslesen = [
      for (final a in adaylar)
        if (SifreOzeti.dogrula(sifre, a[3]! as String)) a,
    ];
    if (adaylar.isEmpty) SifreOzeti.dogrula(sifre, _sahteOzet);

    await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.giris_denemesi_kaydet(@e, @b)'),
        parameters: {'e': eposta, 'b': eslesen.isNotEmpty}));
    if (eslesen.isEmpty) {
      // Kilitli hesap, yanlış şifre ve olmayan hesap aynı yanıtı alır.
      throw const ApiHatasi(401, 'E-posta veya şifre hatalı ya da hesap geçici olarak kilitli.', kod: 'giris_hatali');
    }

    final secilen = secilenKiraci == null ? eslesen : eslesen.where((a) => a[1] == secilenKiraci).toList();
    if (secilen.length != 1) {
      return jsonYanit({
        'kurumSecin': [
          for (final a in eslesen) {'kiraciId': a[1], 'ad': a[2]},
        ],
      });
    }
    final kullanici = secilen.single;
    if (kullanici[4] == true) {
      // İki adımlı doğrulama sırrı şifreli sütuna taşındığında burada kod istenecek.
      throw const ApiHatasi(501, 'İki adımlı doğrulama sunucuda henüz etkin değil.', kod: 'iki_adimli');
    }

    final token = base64Url.encode(List.generate(32, (_) => _rastgele.nextInt(256))).replaceAll('=', '');
    await vt.genel((tx) => tx.execute(
          Sql.named("SELECT hukuk.oturum_ac(@o, CAST(@k AS uuid), CAST(@s AS integer) * interval '1 second', @i)"),
          parameters: {
            'o': tokenOzeti(token),
            'k': kullanici[0],
            's': oturumSuresi.inSeconds,
            'i': (istek.headers['user-agent'] ?? '').characters300,
          },
        ));
    final baglam = KimlikBaglami(kullaniciId: kullanici[0]! as String, kiraciId: kullanici[1]! as String);
    await vt.kiraciIcin(
        baglam,
        (tx) => tx.execute(
              Sql.named("INSERT INTO hukuk.denetim_kaydi (kiraci_id, islem, nesne_turu, nesne_id, onceki_ozet, ozet) "
                  "VALUES (CAST(@k AS uuid), 'girisBasarili', 'oturum', @u, '', '')"),
              parameters: {'k': baglam.kiraciId, 'u': baglam.kullaniciId},
            ));
    return jsonYanit({
      'token': token,
      'kullaniciId': baglam.kullaniciId,
      'kiraciId': baglam.kiraciId,
      'gecerlilikSaniye': oturumSuresi.inSeconds,
    });
  }

  /// Kendi kendine hesap açma: kiracı, kurucu kullanıcı ve 14 günlük deneme.
  Future<Response> _kayit(Request istek) async {
    final j = await jsonGovde(istek);
    final kurum = zorunluMetin(j, 'kurumAdi');
    final tur = zorunluMetin(j, 'hesapTuru');
    if (!HesapTuru.values.any((t) => t.name == tur)) throw const ApiHatasi(400, 'Geçersiz hesap türü.');
    final eposta = zorunluMetin(j, 'eposta').toLowerCase();
    final epostaHatasi = Dogrulayicilar.eposta(eposta);
    if (epostaHatasi != null) throw ApiHatasi(400, epostaHatasi, kod: 'gecersiz_istek');
    final sifre = zorunluMetin(j, 'sifre');
    final sifreHatasi = Dogrulayicilar.sifre(sifre, eposta: eposta);
    if (sifreHatasi != null) throw ApiHatasi(400, sifreHatasi, kod: 'zayif_sifre');
    final ad = zorunluMetin(j, 'adSoyad');
    final rs = await vt.genel((tx) => tx.execute(
          Sql.named('SELECT kiraci_id::text, kullanici_id::text FROM hukuk.hesap_ac(@k, @t, @e, @a, @s)'),
          parameters: {'k': kurum, 't': tur, 'e': eposta, 'a': ad, 's': SifreOzeti.olustur(sifre)},
        ));
    return jsonYanit({'kiraciId': rs.first[0], 'kullaniciId': rs.first[1]}, durum: 201);
  }

  Future<Response> _cikis(Request istek) async {
    final baslik = istek.headers['authorization'] ?? '';
    await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.oturum_kapat(@o)'),
        parameters: {'o': tokenOzeti(baslik.replaceFirst('Bearer ', '').trim())}));
    return jsonYanit({'durum': 'kapatildi'});
  }

  /// Aynı kurumdaki kullanıcılar (atama listeleri ve adların gösterimi için).
  Future<Response> _kullanicilar(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(
        k,
        (tx) => tx.execute('SELECT u.id::text, u.ad_soyad, u.aktif, coalesce(array_agg(r.rol) FILTER (WHERE r.rol IS NOT NULL), '
            "'{}') FROM hukuk.kullanici u LEFT JOIN hukuk.kullanici_rol r ON r.kullanici_id = u.id "
            'GROUP BY u.id ORDER BY u.ad_soyad'));
    return jsonYanit([
      for (final r in rs) {'id': r[0], 'adSoyad': r[1], 'aktif': r[2], 'roller': r[3]},
    ]);
  }

  Future<Response> _ben(Request istek) async {
    final k = kimlik(istek);
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final u = await tx.execute(
        Sql.named('SELECT u.ad_soyad, u.eposta, k.ad, k.hesap_turu FROM hukuk.kullanici u '
            'JOIN hukuk.kiraci k ON k.id = u.kiraci_id WHERE u.id = CAST(@u AS uuid)'),
        parameters: {'u': k.kullaniciId},
      );
      final r = await tx.execute(
        Sql.named('SELECT rol FROM hukuk.kullanici_rol WHERE kullanici_id = CAST(@u AS uuid) ORDER BY rol'),
        parameters: {'u': k.kullaniciId},
      );
      return (u, r);
    });
    final (u, r) = sonuc;
    if (u.isEmpty) throw ApiHatasi.yetkisiz;
    final s = u.first;
    return jsonYanit({
      'kullaniciId': k.kullaniciId,
      'kiraciId': k.kiraciId,
      'adSoyad': s[0],
      'eposta': s[1],
      'kurumAdi': s[2],
      'hesapTuru': s[3],
      'roller': [for (final x in r) x[0]],
    });
  }
}

extension on String {
  /// Kayıt için istemci bilgisini makul uzunlukta tutar.
  String get characters300 => length > 300 ? substring(0, 300) : this;
}
