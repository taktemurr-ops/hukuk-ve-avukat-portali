import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'kimlik_api.dart';
import 'veritabani.dart';

/// iCal (RFC 5545) etkinliği. [tumGun] ise yalnızca tarih kullanılır.
class IcsEtkinlik {
  const IcsEtkinlik({
    required this.uid,
    required this.baslangic,
    required this.baslik,
    this.bitis,
    this.tumGun = false,
    this.yer,
    this.aciklama,
    this.hatirlatmaDakika,
  });

  final String uid;
  final DateTime baslangic;
  final DateTime? bitis;
  final bool tumGun;
  final String baslik;
  final String? yer;
  final String? aciklama;
  final int? hatirlatmaDakika;
}

String _kacis(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll(RegExp(r'\r?\n'), r'\n');

String _utc(DateTime t) {
  final u = t.toUtc();
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${iki(u.month)}${iki(u.day)}T${iki(u.hour)}${iki(u.minute)}${iki(u.second)}Z';
}

String _tarih(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

/// 75 sekizliği aşan satırlar katlanır (UTF-8 karakter bölünmeden), satır sonları CRLF.
String _katla(String satir) {
  final parcalar = <String>[];
  var b = StringBuffer();
  var bayt = 0;
  var sinir = 75;
  for (final r in satir.runes) {
    final c = String.fromCharCode(r);
    final n = utf8.encode(c).length;
    if (bayt + n > sinir) {
      parcalar.add(b.toString());
      b = StringBuffer();
      bayt = 0;
      sinir = 74; // devam satırı bir boşlukla başlar
    }
    b.write(c);
    bayt += n;
  }
  parcalar.add(b.toString());
  return parcalar.join('\r\n ');
}

String icsOlustur(List<IcsEtkinlik> etkinlikler, {required String takvimAdi, required DateTime simdi}) {
  final s = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Hukuk ve Avukat Portali//TR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_kacis(takvimAdi)}',
    'X-WR-TIMEZONE:Europe/Istanbul',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
    'X-PUBLISHED-TTL:PT1H',
  ];
  for (final e in etkinlikler) {
    s.addAll([
      'BEGIN:VEVENT',
      'UID:${e.uid}',
      'DTSTAMP:${_utc(simdi)}',
      if (e.tumGun) ...[
        'DTSTART;VALUE=DATE:${_tarih(e.baslangic)}',
        'DTEND;VALUE=DATE:${_tarih(e.baslangic.add(const Duration(days: 1)))}',
        'TRANSP:TRANSPARENT',
      ] else ...[
        'DTSTART:${_utc(e.baslangic)}',
        'DTEND:${_utc(e.bitis ?? e.baslangic.add(const Duration(hours: 1)))}',
      ],
      'SUMMARY:${_kacis(e.baslik)}',
      if (e.yer != null && e.yer!.isNotEmpty) 'LOCATION:${_kacis(e.yer!)}',
      if (e.aciklama != null && e.aciklama!.isNotEmpty) 'DESCRIPTION:${_kacis(e.aciklama!)}',
      if (e.hatirlatmaDakika != null) ...[
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_kacis(e.baslik)}',
        'TRIGGER:-PT${e.hatirlatmaDakika}M',
        'END:VALARM',
      ],
      'END:VEVENT',
    ]);
  }
  s.add('END:VCALENDAR');
  return '${s.map(_katla).join('\r\n')}\r\n';
}

/// Takvim aboneliği: kişiye özel gizli bağlantı (yalnızca özeti saklanır). Akış bağlantı sahibinin yetkisiyle
/// üretilir; müvekkil adı ve dosya başlığı içermez (dış takvim sağlayıcısına gider).
class TakvimApi {
  TakvimApi(this.vt, {Uri? disAdres, Random? rastgele})
      : disAdres = disAdres ?? Uri.parse('http://localhost:8080/'),
        _rastgele = rastgele ?? Random.secure();

  final Veritabani vt;

  /// Sunucunun dışarıdan erişilen adresi; bağlantı bunun altında verilir.
  final Uri disAdres;
  final Random _rastgele;

  Router get router => Router()
    ..get('/ben/takvim', _durum)
    ..post('/ben/takvim', _olustur)
    ..delete('/ben/takvim', _kapat)
    ..get('/acik/takvim/<dosya>', _akis);

  Future<Response> _durum(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT olusturma, son_okuma FROM hukuk.takvim_baglantisi_var()'));
    if (rs.isEmpty) return jsonYanit({'var': false});
    return jsonYanit({
      'var': true,
      'olusturma': (rs.first[0]! as DateTime).toUtc().toIso8601String(),
      'sonOkuma': rs.first[1] == null ? null : (rs.first[1]! as DateTime).toUtc().toIso8601String(),
    });
  }

