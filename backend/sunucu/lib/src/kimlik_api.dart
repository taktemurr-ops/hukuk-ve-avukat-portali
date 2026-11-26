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
import 'sifreleme.dart';
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
          // `acik/` altındaki yollar (ör. ihbar formu) oturum gerektirmez; bu uçlar yalnızca SECURITY DEFINER
          // fonksiyonlarıyla sınırlı işlem yapar.
          if (acikYollar.contains(istek.url.path) || istek.url.path.startsWith('acik/')) return ic(istek);
          final baslik = istek.headers['authorization'] ?? '';
          if (!baslik.startsWith('Bearer ')) throw ApiHatasi.yetkisiz;
          final ozet = tokenOzeti(baslik.substring(7).trim());
          final satirlar = await vt.genel((tx) => tx.execute(
                Sql.named('SELECT o.kullanici_id::text, o.kiraci_id::text, hukuk.portal_kisisi(o.kullanici_id)::text, '
                    'CASE WHEN hukuk.yalniz_dis_avukat(o.kullanici_id) '
                    "THEN coalesce(hukuk.dis_avukat_kimligi(o.kullanici_id)::text, '') END "
                    'FROM hukuk.oturum_coz(@o) o'),
                parameters: {'o': ozet},
              ));
          if (satirlar.isEmpty) throw ApiHatasi.yetkisiz;
          final s = satirlar.first;
          final baglam = KimlikBaglami(
              kullaniciId: s[0]! as String,
              kiraciId: s[1]! as String,
              portalKisiId: s[2] as String?,
              disAvukatId: s[3] as String?);
          // Müvekkil oturumu yalnızca portal uçlarını, kendi bilgisini ve çıkışı kullanabilir.
          final yol = istek.url.path;
          if (baglam.portal &&
              !(yol.startsWith('portal/') || yol == 'ben' || yol == 'cikis' || yol == 'ben/sifre' || yol.startsWith('ben/oturumlar'))) {
            throw const ApiHatasi(403, 'Bu işlem müvekkil portalında kullanılamaz.', kod: 'yasak');
          }
          // Yalnızca dış avukat rolündeki kullanıcı (bir büroya bağlı olsun olmasın; bağlı değilse kimlik boş)
          // yalnızca kendi portal uçlarını ve hesap işlemlerini kullanabilir.
          if (baglam.disAvukat &&
              !(yol.startsWith('dis-portal/') || yol == 'ben' || yol == 'cikis' || yol == 'ben/sifre' ||
                  yol.startsWith('ben/oturumlar'))) {
            throw const ApiHatasi(403, 'Bu işlem dış avukat portalında kullanılamaz.', kod: 'yasak');
          }
          // Askıdaki veya iptal edilmiş hesapta veriler salt okunur (silinmez); abonelik ve çıkış işlemleri serbest.
          if (istek.method != 'GET' && !baglam.portal && !_yazmaKilidiMuaf(yol)) {
            final rs = await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.abonelik_yazilabilir(CAST(@k AS uuid))'),
                parameters: {'k': baglam.kiraciId}));
            if (rs.first[0] == false) {
              throw const ApiHatasi(402,
                  'Aboneliğiniz askıda: verileriniz korunuyor ve görüntülenebilir, ancak değişiklik için ödeme gerekiyor.',
                  kod: 'abonelik_askida');
            }
          }
          return ic(istek.change(context: {_kimlikAnahtari: baglam}));
        };

bool _yazmaKilidiMuaf(String yol) => yol == 'cikis' || yol.startsWith('abonelik') || yol.startsWith('ben/') ||
    yol == 'denetim/kayit'; // salt okunur hesapta da dışa aktarma kaydı düşülmeli

/// Kabul edilen en uzun şifre (karakter).
const azamiSifreUzunlugu = 256;

class KimlikApi {
  KimlikApi(this.vt, this.sifreleyici,
      {Random? rastgele,
      this.oturumSuresi = const Duration(hours: 8),
      DateTime Function()? saat,
      this.sifirlamaAdresi,
      this.dogrulamaAdresi})
      : _rastgele = rastgele ?? Random.secure(),
        _saat = saat ?? DateTime.now;

  final Veritabani vt;

