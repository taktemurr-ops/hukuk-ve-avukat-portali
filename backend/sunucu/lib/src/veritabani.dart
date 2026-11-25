import 'package:postgres/postgres.dart';

import 'hata.dart';

/// Oturumu doğrulanmış kullanıcının bağlamı.
class KimlikBaglami {
  const KimlikBaglami({required this.kullaniciId, required this.kiraciId, this.portalKisiId});

  final String kullaniciId;
  final String kiraciId;

  /// Müvekkil portalı oturumunda bağlı kişi kartı; büro kullanıcılarında boş.
  final String? portalKisiId;

  bool get portal => portalKisiId != null;
}

/// Veritabanı erişimi. Uygulama `hukuk_uygulama` rolünün üyesi olan bir kullanıcıyla bağlanır;
/// tablo sahibi olmadığı için satır düzeyi güvenlik (RLS) her sorguda uygulanır.
class Veritabani {
  Veritabani(this.havuz);

  final Pool<void> havuz;

  factory Veritabani.ortamdan(Map<String, String> ortam) => Veritabani(Pool.withEndpoints(
        [
          Endpoint(
            host: ortam['PG_HOST'] ?? 'localhost',
            port: int.parse(ortam['PG_PORT'] ?? '5432'),
            database: ortam['PG_VERITABANI'] ?? 'hukuk',
            username: ortam['PG_KULLANICI'] ?? 'hukuk_api',
            password: ortam['PG_SIFRE'],
          ),
        ],
        settings: PoolSettings(
          maxConnectionCount: int.parse(ortam['PG_HAVUZ'] ?? '10'),
          sslMode: ortam['PG_SSL'] == 'kapali' ? SslMode.disable : SslMode.require,
        ),
      ));

  /// Kiracı bağlamı olmadan (giriş öncesi) işlem; yalnızca SECURITY DEFINER fonksiyonlarına erişir.
  Future<T> genel<T>(Future<T> Function(TxSession tx) islem) => _hataCevir(() => havuz.runTx(islem));

  /// Kullanıcı adına işlem. Kiracı ve kullanıcı yalnızca bu işlem için ayarlanır (`set_config(..., true)`),
  /// böylece havuzdaki bağlantı başka bir isteğe bağlam taşımaz.
  ///
  /// Portal (müvekkil) oturumları büro verisine bu yoldan hiç erişemez.
  Future<T> kiraciIcin<T>(KimlikBaglami k, Future<T> Function(TxSession tx) islem) {
    if (k.portal) throw const ApiHatasi(403, 'Bu işlem müvekkil portalında kullanılamaz.', kod: 'yasak');
    return _kiraciIcin(k, islem);
  }

  /// Müvekkil portalı işlemi: kiracı ayarlanmaz (büro tablolarının satır politikaları hiçbir şey döndürmez);
  /// yalnızca portal kişisi ve kullanıcısı ayarlanır, erişim SECURITY DEFINER portal fonksiyonlarıyla yapılır.
  Future<T> portalIcin<T>(KimlikBaglami k, Future<T> Function(TxSession tx) islem) {
    final kisi = k.portalKisiId;
    if (kisi == null) throw const ApiHatasi(403, 'Bu uç yalnızca müvekkil portalı içindir.', kod: 'yasak');
    return _hataCevir(() => havuz.runTx((tx) async {
          await tx.execute(
            Sql.named("SELECT set_config('app.kiraci_id', '', true), set_config('app.kullanici_id', @u, true), "
                "set_config('app.portal_kisi', @p, true)"),
            parameters: {'u': k.kullaniciId, 'p': kisi},
          );
          return islem(tx);
        }));
  }

  Future<T> _kiraciIcin<T>(KimlikBaglami k, Future<T> Function(TxSession tx) islem) => _hataCevir(() => havuz.runTx((tx) async {
            await tx.execute(
              Sql.named("SELECT set_config('app.kiraci_id', @k, true), set_config('app.kullanici_id', @u, true), "
                  "set_config('app.portal_kisi', '', true)"),
              parameters: {'k': k.kiraciId, 'u': k.kullaniciId},
            );
            return islem(tx);
          }));

  /// Veritabanı kısıtlarını kullanıcıya anlamlı hatalara çevirir.
  static Future<T> _hataCevir<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ServerException catch (e) {
      switch (e.code) {
        case '23514': // check_violation (tetikleyicilerin Türkçe iletileri dahil)
          throw ApiHatasi(409, _kisitIletisi(e), kod: 'kural_ihlali');
        case '23505':
          throw const ApiHatasi(409, 'Bu kayıt zaten var.', kod: 'mukerrer');
        case '23503':
          throw const ApiHatasi(409, 'İlişkili kayıt bulunamadı.', kod: 'iliski');
        case '42501':
          throw const ApiHatasi(403, 'Bu işlem için yetkiniz yok.', kod: 'yasak');
        case 'P0002': // no_data_found (ör. bulunmayan ihbar formu)
          throw ApiHatasi(404, e.message, kod: 'bulunamadi');
        case '22023': // invalid_parameter_value (ör. geçersiz/süresi dolmuş sıfırlama bağlantısı)
          throw ApiHatasi(400, e.message, kod: 'gecersiz_istek');
        case '22P02':
          throw const ApiHatasi(400, 'Geçersiz değer.', kod: 'gecersiz_istek');
        default:
          rethrow;
      }
    }
  }

  static const _kisitlar = {
    'sure_kaydi_check1': 'Asıl ve yedek sorumlu aynı kişi olamaz.',
    'sure_kaydi_check2': 'Hesabı yapan kendi süresini teyit edemez.',
    'sure_kaydi_check3': 'Teyitli süre için teyit eden belirtilmeli.',
    'sure_kaydi_check4': 'Tamamlanan süre için kanıt (UYAP gönderim no, makbuz…) girilmeli.',
    'dosya_check': 'Yedek sorumlu, asıl sorumludan farklı olmalıdır.',
  };

  static String _kisitIletisi(ServerException e) {
    final ad = e.constraintName;
    if (ad != null && _kisitlar.containsKey(ad)) return _kisitlar[ad]!;
    // Tetikleyicilerden gelen RAISE EXCEPTION iletileri zaten Türkçe ve kullanıcıya uygundur.
    if (ad == null && e.message.isNotEmpty) return e.message;
    return 'İşlem veri kurallarına uymuyor.';
  }
}
