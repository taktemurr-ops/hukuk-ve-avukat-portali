import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'kimlik_servisi.dart';

/// Aynı e-postayla birden çok kurumda hesap varsa kullanıcı kurum seçer.
class KurumSecimiGerekli implements Exception {
  const KurumSecimiGerekli(this.kurumlar);

  /// kiraciId → kurum adı
  final Map<String, String> kurumlar;
}

/// Şifre doğru; hesapta iki adımlı doğrulama açık, 6 haneli kod gerekiyor.
class IkiAdimliGerekli implements Exception {
  const IkiAdimliGerekli();
}

/// Gerçek sunucuya bağlanan kimlik servisi. Demo girişi bellekte kalır (sunucuya veri yazmaz).
class SunucuKimlikServisi implements KimlikServisi {
  SunucuKimlikServisi(this.api, {KimlikServisi? demo}) : _demo = demo ?? BellekKimlikServisi();

  final ApiIstemcisi api;
  final KimlikServisi _demo;
  Oturum? _oturum;

  /// Sunucu oturumu mu (demo değil).
  bool get sunucuOturumu => _oturum != null && api.token != null;

  @override
  Oturum? get oturum => _oturum;

  @override
  Future<Oturum> girisYap({required String eposta, required String sifre, String? kiraciId, String? ikiAdimliKod}) async {
    try {
      final y = await api.post('/giris', {
        'eposta': eposta,
        'sifre': sifre,
        if (kiraciId != null) 'kiraciId': kiraciId,
        if (ikiAdimliKod != null) 'ikiAdimliKod': ikiAdimliKod,
      }) as Map<String, dynamic>;
      if (y['ikiAdimliGerekli'] == true) throw const IkiAdimliGerekli();
      final secenekler = y['kurumSecin'];
      if (secenekler is List) {
        throw KurumSecimiGerekli({
          for (final k in secenekler.cast<Map<String, dynamic>>()) k['kiraciId'] as String: k['ad'] as String,
        });
      }
      api.token = y['token'] as String;
      final ben = await api.get('/ben') as Map<String, dynamic>;
      return _oturum = Oturum(
        kullaniciId: ben['kullaniciId'] as String,
        kiraciId: ben['kiraciId'] as String,
        adSoyad: ben['adSoyad'] as String,
        eposta: ben['eposta'] as String,
        kurumAdi: ben['kurumAdi'] as String,
        hesapTuru: HesapTuru.values.byName(ben['hesapTuru'] as String),
        roller: {
          for (final r in (ben['roller'] as List).cast<String>())
            if (Rol.values.any((x) => x.name == r)) Rol.values.byName(r),
        },
        // Müvekkil oturumunda sunucu bağlı kişi kartını döner; uygulama portal görünümünü açar.
        muvekkilKisiId: ben['portalKisiId'] as String?,
      );
    } on SunucuHatasi catch (e) {
      throw KimlikHatasi(e.mesaj);
    }
  }

  @override
  Future<void> cikisYap() async {
    if (api.token != null) {
      try {
        await api.post('/cikis');
      } on Exception {
        // Ağ hatasında da yerel oturum kapanır; sunucudaki oturum süresi dolunca geçersizleşir.
      }
    }
    api.token = null;
    _oturum = null;
    await _demo.cikisYap();
  }

  @override
  Future<void> kayitOl(KayitBilgileri bilgiler) async {
    try {
      await api.post('/kayit', {
        'kurumAdi': bilgiler.kurumAdi,
        'hesapTuru': bilgiler.hesapTuru.name,
        'eposta': bilgiler.eposta,
        'sifre': bilgiler.sifre,
        'adSoyad': bilgiler.adSoyad,
      });
    } on SunucuHatasi catch (e) {
      throw KimlikHatasi(e.mesaj);
    }
  }

  @override
  Future<void> davetKabul({required String kod, required String eposta, required String adSoyad, required String sifre}) async {
    try {
      await api.post('/acik/davet-kabul', {'kod': kod.trim(), 'eposta': eposta.trim(), 'adSoyad': adSoyad.trim(), 'sifre': sifre});
    } on SunucuHatasi catch (e) {
      throw KimlikHatasi(e.mesaj);
    }
  }

  @override
  Future<void> sifreSifirlamaIste(String eposta) async {
    // Sunucu ucu e-posta altyapısıyla gelecek; kullanıcıya her durumda aynı yanıt verilir.
  }

  @override
  Future<Oturum> demoGiris(HesapTuru tur) => _demo.demoGiris(tur);

  @override
  Future<Oturum> demoMuvekkilGiris() => _demo.demoMuvekkilGiris();
}