  /// TOTP sırlarını şifreler (anahtar ortamdan; veritabanında yalnızca şifreli sır durur).
  final AlanSifreleyici sifreleyici;
  final DateTime Function() _saat;
  static const _yayinci = 'Hukuk ve Avukat Portalı';
  final Random _rastgele;
  final Duration oturumSuresi;

  /// Şifre sıfırlama sayfası (ör. https://app.../sifre-sifirla); bağlantıya `kod` eklenir. Yoksa e-postada yalnızca kod.
  final Uri? sifirlamaAdresi;

  /// E-posta doğrulama sayfası (ör. https://app.../eposta-dogrula); bağlantıya `kod` eklenir.
  final Uri? dogrulamaAdresi;

  /// 128 bit tek kullanımlık kod (yalnızca SHA-256 özeti saklanır).
  String _kod() => List.generate(16, (_) => _rastgele.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  String _dogrulamaMetni(String kod) {
    final adres = dogrulamaAdresi;
    final baglanti = adres == null
        ? 'Uygulamada "E-postamı doğrula" bölümüne bu kodu girin: $kod'
        : 'Adresinizi doğrulamak için: ${adres.replace(queryParameters: {'kod': kod})}';
    return '$_yayinci hesabınızı açtığınız için teşekkürler.\n\n$baglanti\n\n'
        'Bağlantı 48 saat geçerlidir. Bu kaydı siz yapmadıysanız bu e-postayı dikkate almayın.';
  }

  /// Kullanıcı yokken de aynı sürede yanıt vermek için sahte özet (kullanıcı varlığı sızmasın).
  static final _sahteOzet = SifreOzeti.olustur('sahte-sifre', tuz: Uint8List.fromList(List.filled(16, 7)));

  Router get router => Router()
    ..post('/giris', _giris)
    ..post('/kayit', _kayit)
    ..post('/acik/sifre-sifirlama', _sifirlamaIste)
    ..post('/acik/eposta-dogrula', _epostaDogrula)
    ..post('/acik/dogrulama-yeniden', _dogrulamaYeniden)
    ..post('/acik/sifre-sifirla', _sifirla)
    ..post('/cikis', _cikis)
    ..get('/ben', _ben)
    ..get('/kullanicilar', _kullanicilar)
    ..post('/ben/iki-adimli/baslat', _ikiAdimliBaslat)
    ..post('/ben/iki-adimli/etkinlestir', _ikiAdimliEtkinlestir)
    ..post('/ben/iki-adimli/kapat', _ikiAdimliKapat)
    ..post('/ben/sifre', _sifreDegistir)
    ..get('/ben/tercihler', _tercihler)
    ..put('/ben/tercihler', _tercihKaydet)
    ..get('/ben/oturumlar', _oturumlar)
    ..post('/ben/oturumlar/digerlerini-kapat', _digerOturumlariKapat)
    ..post('/ben/oturumlar/<kimlik>/kapat', _oturumKapat)
    ..put('/kullanicilar/<id>/roller', _rolDegistir)
    ..post('/kullanicilar/<id>/pasif', _pasiflestir)
    ..post('/kullanicilar/<id>/aktif', _aktiflestir);

  Future<Response> _giris(Request istek) async {
    final j = await jsonGovde(istek);
    final eposta = zorunluMetin(j, 'eposta').toLowerCase();
    final sifre = zorunluMetin(j, 'sifre');
    // Aşırı uzun şifre, Argon2 hesabıyla sunucuyu meşgul etmek için kullanılamasın.
    if (sifre.length > azamiSifreUzunlugu) {
      throw const ApiHatasi(401, 'E-posta veya şifre hatalı ya da hesap geçici olarak kilitli.', kod: 'giris_hatali');
    }
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

    Future<void> denemeKaydet(bool basarili) => vt.genel((tx) => tx.execute(
        Sql.named('SELECT hukuk.giris_denemesi_kaydet(@e, @b)'), parameters: {'e': eposta, 'b': basarili}));
    if (eslesen.isEmpty) {
      await denemeKaydet(false);
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
    // Şifre doğru olduktan sonra söylenir; yanlış şifrede hesap varlığı sızmaz.
    final dogrulandi = await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.eposta_dogrulandi_mi(CAST(@u AS uuid))'),
        parameters: {'u': kullanici[0]}));
    if (dogrulandi.first[0] != true) {
      throw const ApiHatasi(403, 'E-posta adresiniz henüz doğrulanmadı. Size gönderdiğimiz bağlantıya tıklayın ya da yeni bağlantı isteyin.',
          kod: 'eposta_dogrulanmadi');
    }
    if (kullanici[4] == true) {
      // Şifre doğru; ikinci adım: doğrulayıcı uygulamadaki 6 haneli kod. Başarı ancak kod da doğruysa kaydedilir.
      final kod = j['ikiAdimliKod'] as String?;
      if (kod == null || kod.trim().isEmpty) return jsonYanit({'ikiAdimliGerekli': true});
      if (!await _ikinciAdimDogru(kullanici[0]! as String, kod)) {
        await denemeKaydet(false);
        throw const ApiHatasi(401, 'Doğrulama kodu hatalı veya daha önce kullanılmış.', kod: 'iki_adimli_hatali');
      }
    }
    await denemeKaydet(true);

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
    final kod = _kod();
    // Hesap ve doğrulama e-postası tek işlemde: e-posta kuyruğa yazılamazsa hesap da açılmaz.
    final rs = await vt.genel((tx) async {
      final h = await tx.execute(
        Sql.named('SELECT kiraci_id::text, kullanici_id::text FROM hukuk.hesap_ac(@k, @t, @e, @a, @s)'),
        parameters: {'k': kurum, 't': tur, 'e': eposta, 'a': ad, 's': SifreOzeti.olustur(sifre)},
      );
      await tx.execute(Sql.named('SELECT hukuk.eposta_dogrulama_baslat(CAST(@u AS uuid), @o, @k, @m)'), parameters: {
        'u': h.first[1],
        'o': tokenOzeti(kod),
        'k': 'E-posta doğrulama · $_yayinci',
        'm': _dogrulamaMetni(kod),
      });
      return h;
    });
    return jsonYanit({'kiraciId': rs.first[0], 'kullaniciId': rs.first[1], 'dogrulamaGerekli': true}, durum: 201);
  }

