import '../hesap/hesap_turu.dart';

/// Ayrı ayrı yetkilendirilen işlemler (docs/03-yetki-modeli.md).
enum Islem {
  goruntule,
  indir,
  disaAktar,
  paylas,
  duzenle,
  onayla,
  imzala,
  gonder,
  kapat,
  yenidenAc,
  sil,
  sureTeyitEt,
  muhafazaBaslat,
  muhafazaKaldir,
  rolVer,
}

/// İkinci kişi onayı gerektiren riskli işlemler.
const Set<Islem> riskliIslemler = {Islem.sil, Islem.muhafazaKaldir, Islem.rolVer};

/// İşlemi yapmak isteyen kullanıcı.
class Aktor {
  const Aktor({
    required this.kullaniciId,
    required this.kiraciId,
    required this.roller,
    this.aktif = true,
  });

  final String kullaniciId;
  final String kiraciId;
  final Set<Rol> roller;

  /// Ayrılan veya askıya alınan kullanıcı `false`; hiçbir işlem yapamaz.
  final bool aktif;
}

/// Yetkisi denetlenen nesne (dosya, belge, sözleşme...).
class KorunanNesne {
  const KorunanNesne({
    required this.kiraciId,
    this.atananKullanicilar = const {},
    this.etikDuvar = const {},
    this.gizli = false,
  });

  final String kiraciId;

  /// Dosya ekibi; dış avukat ve müvekkil yalnızca atandıkları nesneleri görür.
  /// Gizli nesnelerde de yalnızca bu kişiler erişir.
  final Set<String> atananKullanicilar;

  /// Bu kullanıcılar nesnenin varlığını bile göremez.
  final Set<String> etikDuvar;

  final bool gizli;
}

/// Yetki kararı. `neden` denetim kaydına yazılır.
class YetkiKarari {
  const YetkiKarari._(this.izin, this.neden, {this.ikinciOnayGerekir = false});

  const YetkiKarari.izin({bool ikinciOnayGerekir = false})
      : this._(true, 'izin', ikinciOnayGerekir: ikinciOnayGerekir);

  const YetkiKarari.red(String neden) : this._(false, neden);

  final bool izin;
  final String neden;
  final bool ikinciOnayGerekir;
}

/// Tek kapı yetki denetçisi.
///
/// Liste, arama, ön izleme, rapor, Excel, API, bildirim ve yapay zekâ dahil
/// TÜM okuma ve yazma yolları bu sınıftan geçer; hiçbir kanal kendi filtresini yazmaz.
class YetkiDenetcisi {
  const YetkiDenetcisi({Map<Rol, Set<Islem>>? rolYetkileri})
      : _rolYetkileri = rolYetkileri ?? varsayilanRolYetkileri;

  final Map<Rol, Set<Islem>> _rolYetkileri;

  /// Kendi atanmış nesneleri dışında hiçbir şey göremeyen dış roller.
  static const Set<Rol> disRoller = {Rol.muvekkil, Rol.disAvukat, Rol.muhabirAvukat};

  YetkiKarari karar(Aktor aktor, Islem islem, KorunanNesne nesne) {
    if (!aktor.aktif) return const YetkiKarari.red('Kullanıcı aktif değil');
    if (aktor.kiraciId != nesne.kiraciId) return const YetkiKarari.red('Farklı müşteri ortamı');
    if (nesne.etikDuvar.contains(aktor.kullaniciId)) return const YetkiKarari.red('Etik duvar');

    final atanmis = nesne.atananKullanicilar.contains(aktor.kullaniciId);
    final yalnizcaDisRol = aktor.roller.isNotEmpty && aktor.roller.every(disRoller.contains);
    if (yalnizcaDisRol && !atanmis) return const YetkiKarari.red('Dış kullanıcıya atanmamış');
    if (nesne.gizli && !atanmis && !_tumYetkili(aktor)) {
      return const YetkiKarari.red('Gizli nesne');
    }

    final izinli = aktor.roller.any((r) => _rolYetkileri[r]?.contains(islem) ?? false);
    if (!izinli) return YetkiKarari.red('Rol "${islem.name}" işlemine izin vermiyor');

    return YetkiKarari.izin(ikinciOnayGerekir: riskliIslemler.contains(islem));
  }

  bool izinVarMi(Aktor aktor, Islem islem, KorunanNesne nesne) => karar(aktor, islem, nesne).izin;

  /// Listelerde ve aramada kullanılır: görülemeyen nesne sonuçtan tamamen çıkar.
  Iterable<T> gorunurOlanlar<T>(Aktor aktor, Iterable<T> nesneler, KorunanNesne Function(T) koruma) =>
      nesneler.where((n) => izinVarMi(aktor, Islem.goruntule, koruma(n)));

  bool _tumYetkili(Aktor aktor) => aktor.roller.any(
        (r) => r == Rol.buroSahibi || r == Rol.yoneticiOrtak || r == Rol.hukukDirektoru,
      );

  static const Set<Islem> _tumIslemler = {...Islem.values};

  static const Set<Islem> _avukatIslemleri = {
    Islem.goruntule,
    Islem.indir,
    Islem.disaAktar,
    Islem.paylas,
    Islem.duzenle,
    Islem.onayla,
    Islem.imzala,
    Islem.gonder,
    Islem.kapat,
    Islem.yenidenAc,
    Islem.sureTeyitEt,
    Islem.muhafazaBaslat,
  };

  /// Varsayılan rol → işlem matrisi. Canlıda müşteri bazında düzenlenebilir.
  static const Map<Rol, Set<Islem>> varsayilanRolYetkileri = {
    Rol.buroSahibi: _tumIslemler,
    Rol.yoneticiOrtak: _tumIslemler,
    Rol.hukukDirektoru: _tumIslemler,
    Rol.ortak: _avukatIslemleri,
    Rol.avukat: _avukatIslemleri,
    Rol.sirketAvukati: _avukatIslemleri,
    Rol.stajyer: {Islem.goruntule, Islem.indir, Islem.duzenle},
    Rol.hukukUzmani: {Islem.goruntule, Islem.indir, Islem.duzenle},
    Rol.sekreter: {Islem.goruntule, Islem.indir, Islem.duzenle},
    Rol.muhasebe: {Islem.goruntule, Islem.disaAktar},
    Rol.finansVeSatinAlma: {Islem.goruntule, Islem.onayla, Islem.disaAktar},
    Rol.onayci: {Islem.goruntule, Islem.onayla},
    Rol.talepEden: {Islem.goruntule, Islem.duzenle},
    Rol.muvekkil: {Islem.goruntule, Islem.indir},
    Rol.disAvukat: {Islem.goruntule, Islem.indir, Islem.duzenle},
    Rol.muhabirAvukat: {Islem.goruntule, Islem.indir, Islem.duzenle},
    Rol.btYoneticisi: {Islem.rolVer},
    Rol.denetci: {Islem.goruntule},
  };
}
