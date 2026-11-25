import 'dart:async';

import 'package:postgres/postgres.dart';

import 'belge_servisi.dart';
import 'hata.dart';
import 'nesne_deposu.dart';
import 'veritabani.dart';

/// Yüklenen belgelerin metnini arka planda çıkarır (PDF/Word/UDF; taranmış belge ve görüntüde Türkçe OCR) ve
/// aramaya açar. İçerik depodan okunur, iç ağdaki belge servisine gönderilir; metin veritabanında belgeyle aynı
/// yetkiyle durur. Hatalı belge en çok 3 kez, saatte bir denenir (veritabanı kuralı).
class BelgeMetniGorevi {
  BelgeMetniGorevi(this.vt, this.depo, this.servis, {this.aralik = const Duration(minutes: 1), this.kaydet});

  final Veritabani vt;
  final NesneDeposu depo;
  final BelgeServisi servis;
  final Duration aralik;
  final void Function(Object hata)? kaydet;
  Timer? _zamanlayici;
  bool _calisiyor = false;

  /// Metin çıkarılmayan türler (arşiv, e-posta kutusu, tablo); boş metinle "tamam" sayılır.
  static const _atlanan = {'zip', 'eml', 'msg', 'xls', 'xlsx', 'doc', 'odt', 'rtf', 'heic'};

  void baslat() => _zamanlayici ??= Timer.periodic(aralik, (_) => birTur());

  void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  /// Bir tur: en çok 5 belge; işlenen sayısını döner.
  Future<int> birTur() async {
    if (_calisiyor) return 0;
    _calisiyor = true;
    var n = 0;
    try {
      final rs = await vt.genel((tx) => tx.execute(
          'SELECT belge_id::text, surum_no, dosya_adi, depo_anahtari FROM hukuk.metin_bekleyenler(5)'));
      for (final r in rs) {
        final belge = r[0]! as String;
        final no = r[1]! as int;
        final ad = r[2]! as String;
        var metin = '';
        var ocr = false;
        String? hata;
        final uzanti = ad.contains('.') ? ad.substring(ad.lastIndexOf('.') + 1).toLowerCase() : '';
        if (!_atlanan.contains(uzanti)) {
          try {
            final j = await servis.metin(ad, await depo.oku(r[3]! as String));
            metin = '${j['metin'] ?? ''}';
            ocr = j['ocr'] == true;
          } on ApiHatasi catch (e) {
            hata = e.mesaj;
          } on Object catch (e) {
            hata = 'Metin çıkarılamadı.';
            kaydet?.call(e);
          }
        }
        await vt.genel((tx) => tx.execute(Sql.named('SELECT hukuk.belge_metni_kaydet(CAST(@b AS uuid), @n, @m, @o, @h)'),
            parameters: {'b': belge, 'n': no, 'm': metin, 'o': ocr, 'h': hata}));
        n++;
      }
    } on Object catch (e) {
      kaydet?.call(e);
    } finally {
      _calisiyor = false;
    }
    return n;
  }
}
