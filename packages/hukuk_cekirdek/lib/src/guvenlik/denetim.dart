import 'dart:convert';

import 'package:crypto/crypto.dart';

enum DenetimIslemi {
  girisBasarili('Giriş'),
  girisBasarisiz('Başarısız giriş'),
  goruntuleme('Görüntüleme'),
  indirme('İndirme'),
  disaAktarma('Dışa aktarma'),
  paylasim('Paylaşım'),
  olusturma('Oluşturma'),
  degisiklik('Değişiklik'),
  silme('Silme'),
  rolVerme('Rol verme'),
  sureTeyit('Süre teyidi'),
  kararKaydi('Karar'),
  destekErisimi('Destek erişimi'),
  aktarim('Veri aktarımı');

  const DenetimIslemi(this.ad);

  final String ad;
}

/// Değiştirilemez denetim olayı. Her olay bir öncekinin özetini taşır (hash zinciri);
/// aradaki bir kayıt silinir veya değiştirilirse zincir kırılır.
class DenetimOlayi {
  const DenetimOlayi({
    required this.sira,
    required this.zaman,
    required this.kiraciId,
    required this.kullaniciId,
    required this.islem,
    required this.nesneTuru,
    required this.nesneId,
    required this.aciklama,
    required this.oncekiOzet,
    required this.ozet,
  });

  final int sira;

  /// UTC
  final DateTime zaman;
  final String kiraciId;
  final String kullaniciId;
  final DenetimIslemi islem;
  final String nesneTuru;
  final String nesneId;
  final String aciklama;
  final String oncekiOzet;
  final String ozet;

  static const String baslangicOzeti = '0000000000000000000000000000000000000000000000000000000000000000';

  static String ozetHesapla({
    required int sira,
    required DateTime zaman,
    required String kiraciId,
    required String kullaniciId,
    required DenetimIslemi islem,
    required String nesneTuru,
    required String nesneId,
    required String aciklama,
    required String oncekiOzet,
  }) {
    final govde = jsonEncode([
      oncekiOzet,
      sira,
      zaman.toUtc().toIso8601String(),
      kiraciId,
      kullaniciId,
      islem.name,
      nesneTuru,
      nesneId,
      aciklama,
    ]);
    return sha256.convert(utf8.encode(govde)).toString();
  }

  String yenidenHesapla() => ozetHesapla(
        sira: sira,
        zaman: zaman,
        kiraciId: kiraciId,
        kullaniciId: kullaniciId,
        islem: islem,
        nesneTuru: nesneTuru,
        nesneId: nesneId,
        aciklama: aciklama,
        oncekiOzet: oncekiOzet,
      );
}

/// Yalnızca ekleme yapılabilen denetim kaydı.
class DenetimKaydi {
  final List<DenetimOlayi> _olaylar = [];

  List<DenetimOlayi> get olaylar => List.unmodifiable(_olaylar);

  DenetimOlayi ekle({
    required String kiraciId,
    required String kullaniciId,
    required DenetimIslemi islem,
    required String nesneTuru,
    required String nesneId,
    String aciklama = '',
    DateTime? zaman,
  }) {
    final onceki = _olaylar.isEmpty ? DenetimOlayi.baslangicOzeti : _olaylar.last.ozet;
    final sira = _olaylar.length + 1;
    final z = (zaman ?? DateTime.now()).toUtc();
    final olay = DenetimOlayi(
      sira: sira,
      zaman: z,
      kiraciId: kiraciId,
      kullaniciId: kullaniciId,
      islem: islem,
      nesneTuru: nesneTuru,
      nesneId: nesneId,
      aciklama: aciklama,
      oncekiOzet: onceki,
      ozet: DenetimOlayi.ozetHesapla(
        sira: sira,
        zaman: z,
        kiraciId: kiraciId,
        kullaniciId: kullaniciId,
        islem: islem,
        nesneTuru: nesneTuru,
        nesneId: nesneId,
        aciklama: aciklama,
        oncekiOzet: onceki,
      ),
    );
    _olaylar.add(olay);
    return olay;
  }

  /// Zincir sağlamsa `null`, değilse ilk bozuk olayın sıra numarası.
  static int? zinciriDogrula(List<DenetimOlayi> olaylar) {
    var onceki = DenetimOlayi.baslangicOzeti;
    for (var i = 0; i < olaylar.length; i++) {
      final o = olaylar[i];
      if (o.sira != i + 1 || o.oncekiOzet != onceki || o.yenidenHesapla() != o.ozet) return i + 1;
      onceki = o.ozet;
    }
    return null;
  }

  int? dogrula() => zinciriDogrula(_olaylar);
}
