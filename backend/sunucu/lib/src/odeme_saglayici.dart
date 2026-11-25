import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

/// Ödeme sayfasını başlatmak için sağlayıcıya giden bilgiler. Tutar her zaman sunucuda hesaplanır.
class OdemeIstegi {
  const OdemeIstegi({
    required this.referans,
    required this.toplamKurus,
    required this.aciklama,
    required this.eposta,
    required this.adSoyad,
    required this.istemciIp,
  });

  /// Sunucunun ürettiği tekil, tahmin edilemez referans (bildirimde geri gelir).
  final String referans;
  final int toplamKurus;
  final String aciklama;
  final String eposta;
  final String adSoyad;
  final String istemciIp;
}

/// Kullanıcının yönlendirileceği ödeme sayfası (kart bilgisi yalnızca sağlayıcının sayfasında girilir).
class OdemeBaslangici {
  const OdemeBaslangici(this.odemeAdresi);
  final Uri odemeAdresi;
}

/// İmzası doğrulanmış sağlayıcı bildirimi.
class OdemeBildirimi {
  const OdemeBildirimi({required this.referans, required this.basarili, required this.tutarKurus, this.islemNo, this.hata});
  final String referans;
  final bool basarili;
  final int? tutarKurus;
  final String? islemNo;
  final String? hata;
}

/// Ödeme kuruluşu soyutlaması (iyzico, PayTR vb. aynı yüzeyi uygular). Kart verisi platformdan hiç geçmez.
abstract class OdemeSaglayici {
  /// Bildirim adresindeki ad: `/acik/odeme-bildirimi/<ad>`.
  String get ad;

  Future<OdemeBaslangici> baslat(OdemeIstegi istek);

  /// Bildirim gövdesindeki alanların imzasını doğrular; geçersizse null.
  OdemeBildirimi? bildirimDogrula(Map<String, String> alanlar, Map<String, String> basliklar);

  /// Sağlayıcının beklediği bildirim yanıtı (ör. PayTR düz "OK" ister).
  Response bildirimYaniti() => Response.ok('OK', headers: {'content-type': 'text/plain; charset=utf-8'});
}

/// Sabit zamanlı karşılaştırma (imza doğrulamasında zamanlama sızıntısına karşı).
bool sabitZamanliEsit(String a, String b) {
  if (a.length != b.length) return false;
  var fark = 0;
  for (var i = 0; i < a.length; i++) {
    fark |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return fark == 0;
}

String rastgeleReferans([Random? r]) {
  final rr = r ?? Random.secure();
  return List.generate(32, (_) => rr.nextInt(16).toRadixString(16)).join();
}

/// YALNIZCA GELİŞTİRME VE TEST: gerçek para çekmeyen sahte ödeme sayfası. Sunucu kendi sayfasını sunar;
/// "Öde" veya "Reddet" düğmesi gerçek sağlayıcılardaki gibi imzalı bildirim gönderir. Canlıda kapalıdır.
class SahteOdemeSaglayici extends OdemeSaglayici {
  SahteOdemeSaglayici({required this.kokAdres, required String gizli}) : _gizli = utf8.encode(gizli) {
    if (gizli.length < 16) throw ArgumentError('Sahte ödeme gizli anahtarı en az 16 karakter olmalı.');
  }

  /// Sunucunun dışarıdan erişilen adresi (ör. https://api.hukukportali.com.tr/).
  final Uri kokAdres;
  final List<int> _gizli;

  @override
  String get ad => 'sahte';

  String imza(String referans, String tutar, String durum, String islemNo) =>
      Hmac(sha256, _gizli).convert(utf8.encode('$referans|$tutar|$durum|$islemNo')).toString();

  @override
  Future<OdemeBaslangici> baslat(OdemeIstegi istek) async => OdemeBaslangici(kokAdres.resolve(
      'acik/sahte-odeme/${istek.referans}?tutar=${istek.toplamKurus}&aciklama=${Uri.encodeQueryComponent(istek.aciklama)}'));

  /// Sahte ödeme sayfası (HTML). İki form: başarılı ve başarısız bildirim.
  Response sayfa(String referans, Map<String, String> sorgu) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(referans)) return Response.notFound('Bulunamadı');
    final tutar = int.tryParse(sorgu['tutar'] ?? '') ?? 0;
    final aciklama = const HtmlEscape().convert(sorgu['aciklama'] ?? '');
    String form(String durum, String dugme) {
      final islemNo = durum == 'basarili' ? 'SAHTE-${DateTime.now().millisecondsSinceEpoch}' : '';
      final i = imza(referans, '$tutar', durum, islemNo);
      return '<form method="post" action="${kokAdres.resolve('acik/odeme-bildirimi/sahte')}">'
          '<input type="hidden" name="referans" value="$referans"><input type="hidden" name="tutar" value="$tutar">'
          '<input type="hidden" name="durum" value="$durum"><input type="hidden" name="islemNo" value="$islemNo">'
          '<input type="hidden" name="imza" value="$i"><button type="submit">$dugme</button></form>';
    }

    final tl = (tutar / 100).toStringAsFixed(2).replaceAll('.', ',');
    return Response.ok(
      '<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8"><title>Sahte ödeme (test)</title></head>'
      '<body style="font-family:sans-serif;max-width:480px;margin:40px auto">'
      '<h1>Test ödeme sayfası</h1><p><strong>Gerçek ödeme alınmaz.</strong> Bu sayfa yalnızca geliştirme ortamındadır.</p>'
      '<p>$aciklama</p><p>Tutar: <strong>$tl TL</strong></p>'
      '${form('basarili', 'Ödemeyi onayla')}<br>${form('basarisiz', 'Ödemeyi reddet')}</body></html>',
      headers: {'content-type': 'text/html; charset=utf-8', 'content-security-policy': "default-src 'none'; form-action 'self'"},
    );
  }

  @override
  OdemeBildirimi? bildirimDogrula(Map<String, String> alanlar, Map<String, String> basliklar) {
    final referans = alanlar['referans'] ?? '';
    final tutar = alanlar['tutar'] ?? '';
    final durum = alanlar['durum'] ?? '';
    final islemNo = alanlar['islemNo'] ?? '';
    if (!sabitZamanliEsit(imza(referans, tutar, durum, islemNo), alanlar['imza'] ?? '')) return null;
    return OdemeBildirimi(
      referans: referans,
      basarili: durum == 'basarili',
      tutarKurus: int.tryParse(tutar),
      islemNo: islemNo.isEmpty ? null : islemNo,
      hata: durum == 'basarili' ? null : 'Test sayfasında reddedildi',
    );
  }

  @override
  Response bildirimYaniti() => Response.ok(
        '<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8"><title>Ödeme</title></head>'
        '<body style="font-family:sans-serif;max-width:480px;margin:40px auto"><p>İşlem tamamlandı. '
        'Uygulamaya dönebilirsiniz.</p></body></html>',
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
}
