import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

/// Kayıt sihirbazında toplanan bilgiler.
class KayitBilgileri {
  const KayitBilgileri({
    required this.hesapTuru,
    required this.adSoyad,
    required this.kurumAdi,
    required this.eposta,
    required this.telefon,
    required this.sifre,
    required this.faturaUnvani,
    required this.tcknVeyaVkn,
    required this.vergiDairesi,
    required this.faturaAdresi,
    required this.ticariIletiIzni,
    required this.onayZamani,
  });

  final HesapTuru hesapTuru;
  final String adSoyad;

  /// Büro veya şirket adı.
  final String kurumAdi;
  final String eposta;
  final String telefon;
  final String sifre;
  final String faturaUnvani;
  final String tcknVeyaVkn;
  final String vergiDairesi;
  final String faturaAdresi;

  /// İYS kapsamında ticari elektronik ileti izni (isteğe bağlı).
  final bool ticariIletiIzni;

  /// Kullanım koşulları, abonelik sözleşmesi ve KVKK aydınlatma metninin onaylandığı an.
  final DateTime onayZamani;
}

/// Oturum açmış kullanıcı.
class Oturum {
  const Oturum({
    required this.kullaniciId,
    required this.kiraciId,
    required this.adSoyad,
    required this.eposta,
    required this.kurumAdi,
    required this.hesapTuru,
    required this.roller,
    this.muvekkilKisiId,
  });

  final String kullaniciId;
  final String kiraciId;
  final String adSoyad;
  final String eposta;
  final String kurumAdi;
  final HesapTuru hesapTuru;
  final Set<Rol> roller;

  /// Müvekkil portalı oturumunda, büro kayıtlarındaki müvekkil kişi kimliği.
  final String? muvekkilKisiId;

  bool get muvekkilPortali => muvekkilKisiId != null;

  LisansProfili get lisans => LisansProfili.varsayilan(hesapTuru);
}

class KimlikHatasi implements Exception {
  const KimlikHatasi(this.mesaj);

  final String mesaj;

  @override
  String toString() => mesaj;
}

/// Kimlik işlemleri. Sunucu (Serverpod) hazır olduğunda gerçek uygulaması yazılacak;
/// ekranlar yalnızca bu arayüze bağlıdır.
abstract class KimlikServisi {
  Oturum? get oturum;

  /// [kiraciId]: aynı e-postayla birden çok kurumda hesap varsa seçilen kurum.
  /// [ikiAdimliKod]: iki adımlı doğrulama açıksa doğrulayıcı uygulamadaki 6 haneli kod.
  Future<Oturum> girisYap({required String eposta, required String sifre, String? kiraciId, String? ikiAdimliKod});

  Future<void> cikisYap();

  /// Hesabı ve 14 günlük denemeyi başlatır, aktivasyon e-postası gönderir.
  Future<void> kayitOl(KayitBilgileri bilgiler);

  /// Güvenlik gereği e-posta kayıtlı olsun olmasın aynı yanıtı verir.
  Future<void> sifreSifirlamaIste(String eposta);

  /// E-postadaki kodla yeni şifre belirler; geçersiz/süresi dolmuş kodda [KimlikHatasi].
  Future<void> sifreSifirla({required String kod, required String yeniSifre});

  /// Kayıt olmadan, örnek verilerle salt deneme oturumu. Demo verisi kalıcı değildir.
  Future<Oturum> demoGiris(HesapTuru tur);

  /// Müvekkil portalını örnek müvekkil olarak dener.
  Future<Oturum> demoMuvekkilGiris();

  /// Davet bağlantısındaki kodla hesap açar (şifreyi kişi kendisi belirler). Ardından normal giriş yapılır.
  Future<void> davetKabul({required String kod, required String eposta, required String adSoyad, required String sifre});
}

/// Yalnızca geliştirme ve demo için bellekte çalışan kimlik servisi.
///
/// Gerçek sunucuda şifreler Argon2 ile özetlenir, hesap e-posta doğrulanana kadar
/// pasif kalır ve deneme sayısı sunucuda tutulur.
class BellekKimlikServisi implements KimlikServisi {
  final Map<String, _Kayit> _kayitlar = {};
  final Map<String, int> _hataliDenemeler = {};
  Oturum? _oturum;
  int _sayac = 0;

