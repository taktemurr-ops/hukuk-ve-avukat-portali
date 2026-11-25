import 'dart:io';

/// Belge içeriklerinin saklandığı depo. Canlıda Türkiye'deki S3 uyumlu nesne deposu (şifreli) kullanılır;
/// geliştirmede ve tek sunuculu kurulumda yerel klasör.
abstract class NesneDeposu {
  Future<void> yaz(String anahtar, List<int> icerik);

  Future<List<int>> oku(String anahtar);
}

/// Yerel klasörde saklar. Anahtarlar sunucuda üretilir (kiracı/belge/sürüm kimlikleri); yine de yalnızca güvenli
/// karakterler kabul edilir ve dosya önce geçici adla yazılıp sonra taşınır (yarım dosya kalmaz).
class YerelNesneDeposu implements NesneDeposu {
  YerelNesneDeposu(this.kok);

  final String kok;

  static final _gecerli = RegExp(r'^[0-9a-f-]{36}(/[0-9a-f-]{36})*/[0-9]{1,6}$');

  File _dosya(String anahtar) {
    if (!_gecerli.hasMatch(anahtar)) throw ArgumentError('Geçersiz depo anahtarı.');
    return File('$kok/$anahtar');
  }

  @override
  Future<void> yaz(String anahtar, List<int> icerik) async {
    final d = _dosya(anahtar);
    await d.parent.create(recursive: true);
    final gecici = File('${d.path}.yukleniyor');
    await gecici.writeAsBytes(icerik, flush: true);
    await gecici.rename(d.path);
  }

  @override
  Future<List<int>> oku(String anahtar) => _dosya(anahtar).readAsBytes();
}

/// Testler için bellek içi depo.
class BellekNesneDeposu implements NesneDeposu {
  final Map<String, List<int>> icerikler = {};

  @override
  Future<void> yaz(String anahtar, List<int> icerik) async => icerikler[anahtar] = List.of(icerik);

  @override
  Future<List<int>> oku(String anahtar) async {
    final i = icerikler[anahtar];
    if (i == null) throw const FileSystemException('Nesne bulunamadı');
    return i;
  }
}