  /// Adres kayıtlı olsun olmasın aynı yanıt (hesap varlığı sızmaz). Kod 128 bit, yalnızca özeti saklanır.
  Future<Response> _sifirlamaIste(Request istek) async {
    final eposta = zorunluMetin(await jsonGovde(istek), 'eposta').toLowerCase();
    if (Dogrulayicilar.eposta(eposta) == null) {
      final kod = _kod();
      final adres = sifirlamaAdresi;
      final baglanti = adres == null
          ? 'Uygulamada "Şifremi unuttum" bölümünde bu kodu girin: $kod'
          : 'Yeni şifrenizi belirlemek için: ${adres.replace(queryParameters: {'kod': kod})}';
      await vt.genel((tx) => tx.execute(
            Sql.named('SELECT hukuk.sifre_sifirlama_iste(@e, @o, @k, @m)'),
            parameters: {
              'e': eposta,
              'o': tokenOzeti(kod),
              'k': 'Şifre sıfırlama · $_yayinci',
              'm': 'Şifre sıfırlama isteği aldık.\n\n$baglanti\n\nBağlantı 1 saat geçerlidir ve bir kez kullanılabilir. '
                  'Şifreniz değişince tüm cihazlardaki oturumlarınız kapanır.\n\n'
                  'Bu isteği siz yapmadıysanız bu e-postayı dikkate almayın; şifreniz değişmez.',
            },
          ));
    }
    return jsonYanit({'durum': 'Adres kayıtlıysa şifre sıfırlama bağlantısı gönderildi.'}, durum: 202);
  }

  Future<Response> _epostaDogrula(Request istek) async {
    final kod = zorunluMetin(await jsonGovde(istek), 'kod').trim().toLowerCase();
    final rs = await vt.genel((tx) =>
        tx.execute(Sql.named('SELECT hukuk.eposta_dogrula(@o)'), parameters: {'o': tokenOzeti(kod)}));
    return jsonYanit({'hesapSayisi': rs.first[0]});
  }

