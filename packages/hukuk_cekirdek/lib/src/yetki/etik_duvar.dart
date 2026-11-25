import '../takvim/tarih.dart';

/// Bir kullanıcının bir dosyadan etik duvarla ayrılması. Kayıtlar silinmez; kaldırma da kayıt altına alınır.
class EtikDuvarKaydi {
  EtikDuvarKaydi({
    required this.dosyaId,
    required this.kullanici,
    required this.gerekce,
    required this.kuran,
    required this.tarih,
  });

  final String dosyaId;
  final String kullanici;
  final String gerekce;
  final String kuran;
  final Tarih tarih;
  String? kaldiran;
  String? kaldirmaGerekcesi;
  Tarih? kaldirmaTarihi;

  bool get aktif => kaldiran == null;
}

class EtikDuvarDefteri {
  final List<EtikDuvarKaydi> _kayitlar = [];

  static const asgariGerekce = 10;

  /// Sunucudan gelen kayıtlarla önbelleği değiştirir.
  void yukle(Iterable<EtikDuvarKaydi> kayitlar) {
    _kayitlar
      ..clear()
      ..addAll(kayitlar);
  }

  /// Dosyadan şu an engellenmiş kullanıcılar.
  Set<String> engelliler(String dosyaId) =>
      {for (final k in _kayitlar) if (k.dosyaId == dosyaId && k.aktif) k.kullanici};

  List<EtikDuvarKaydi> gecmis(String dosyaId) => _kayitlar.where((k) => k.dosyaId == dosyaId).toList();

  /// Dosya ekibindeki kişi önce ekipten çıkarılmalıdır; kişi kendine duvar kuramaz.
  EtikDuvarKaydi kur({
    required String dosyaId,
    required String kullanici,
    required String gerekce,
    required String kuran,
    required Tarih tarih,
    required Set<String> dosyaEkibi,
  }) {
    if (gerekce.trim().length < asgariGerekce) throw ArgumentError('Gerekçe en az $asgariGerekce karakter olmalı.');
    if (kullanici == kuran) throw ArgumentError('Kendinize etik duvar kuramazsınız.');
    if (dosyaEkibi.contains(kullanici)) throw StateError('Kullanıcı dosya ekibinde; önce ekipten çıkarılmalı.');
    if (engelliler(dosyaId).contains(kullanici)) throw StateError('Bu kullanıcı için etik duvar zaten var.');
    final k = EtikDuvarKaydi(dosyaId: dosyaId, kullanici: kullanici, gerekce: gerekce.trim(), kuran: kuran, tarih: tarih);
    _kayitlar.add(k);
    return k;
  }

  void kaldir({
    required String dosyaId,
    required String kullanici,
    required String gerekce,
    required String kaldiran,
    required Tarih tarih,
  }) {
    if (gerekce.trim().length < asgariGerekce) throw ArgumentError('Gerekçe en az $asgariGerekce karakter olmalı.');
    if (kullanici == kaldiran) throw ArgumentError('Kendi etik duvarınızı kaldıramazsınız.');
    EtikDuvarKaydi? k;
    for (final x in _kayitlar) {
      if (x.dosyaId == dosyaId && x.kullanici == kullanici && x.aktif) k = x;
    }
    if (k == null) throw StateError('Etkin etik duvar bulunamadı.');
    k
      ..kaldiran = kaldiran
      ..kaldirmaGerekcesi = gerekce.trim()
      ..kaldirmaTarihi = tarih;
  }
}
