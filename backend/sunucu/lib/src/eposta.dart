import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart' as m;
import 'package:mailer/smtp_server.dart' as m;
import 'package:postgres/postgres.dart';

import 'veritabani.dart';

/// E-posta gönderim soyutlaması. Canlıda Türkiye'deki SMTP sağlayıcısı (TLS zorunlu) kullanılır.
abstract class EpostaGonderici {
  Future<void> gonder({required String alici, required String konu, required String metin});
}

class SmtpGonderici implements EpostaGonderici {
  SmtpGonderici({
    required String sunucu,
    required int port,
    required String kullanici,
    required String sifre,
    required this.gonderenAdres,
    this.gonderenAd = 'Hukuk ve Avukat Portalı',
  }) : _sunucu = m.SmtpServer(sunucu, port: port, username: kullanici, password: sifre, ssl: port == 465);

  final m.SmtpServer _sunucu;
  final String gonderenAdres;
  final String gonderenAd;

  @override
  Future<void> gonder({required String alici, required String konu, required String metin}) async {
    final ileti = m.Message()
      ..from = m.Address(gonderenAdres, gonderenAd)
      ..recipients.add(alici)
      ..subject = konu
      ..text = metin;
    await m.send(ileti, _sunucu, timeout: const Duration(seconds: 30));
  }
}

/// Geliştirme: e-postayı gönderme, sunucu günlüğüne yaz. Canlıda kullanılmaz (içerik bağlantı/kod içerebilir).
class GunlugeYazanGonderici implements EpostaGonderici {
  @override
  Future<void> gonder({required String alici, required String konu, required String metin}) async {
    stdout.writeln('[e-posta: geliştirme] Alıcı: $alici | Konu: $konu\n$metin\n---');
  }
}

/// Kuyruktaki e-postaları gönderen arka plan görevi. Birden çok sunucu örneği aynı anda çalışabilir.
class EpostaGorevi {
  EpostaGorevi(this.vt, this.gonderici, {this.aralik = const Duration(seconds: 30), this.kaydet});

  final Veritabani vt;
  final EpostaGonderici gonderici;
  final Duration aralik;
  final void Function(Object hata)? kaydet;
  Timer? _zamanlayici;
  bool _calisiyor = false;

  void baslat() => _zamanlayici ??= Timer.periodic(aralik, (_) => birTur());

  void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  /// Bir tur: en fazla 20 ileti alır ve gönderir; gönderilen sayısını döner.
  Future<int> birTur() async {
    if (_calisiyor) return 0;
    _calisiyor = true;
    var gonderilen = 0;
    try {
      final rs = await vt.genel((tx) => tx.execute('SELECT id, alici, konu, metin FROM hukuk.eposta_al(20)'));
      for (final r in rs) {
        String? hata;
        try {
          await gonderici.gonder(alici: r[1]! as String, konu: r[2]! as String, metin: r[3]! as String);
          gonderilen++;
        } on Object catch (e) {
          hata = '$e';
          kaydet?.call(e);
        }
        await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.eposta_sonuc(@i, @b, @h)'),
            parameters: {'i': r[0], 'b': hata == null, 'h': hata}));
      }
    } on Object catch (e) {
      kaydet?.call(e);
    } finally {
      _calisiyor = false;
    }
    return gonderilen;
  }
}