  static const int azamiHataliDeneme = 5;

  @override
  Oturum? get oturum => _oturum;

  @override
  Future<void> kayitOl(KayitBilgileri bilgiler) async {
    final eposta = bilgiler.eposta.trim().toLowerCase();
    if (_kayitlar.containsKey(eposta)) {
      throw const KimlikHatasi('Bu e-posta adresiyle kayıtlı bir hesap var.');
    }
    _sayac++;
    _kayitlar[eposta] = _Kayit(
      sifre: bilgiler.sifre,
      oturum: Oturum(
        kullaniciId: 'k$_sayac',
        kiraciId: 'kiraci$_sayac',
        adSoyad: bilgiler.adSoyad.trim(),
        eposta: eposta,
        kurumAdi: bilgiler.kurumAdi.trim(),
        hesapTuru: bilgiler.hesapTuru,
        roller: {_kurucuRol(bilgiler.hesapTuru)},
      ),
    );
  }

  @override
  Future<Oturum> girisYap({required String eposta, required String sifre, String? kiraciId, String? ikiAdimliKod}) async {
    final anahtar = eposta.trim().toLowerCase();
    final hatali = _hataliDenemeler[anahtar] ?? 0;
    if (hatali >= azamiHataliDeneme) {
      throw const KimlikHatasi('Çok sayıda hatalı deneme. Hesabınız geçici olarak kilitlendi.');
    }
    final kayit = _kayitlar[anahtar];
    if (kayit == null || kayit.sifre != sifre) {
      _hataliDenemeler[anahtar] = hatali + 1;
      throw const KimlikHatasi('E-posta veya şifre hatalı.');
    }
    _hataliDenemeler.remove(anahtar);
    return _oturum = kayit.oturum;
  }

  @override
  Future<void> cikisYap() async => _oturum = null;

  @override
  Future<void> sifreSifirlamaIste(String eposta) async {}

  @override
  Future<void> sifreSifirla({required String kod, required String yeniSifre}) async =>
      throw const KimlikHatasi('Demo modunda şifre sıfırlanamaz.');

  @override
  Future<void> davetKabul({required String kod, required String eposta, required String adSoyad, required String sifre}) async {
    throw const KimlikHatasi('Davet kabulü sunucu bağlantısıyla çalışır; demo sürümünde kullanılamaz.');
  }

  @override
  Future<Oturum> demoGiris(HesapTuru tur) async {
    _sayac++;
    return _oturum = Oturum(
      kullaniciId: 'demo$_sayac',
      kiraciId: 'demo-kiraci$_sayac',
      adSoyad: 'Demo Kullanıcı',
      eposta: 'demo@hukukportali.com.tr',
      kurumAdi: switch (tur) {
        HesapTuru.avukatlikBurosu => 'Demo Avukatlık Bürosu',
        HesapTuru.hukukBurosu => 'Demo Hukuk Bürosu',
        HesapTuru.kurumsal => 'Demo Holding A.Ş.',
      },
      hesapTuru: tur,
      roller: {_kurucuRol(tur)},
    );
  }

  @override
  Future<Oturum> demoMuvekkilGiris() async {
    _sayac++;
    return _oturum = Oturum(
      kullaniciId: 'mvk$_sayac',
      kiraciId: 'demo-kiraci$_sayac',
      adSoyad: 'Can Demir (ABC Gıda yetkilisi)',
      eposta: 'can.demir@abcgida.com.tr',
      kurumAdi: 'Demo Hukuk Bürosu',
      hesapTuru: HesapTuru.hukukBurosu,
      roller: const {Rol.muvekkil},
      muvekkilKisiId: 'abc',
    );
  }

  static Rol _kurucuRol(HesapTuru tur) => switch (tur) {
        HesapTuru.avukatlikBurosu => Rol.buroSahibi,
        HesapTuru.hukukBurosu => Rol.yoneticiOrtak,
        HesapTuru.kurumsal => Rol.hukukDirektoru,
      };
}

class _Kayit {
  _Kayit({required this.sifre, required this.oturum});

  final String sifre;
  final Oturum oturum;
}
