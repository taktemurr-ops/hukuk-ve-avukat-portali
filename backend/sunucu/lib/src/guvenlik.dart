import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:shelf/shelf.dart';

import 'hata.dart';

/// İstek gövdesini en fazla [sinir] bayt okur; aşılırsa okumayı keser ve 413 döner.
/// (Gövdenin tamamını belleğe alıp sonra boyuta bakmak, büyük istekle belleği tüketmeye açıktı.)
Future<List<int>> govdeBaytlari(Request istek, int sinir) async {
  final beyan = istek.contentLength;
  if (beyan != null && beyan > sinir) throw const ApiHatasi(413, 'İstek çok büyük.');
  final b = BytesBuilder(copy: false);
  await for (final parca in istek.read()) {
    if (b.length + parca.length > sinir) throw const ApiHatasi(413, 'İstek çok büyük.');
    b.add(parca);
  }
  return b.takeBytes();
}

Future<String> govdeMetni(Request istek, int sinir) async {
  try {
    return utf8.decode(await govdeBaytlari(istek, sinir));
  } on FormatException {
    throw const ApiHatasi(400, 'İstek UTF-8 değil.', kod: 'gecersiz_istek');
  }
}

/// Yüzde kodlu başlık değeri (ör. X-Dosya-Adi). Bozuk kodlama ve denetim karakterleri (satır sonu, NUL) 400 döner.
String basliktanCoz(String ham) {
  final String deger;
  try {
    deger = Uri.decodeComponent(ham);
  } on ArgumentError {
    throw const ApiHatasi(400, 'Başlık değeri geçersiz.', kod: 'gecersiz_istek');
  } on FormatException {
    throw const ApiHatasi(400, 'Başlık değeri geçersiz.', kod: 'gecersiz_istek');
  }
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(deger)) {
    throw const ApiHatasi(400, 'Başlık değeri geçersiz.', kod: 'gecersiz_istek');
  }
  return deger;
}

/// İstemcinin IP adresi. [guvenilirVekil] yalnızca sunucu kendi ters vekilinin (nginx) arkasındaysa açılır;
/// o zaman X-Forwarded-For'un SON değeri (vekilin eklediği) kullanılır. Aksi hâlde başlık sahtelenebilir.
String istemciIp(Request istek, {bool guvenilirVekil = false}) {
  if (guvenilirVekil) {
    final xff = istek.headers['x-forwarded-for'];
    if (xff != null && xff.trim().isNotEmpty) return xff.split(',').last.trim();
  }
  final bilgi = istek.context['shelf.io.connection_info'];
  if (bilgi is HttpConnectionInfo) return bilgi.remoteAddress.address;
  return 'bilinmiyor';
}

/// Oturumsuz uçlar için IP başına hız sınırı (bellek içi kayan pencere).
///
/// Kimlik uçları (giriş, kayıt, davet, şifre sıfırlama, e-posta doğrulama): 10 dakikada 30 istek.
/// Diğer açık uçlar (ihbar, ihbar durumu, takvim, ödeme bildirimi): dakikada 60 istek.
/// Hesap bazlı kilit (5 hatalı giriş) veritabanında ayrıca uygulanır; bu sınır, çok sayıda hesabı deneyen
/// saldırıyı ve şifre özetiyle sunucuyu meşgul etmeyi (Argon2) engeller.
class HizSiniri {
  HizSiniri({this.guvenilirVekil = false, DateTime Function()? saat}) : _saat = saat ?? DateTime.now;

  final bool guvenilirVekil;
  final DateTime Function() _saat;
  final Map<String, List<DateTime>> _kayit = {};

  /// IP adresi bellekte de açık tutulmaz (ihbarcı gizliliği): süreç başına rastgele tuzla özetlenir, hiçbir yere yazılmaz.
  final String _tuz = base64Url.encode(List.generate(16, (_) => Random.secure().nextInt(256)));
  var _sonTemizlik = DateTime.fromMillisecondsSinceEpoch(0);

  static const _kimlikYollari = {'giris', 'kayit'};

  static (String, int, Duration)? grup(String yol) {
    if (_kimlikYollari.contains(yol) ||
        yol == 'acik/davet-kabul' ||
        yol.startsWith('acik/sifre-') ||
        yol == 'acik/eposta-dogrula' ||
        yol == 'acik/dogrulama-yeniden') {
      return ('kimlik', 30, const Duration(minutes: 10));
    }
    if (yol.startsWith('acik/')) return ('acik', 60, const Duration(minutes: 1));
    return null;
  }

  Middleware get middleware => (ic) => (istek) async {
        final g = grup(istek.url.path);
        if (g == null || istek.method == 'OPTIONS') return ic(istek);
        final (ad, sinir, pencere) = g;
        final simdi = _saat();
        _temizle(simdi);
        final ip = istemciIp(istek, guvenilirVekil: guvenilirVekil);
        final anahtar = '$ad|${sha256.convert(utf8.encode('$_tuz|$ip'))}';
        final l = _kayit.putIfAbsent(anahtar, () => []);
        l.removeWhere((t) => simdi.difference(t) >= pencere);
        if (l.length >= sinir) {
          final bekle = pencere - simdi.difference(l.first);
          return Response(429,
              body: jsonEncode({'hata': 'cok_istek', 'mesaj': 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.'}),
              headers: {
                'content-type': 'application/json; charset=utf-8',
                'retry-after': '${bekle.inSeconds + 1}',
              });
        }
        l.add(simdi);
        return ic(istek);
      };

  void _temizle(DateTime simdi) {
    if (simdi.difference(_sonTemizlik) < const Duration(minutes: 5)) return;
    _sonTemizlik = simdi;
    _kayit.removeWhere((_, l) => l.isEmpty || simdi.difference(l.last) > const Duration(minutes: 15));
  }
}