  /// Yeni bağlantı (öncekini geçersiz kılar). Bağlantı yalnızca bu yanıtta görünür.
  Future<Response> _olustur(Request istek) async {
    final k = kimlik(istek);
    final token = List.generate(32, (_) => _rastgele.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await vt.kiraciIcin(
        k, (tx) => tx.execute(Sql.named('SELECT hukuk.takvim_baglantisi_olustur(@o)'), parameters: {'o': tokenOzeti(token)}));
    final adres = disAdres.resolve('acik/takvim/$token.ics');
    return jsonYanit({'adres': adres.toString(), 'webcal': adres.replace(scheme: 'webcal').toString()}, durum: 201);
  }

  Future<Response> _kapat(Request istek) async {
    final k = kimlik(istek);
    final rs = await vt.kiraciIcin(k, (tx) => tx.execute('SELECT hukuk.takvim_baglantisi_kapat()'));
    return jsonYanit({'kapatildi': rs.first[0] == true});
  }

  Future<Response> _akis(Request istek, String dosya) async {
    final token = dosya.endsWith('.ics') ? dosya.substring(0, dosya.length - 4) : dosya;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) throw ApiHatasi.bulunamadi;
    final sahip = await vt.genel(
        (tx) => tx.execute(Sql.named('SELECT kullanici_id::text, kiraci_id::text FROM hukuk.takvim_sahibi(@o)'),
            parameters: {'o': tokenOzeti(token)}));
    if (sahip.isEmpty) throw ApiHatasi.bulunamadi; // bağlantı yok, yenilenmiş ya da hesap pasif: aynı yanıt
    final k = KimlikBaglami(kullaniciId: sahip.first[0]! as String, kiraciId: sahip.first[1]! as String);
    final (durusmalar, sureler) = await vt.kiraciIcin(k, (tx) async {
      final d = await tx.execute(
        Sql.named('SELECT du.id::text, du.baslangic, du.sure_dakika, du.yer, du.tur, d.ic_no, d.mahkeme, d.esas_no '
            'FROM hukuk.durusma du JOIN hukuk.dosya d ON d.id = du.dosya_id '
            'WHERE (du.katilan = CAST(@u AS uuid) OR CAST(@u AS uuid) IN (d.sorumlu, d.yedek_sorumlu)) '
            "AND du.baslangic > now() - interval '30 days' AND du.baslangic < now() + interval '400 days' "
            'ORDER BY du.baslangic LIMIT 1000'),
        parameters: {'u': k.kullaniciId},
      );
      final s = await tx.execute(
        Sql.named('SELECT s.id::text, s.son_gun, s.durum, d.ic_no FROM hukuk.sure_kaydi s JOIN hukuk.dosya d ON d.id = s.dosya_id '
            "WHERE s.durum IN ('teyitBekliyor', 'teyitli') "
            'AND (s.asil_sorumlu = CAST(@u AS uuid) OR s.yedek_sorumlu = CAST(@u AS uuid)) '
            "AND s.son_gun > current_date - 30 ORDER BY s.son_gun LIMIT 1000"),
        parameters: {'u': k.kullaniciId},
      );
      return (d, s);
    });
    final etkinlikler = <IcsEtkinlik>[
      for (final r in durusmalar)
        IcsEtkinlik(
          uid: 'durusma-${r[0]}@hukukportali',
          baslangic: r[1]! as DateTime,
          bitis: (r[1]! as DateTime).add(Duration(minutes: r[2]! as int)),
          baslik: '${r[4]} · ${r[5]}',
          yer: r[3] as String?,
          aciklama: [if (r[6] != null) r[6], if (r[7] != null) r[7]].join(' '),
          hatirlatmaDakika: 120,
        ),
      for (final r in sureler)
        IcsEtkinlik(
          uid: 'sure-${r[0]}@hukukportali',
          baslangic: r[1]! as DateTime,
          tumGun: true,
          baslik: 'Süre son günü · ${r[3]}${r[2] == 'teyitBekliyor' ? ' (teyit bekliyor)' : ''}',
          aciklama: 'Ayrıntı için portala giriş yapın.',
          hatirlatmaDakika: 24 * 60,
        ),
    ];
    return Response.ok(
      icsOlustur(etkinlikler, takvimAdi: 'Hukuk Portalı', simdi: DateTime.now()),
      headers: {'content-type': 'text/calendar; charset=utf-8', 'cache-control': 'private, max-age=300'},
    );
  }
}