  Future<Response> _dogrulamaYeniden(Request istek) async {
    final eposta = zorunluMetin(await jsonGovde(istek), 'eposta').toLowerCase();
    if (Dogrulayicilar.eposta(eposta) == null) {
      final kod = _kod();
      await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.eposta_dogrulama_yenile(@e, @o, @k, @m)'), parameters: {
            'e': eposta,
            'o': tokenOzeti(kod),
            'k': 'E-posta doğrulama · $_yayinci',
            'm': _dogrulamaMetni(kod),
          }));
    }
    return jsonYanit({'durum': 'Doğrulanmamış bir hesap varsa yeni bağlantı gönderildi.'}, durum: 202);
  }

  Future<Response> _sifirla(Request istek) async {
    final j = await jsonGovde(istek);
    final kod = zorunluMetin(j, 'kod').trim().toLowerCase();
    final sifre = zorunluMetin(j, 'sifre');
    final hata = Dogrulayicilar.sifre(sifre);
    if (hata != null) throw ApiHatasi(400, hata, kod: 'zayif_sifre');
    final rs = await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.sifre_sifirla(@o, @s)'),
        parameters: {'o': tokenOzeti(kod), 's': SifreOzeti.olustur(sifre)}));
    return jsonYanit({'hesapSayisi': rs.first[0]});
  }

  /// Kendi hesabıyla ilgili işlemler hem büro hem müvekkil portalı oturumunda çalışır.
  Future<T> _kendiIcin<T>(KimlikBaglami k, Future<T> Function(TxSession tx) islem) =>
      k.portal ? vt.portalIcin(k, islem) : vt.kiraciIcin(k, islem);

  static String _mevcutOturum(Request istek) =>
      tokenOzeti((istek.headers['authorization'] ?? '').replaceFirst('Bearer ', '').trim());

  /// Eski şifre doğrulanır (Argon2, sunucuda); yeni şifre kurallara uymalı ve eskisiyle aynı olmamalı.
  /// Bu oturum açık kalır, diğer tüm oturumlar kapanır.
  Future<Response> _sifreDegistir(Request istek) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final eski = zorunluMetin(j, 'eskiSifre');
    final yeni = zorunluMetin(j, 'yeniSifre');
    final ozet = await _kendiIcin(k, (tx) => tx.execute('SELECT hukuk.kendi_sifre_ozetim()'));
    final mevcut = ozet.first[0] as String?;
    if (mevcut == null || !SifreOzeti.dogrula(eski, mevcut)) {
      throw const ApiHatasi(400, 'Mevcut şifre hatalı.', kod: 'sifre_hatali');
    }
    final hata = Dogrulayicilar.sifre(yeni);
    if (hata != null) throw ApiHatasi(400, hata, kod: 'zayif_sifre');
    if (eski == yeni) throw const ApiHatasi(400, 'Yeni şifre eskisiyle aynı olamaz.', kod: 'zayif_sifre');
    await _kendiIcin(k, (tx) => tx.execute(Sql.named('SELECT hukuk.sifre_degistir(@s, @o)'),
        parameters: {'s': SifreOzeti.olustur(yeni), 'o': _mevcutOturum(istek)}));
    return jsonYanit({'degisti': true});
  }

  Future<Response> _oturumlar(Request istek) async {
    final k = kimlik(istek);
    final rs = await _kendiIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT kimlik, olusturma, son_kullanma, istemci, bu_oturum FROM hukuk.kendi_oturumlarim(@o)'),
            parameters: {'o': _mevcutOturum(istek)}));
    return jsonYanit([
      for (final r in rs)
        {
          'kimlik': r[0],
          'olusturma': (r[1]! as DateTime).toUtc().toIso8601String(),
          'sonKullanma': (r[2]! as DateTime).toUtc().toIso8601String(),
          'istemci': r[3],
          'buOturum': r[4],
        },
    ]);
  }

  Future<Response> _oturumKapat(Request istek, String oturumKimligi) async {
    final k = kimlik(istek);
    final rs = await _kendiIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT hukuk.kendi_oturumlarimi_kapat(@i, @o)'),
            parameters: {'i': oturumKimligi, 'o': _mevcutOturum(istek)}));
    if (rs.first[0] == 0) throw ApiHatasi.bulunamadi;
    return jsonYanit({'kapatilan': rs.first[0]});
  }

  Future<Response> _digerOturumlariKapat(Request istek) async {
    final k = kimlik(istek);
    final rs = await _kendiIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT hukuk.kendi_oturumlarimi_kapat(NULL, @o)'),
            parameters: {'o': _mevcutOturum(istek)}));
    return jsonYanit({'kapatilan': rs.first[0]});
  }

  Future<Response> _tercihler(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute(
        Sql.named('SELECT haftalik_ozet FROM hukuk.kullanici WHERE id = CAST(@u AS uuid)'), parameters: {'u': k.kullaniciId}));
    return jsonYanit({'haftalikOzet': rs.isEmpty ? true : rs.first[0] == true});
  }

  Future<Response> _tercihKaydet(Request istek) async {
    final k = kimlik(istek);
    final acik = (await jsonGovde(istek))['haftalikOzet'] != false;
    await vt.kiraciIcin(
        k, (tx) => tx.execute(Sql.named('SELECT hukuk.haftalik_ozet_tercihi(@a)'), parameters: {'a': acik}));
    return jsonYanit({'haftalikOzet': acik});
  }

  /// Ekip yönetimi (yalnızca yöneticiler; kurallar veritabanında: hesap türüne uygun rol, koltuk, son yönetici).
  Future<Response> _rolDegistir(Request istek, String id) async {
    final k = kimlik(istek);
    final roller = [for (final r in ((await jsonGovde(istek))['roller'] as List? ?? const [])) '$r'];
    await vt.kiraciIcin(k, (tx) => tx.execute(Sql.named('SELECT hukuk.kullanici_rolleri_degistir(CAST(@u AS uuid), @r)'),
        parameters: {'u': id, 'r': roller}));
    return jsonYanit({'roller': roller});
  }

  Future<Response> _pasiflestir(Request istek, String id) async {
    final k = kimlik(istek);
    final j = await jsonGovde(istek);
    final n = await vt.kiraciIcin(
        k,
        (tx) => tx.execute(Sql.named('SELECT hukuk.kullanici_pasiflestir(CAST(@u AS uuid), CAST(@d AS uuid), @g)'),
            parameters: {'u': id, 'd': j['devralan'] as String?, 'g': '${j['gerekce'] ?? ''}'}));
    return jsonYanit({'devredilen': n.first[0]});
  }

  Future<Response> _aktiflestir(Request istek, String id) async {
    final k = kimlik(istek);
    await vt.kiraciIcin(
        k, (tx) => tx.execute(Sql.named('SELECT hukuk.kullanici_aktiflestir(CAST(@u AS uuid))'), parameters: {'u': id}));
    return jsonYanit({'aktif': true});
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
            "'{}'), u.eposta FROM hukuk.kullanici u LEFT JOIN hukuk.kullanici_rol r ON r.kullanici_id = u.id "
            'GROUP BY u.id ORDER BY u.ad_soyad'));
    return jsonYanit([
      for (final r in rs) {'id': r[0], 'adSoyad': r[1], 'aktif': r[2], 'roller': r[3], 'eposta': r[4]},
    ]);
  }

  Future<Response> _ben(Request istek) async {
    final k = kimlik(istek);
    if (k.portal) {
      final rs = await vt.portalIcin(
          k, (tx) => tx.execute('SELECT ad_soyad, eposta, kurum, hesap_turu, kisi_adi FROM hukuk.portal_ben()'));
      if (rs.isEmpty) throw ApiHatasi.yetkisiz;
      final p = rs.first;
      return jsonYanit({
        'kullaniciId': k.kullaniciId,
        'kiraciId': k.kiraciId,
        'adSoyad': p[0],
        'eposta': p[1],
        'kurumAdi': p[2],
        'hesapTuru': p[3],
        'roller': ['muvekkil'],
        'portalKisiId': k.portalKisiId,
        'portalKisiAdi': p[4],
      });
    }
    final sonuc = await vt.kiraciIcin(k, (tx) async {
      final u = await tx.execute(
        Sql.named('SELECT u.ad_soyad, u.eposta, k.ad, k.hesap_turu, u.iki_adimli FROM hukuk.kullanici u '
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
      'ikiAdimli': s[4],
      'roller': [for (final x in r) x[0]],
      if (k.disAvukat) 'disAvukatId': k.disAvukatId,
    });
  }

  // ---------------------------------------------------------------------------
  // İki adımlı doğrulama (TOTP)
  // ---------------------------------------------------------------------------

  /// Girişte: şifreli sır çözülür, kod ±1 adım penceresinde doğrulanır ve adım bir kez kullanılabilir.
  Future<bool> _ikinciAdimDogru(String kullaniciId, String kod) async {
    final rs = await vt.genel((tx) => tx.execute(Sql.named('SELECT sir, son_adim FROM hukuk.iki_adimli_sir(CAST(@u AS uuid))'),
        parameters: {'u': kullaniciId}));
    if (rs.isEmpty || rs.first[0] == null) return false;
    final sir = sifreleyici.coz(rs.first[0]! as List<int>, baglam: kullaniciId);
    final adim = Totp.eslesenAdim(sir, kod, _saat());
    if (adim == null) return false;
    final kullanildi = await vt.genel((tx) => tx.execute(
        Sql.named('SELECT hukuk.iki_adimli_adim_kullan(CAST(@u AS uuid), @a)'), parameters: {'u': kullaniciId, 'a': adim}));
    return kullanildi.first[0] == true;
  }

  /// Kurulum: yeni sır üretilir, şifreli olarak "bekleyen" saklanır; uygulamaya QR (otpauth) bağlantısı döner.
  Future<Response> _ikiAdimliBaslat(Request istek) async {
    final k = kimlik(istek);
    final sir = Totp.sirUret();
    final eposta = await vt.kiraciIcin(k, (tx) async {
      await tx.execute(Sql.named('SELECT hukuk.iki_adimli_bekleyen_yaz(@s)'),
          parameters: {'s': TypedValue(Type.byteArray, sifreleyici.sifrele(sir, baglam: k.kullaniciId))});
      final e = await tx.execute(Sql.named('SELECT eposta FROM hukuk.kullanici WHERE id = CAST(@u AS uuid)'),
          parameters: {'u': k.kullaniciId});
      return e.first[0]! as String;
    });
    return jsonYanit({
      'sir': Totp.base32Kodla(sir),
      'otpauth': Totp.otpauthUri(yayinci: _yayinci, hesap: eposta, sir: sir),
    });
  }

  Future<Response> _ikiAdimliEtkinlestir(Request istek) async {
    final k = kimlik(istek);
    final kod = zorunluMetin(await jsonGovde(istek), 'kod');
    await vt.kiraciIcin(k, (tx) async {
      final b = await tx.execute('SELECT hukuk.iki_adimli_bekleyen()');
      final sifreli = b.first[0];
      if (sifreli == null) throw const ApiHatasi(409, 'Önce kurulumu başlatın.', kod: 'kural');
      final sir = sifreleyici.coz(sifreli as List<int>, baglam: k.kullaniciId);
      final adim = Totp.eslesenAdim(sir, kod, _saat());
      if (adim == null) throw const ApiHatasi(400, 'Kod doğrulanamadı; uygulamadaki güncel kodu girin.', kod: 'gecersiz_kod');
      await tx.execute(Sql.named('SELECT hukuk.iki_adimli_etkinlestir(@a)'), parameters: {'a': adim});
    });
    return jsonYanit({'ikiAdimli': true});
  }

  /// Kapatmak için güncel kod gerekir (oturumu ele geçiren biri korumayı kaldıramasın).
  Future<Response> _ikiAdimliKapat(Request istek) async {
    final k = kimlik(istek);
    final kod = zorunluMetin(await jsonGovde(istek), 'kod');
    if (!await _ikinciAdimDogru(k.kullaniciId, kod)) {
      throw const ApiHatasi(400, 'Kod doğrulanamadı veya daha önce kullanılmış.', kod: 'gecersiz_kod');
    }
    await vt.kiraciIcin(k, (tx) => tx.execute('SELECT hukuk.iki_adimli_kapat()'));
    return jsonYanit({'ikiAdimli': false});
  }
}

extension on String {
  /// Kayıt için istemci bilgisini makul uzunlukta tutar.
  String get characters300 => length > 300 ? substring(0, 300) : this;
}
