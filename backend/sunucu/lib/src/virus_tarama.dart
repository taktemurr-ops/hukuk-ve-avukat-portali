import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Tarama sonucu: temizse [bulgu] boştur.
class VirusTaramaSonucu {
  const VirusTaramaSonucu.temiz() : bulgu = null;
  const VirusTaramaSonucu.zararli(String this.bulgu);

  final String? bulgu;
  bool get temiz => bulgu == null;
}

/// Yüklenen dosyaların zararlı yazılım taraması.
abstract class VirusTarayici {
  /// Tarayıcıya ulaşılamazsa veya yanıt anlaşılamazsa hata fırlatır (dosya kabul edilmez).
  Future<VirusTaramaSonucu> tara(List<int> icerik);
}

/// ClamAV (clamd) INSTREAM protokolü: içerik parçalar hâlinde gönderilir, yanıt "stream: OK" veya
/// "stream: <imza> FOUND" olur. clamd aynı yurt içi ağda, yalnızca iç ağdan erişilebilir çalışmalıdır.
class ClamdTarayici implements VirusTarayici {
  ClamdTarayici(this.sunucu, this.port, {this.zamanAsimi = const Duration(seconds: 60)});

  final String sunucu;
  final int port;
  final Duration zamanAsimi;

  static const _parca = 64 * 1024;

  /// Yanıtı yorumlar (test edilebilirlik için ayrı).
  static VirusTaramaSonucu yanitCoz(String yanit) {
    final y = yanit.replaceAll('\u0000', '').trim();
    if (y.endsWith(': OK')) return const VirusTaramaSonucu.temiz();
    final m = RegExp(r':\s*(.+)\s+FOUND$').firstMatch(y);
    if (m != null) return VirusTaramaSonucu.zararli(m.group(1)!);
    throw StateError('Virüs tarayıcısı beklenmeyen yanıt verdi: $y');
  }

  /// INSTREAM çerçeveleri: her parçanın önünde 4 baytlık (big-endian) uzunluk, sonda sıfır uzunluk.
  static List<Uint8List> cerceveler(List<int> icerik) {
    final sonuc = <Uint8List>[Uint8List.fromList(utf8.encode('zINSTREAM\u0000'))];
    for (var i = 0; i < icerik.length; i += _parca) {
      final son = (i + _parca < icerik.length) ? i + _parca : icerik.length;
      final uzunluk = ByteData(4)..setUint32(0, son - i);
      sonuc
        ..add(uzunluk.buffer.asUint8List())
        ..add(Uint8List.fromList(icerik.sublist(i, son)));
    }
    sonuc.add(Uint8List(4));
    return sonuc;
  }

  @override
  Future<VirusTaramaSonucu> tara(List<int> icerik) async {
    final soket = await Socket.connect(sunucu, port, timeout: const Duration(seconds: 10));
    try {
      for (final c in cerceveler(icerik)) {
        soket.add(c);
      }
      await soket.flush();
      final yanit = await soket.cast<List<int>>().transform(utf8.decoder).join().timeout(zamanAsimi);
      return yanitCoz(yanit);
    } finally {
      soket.destroy();
    }
  }
}
