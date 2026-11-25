import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../takvim/tarih.dart';

/// Yüklenmesine izin verilen dosya türleri. Çalıştırılabilir dosyalar kabul edilmez.
const Set<String> izinliUzantilar = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'udf', 'txt', 'rtf', 'odt',
  'jpg', 'jpeg', 'png', 'tif', 'tiff', 'heic',
  'eml', 'msg', 'zip',
};

/// Tek dosya için azami boyut (bayt).
const int azamiBoyut = 200 * 1024 * 1024;

String sha256Ozeti(List<int> baytlar) => sha256.convert(baytlar).toString();

String metinOzeti(String metin) => sha256Ozeti(utf8.encode(metin));

/// Yükleme öncesi kontrol; hata yoksa `null`. Zararlı içerik taraması sunucuda ayrıca yapılır.
String? yuklemeKontrol({required String dosyaAdi, required int boyut}) {
  final nokta = dosyaAdi.lastIndexOf('.');
  if (nokta < 0 || nokta == dosyaAdi.length - 1) return 'Dosya uzantısı bulunamadı.';
  final uzanti = dosyaAdi.substring(nokta + 1).toLowerCase();
  if (!izinliUzantilar.contains(uzanti)) return '".$uzanti" türündeki dosyalar yüklenemez.';
  if (boyut <= 0) return 'Dosya boş.';
  if (boyut > azamiBoyut) return 'Dosya ${azamiBoyut ~/ (1024 * 1024)} MB sınırını aşıyor.';
  return null;
}

enum BelgeTuru { dilekce, karar, tebligat, delil, sozlesme, vekaletname, makbuz, yazisma, diger }

class BelgeSurumu {
  const BelgeSurumu({
    required this.no,
    required this.ozet,
    required this.boyut,
    required this.yukleyen,
    required this.tarih,
    required this.dosyaAdi,
    this.aciklama,
  });

  final int no;

  /// SHA-256; bütünlük ve delil teslim zinciri için.
  final String ozet;
  final int boyut;
  final String yukleyen;
  final Tarih tarih;
  final String dosyaAdi;
  final String? aciklama;
}

/// Sürümleri saklanan belge. İlk sürüm "orijinal" kabul edilir ve değiştirilemez.
class Belge {
  Belge({
    required this.id,
    required this.kiraciId,
    required this.ad,
    required this.tur,
    required BelgeSurumu ilkSurum,
    this.dosyaId,
    this.gizli = false,
    this.fizikselYer,
  }) : _surumler = [ilkSurum];

  final String id;
  final String kiraciId;
  final String ad;
  final BelgeTuru tur;
  final String? dosyaId;
  final bool gizli;

  /// Asıl evrak fiziksel olarak saklanıyorsa yeri.
  final String? fizikselYer;
  final List<BelgeSurumu> _surumler;

  List<BelgeSurumu> get surumler => List.unmodifiable(_surumler);
  BelgeSurumu get orijinal => _surumler.first;
  BelgeSurumu get guncel => _surumler.last;

  /// Yeni çalışma sürümü ekler. Aynı içerik ikinci kez eklenmez.
  BelgeSurumu yeniSurum({required String ozet, required int boyut, required String yukleyen, required Tarih tarih, required String dosyaAdi, String? aciklama}) {
    if (_surumler.any((s) => s.ozet == ozet)) {
      throw StateError('Bu içerik zaten sürüm ${_surumler.firstWhere((s) => s.ozet == ozet).no} olarak kayıtlı.');
    }
    final s = BelgeSurumu(
      no: guncel.no + 1,
      ozet: ozet,
      boyut: boyut,
      yukleyen: yukleyen,
      tarih: tarih,
      dosyaAdi: dosyaAdi,
      aciklama: aciklama,
    );
    _surumler.add(s);
    return s;
  }

  /// İndirilen veya ibraz edilen dosyanın kayıtlı sürümle birebir aynı olup olmadığı.
  BelgeSurumu? butunlukDogrula(String ozet) {
    for (final s in _surumler) {
      if (s.ozet == ozet) return s;
    }
    return null;
  }
}
