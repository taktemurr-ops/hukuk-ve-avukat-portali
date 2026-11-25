import '../takvim/tarih.dart';
import '../takvim/tatil_takvimi.dart';
import 'onay_durumu.dart';
import 'sure_kurali.dart';

/// Hesaplayıcının davranışını belirleyen ayarlar.
///
/// Tartışmalı noktalar ayar olarak bırakılmıştır; varsayılanlar avukat onayı bekler.
class HesapAyarlari {
  const HesapAyarlari({
    this.haftaSonuTatil = true,
    this.yarimGunTatilErtelerMi = false,
    this.adliTatilBaslangicAyGun = const (7, 20),
    this.adliTatilBitisAyGun = const (8, 31),
    this.adliTatilUzamaGun = 7,
    this.taslakKuralaIzinVer = false,
  });

  /// Cumartesi ve pazar tatil sayılır mı (son gün ertesi iş gününe kayar).
  final bool haftaSonuTatil;

  /// Son gün yarım gün tatile (arife) denk gelirse ertesi iş gününe kayar mı.
  /// ONAY BEKLİYOR: uygulama ve içtihat avukat tarafından netleştirilecek.
  final bool yarimGunTatilErtelerMi;

  /// Adli tatil başlangıcı (ay, gün). HMK m.102: 20 Temmuz.
  final (int, int) adliTatilBaslangicAyGun;

  /// Adli tatil bitişi (ay, gün). HMK m.102: 31 Ağustos.
  final (int, int) adliTatilBitisAyGun;

  /// Adli tatile denk gelen sürenin bitişten itibaren uzayacağı gün sayısı (HMK m.104: bir hafta).
  final int adliTatilUzamaGun;

  /// Test ve demo için taslak kurallarla hesaba izin verir. Canlıda `false` olmalıdır.
  final bool taslakKuralaIzinVer;
}

/// Hesabın her adımı; kullanıcıya ve denetim kaydına gösterilir.
class HesapAdimi {
  const HesapAdimi(this.tarih, this.aciklama);

  final Tarih tarih;
  final String aciklama;

  @override
  String toString() => '${tarih.turkceBicim}: $aciklama';
}

/// Süre hesabının sonucu.
class SureSonucu {
  const SureSonucu({
    required this.kural,
    required this.baslangic,
    required this.sonGun,
    required this.adimlar,
    required this.uyarilar,
  });

  final SureKurali kural;

  /// Sürenin başladığı olay tarihi (ör. tebliğ tarihi). Bu gün hesaba katılmaz.
  final Tarih baslangic;

  /// İşlemin yapılabileceği son gün.
  final Tarih sonGun;

  /// Hesabın gerekçesi, adım adım.
  final List<HesapAdimi> adimlar;

  /// Kullanıcının dikkat etmesi gereken durumlar (taslak kural, eksik tatil verisi vb.).
  final List<String> uyarilar;

  /// Hukukçunun teyidi gerekir mi. Her kritik süre en az bir kişi tarafından teyit edilir.
  bool get teyitGerekir => true;
}

/// Kural bazlı süre hesaplayıcı.
///
/// Uygulanan genel ilkeler (HMK m.92-93, m.102-104; avukat onayı bekler):
/// 1. Gün olarak belirlenen sürede başlangıç günü hesaba katılmaz.
/// 2. Hafta, ay veya yıl olarak belirlenen süre, karşılık gelen günde biter;
///    o ayda karşılık gelen gün yoksa ayın son günü esas alınır.
/// 3. Adli tatile tabi sürenin sonu adli tatile denk gelirse,
///    adli tatilin bittiği günden itibaren bir hafta uzar.
/// 4. Son gün tatile denk gelirse ilk iş gününe kayar.
class SureHesaplayici {
  SureHesaplayici(this.takvim, {this.ayarlar = const HesapAyarlari()});

  final TatilTakvimi takvim;
  final HesapAyarlari ayarlar;

  SureSonucu hesapla({required SureKurali kural, required Tarih baslangic}) {
    final adimlar = <HesapAdimi>[];
    final uyarilar = <String>[];

    if (kural.onayDurumu == OnayDurumu.kaldirildi) {
      throw StateError('${kural.kod} kuralı yürürlükten kaldırılmış; yeni hesapta kullanılamaz.');
    }
    if (!kural.kullanilabilir) {
      if (!ayarlar.taslakKuralaIzinVer) {
        throw StateError('${kural.kod} kuralı avukat onayı almamış (taslak).');
      }
      uyarilar.add('Bu kural taslaktır; avukat onayı olmadan sonuç kullanılamaz.');
    }
    if (baslangic.isBefore(kural.yururlukTarihi)) {
      uyarilar.add('Başlangıç tarihi kuralın yürürlük tarihinden (${kural.yururlukTarihi.turkceBicim}) önce.');
    }

    adimlar.add(HesapAdimi(
        baslangic, 'Başlangıç: ${kural.ad} (${kural.sureMetni}, ${kural.dayanak}). Bu gün hesaba katılmaz.'));

    // 1-2. Ham bitiş günü
    var son = switch (kural.birim) {
      SureBirimi.gun => baslangic.gunEkle(kural.miktar),
      SureBirimi.hafta => baslangic.gunEkle(kural.miktar * 7),
      SureBirimi.ay => baslangic.ayEkle(kural.miktar),
      SureBirimi.yil => baslangic.yilEkle(kural.miktar),
    };
    adimlar.add(HesapAdimi(son, '${kural.sureMetni} eklendi; ham son gün (${son.gunAdi}).'));

    // 3. Adli tatil
    if (kural.adliTatildeUzar) {
      final (bAy, bGun) = ayarlar.adliTatilBaslangicAyGun;
      final (sAy, sGun) = ayarlar.adliTatilBitisAyGun;
      final tatilBas = Tarih(son.yil, bAy, bGun);
      final tatilSon = Tarih(son.yil, sAy, sGun);
      if (son.arasinda(tatilBas, tatilSon)) {
        son = tatilSon.gunEkle(ayarlar.adliTatilUzamaGun);
        adimlar.add(HesapAdimi(
            son,
            'Son gün adli tatile (${tatilBas.turkceBicim}-${tatilSon.turkceBicim}) denk geldi; '
            'adli tatil bitiminden itibaren ${ayarlar.adliTatilUzamaGun} gün uzadı.'));
      }
    }

    // 4. Tatil ve hafta sonu
    _veriKontrol(baslangic, son, uyarilar);
    var guvenlik = 0;
    while (true) {
      final neden = _tatilNedeni(son);
      if (neden == null) break;
      final yeni = son.gunEkle(1);
      adimlar.add(HesapAdimi(yeni, '${son.turkceBicim} $neden; süre ertesi güne kaydı.'));
      son = yeni;
      if (++guvenlik > 30) {
        throw StateError('Tatil zinciri 30 günü aştı; tatil verisini kontrol edin.');
      }
    }
    _veriKontrol(baslangic, son, uyarilar);

    adimlar.add(HesapAdimi(son, 'Son gün: ${son.turkceBicim} ${son.gunAdi}.'));

    return SureSonucu(
      kural: kural,
      baslangic: baslangic,
      sonGun: son,
      adimlar: List.unmodifiable(adimlar),
      uyarilar: List.unmodifiable(uyarilar.toSet().toList()),
    );
  }

  String? _tatilNedeni(Tarih gun) {
    final tatil = takvim.tatil(gun);
    if (tatil != null) {
      if (tatil.tamGun) return '${tatil.ad} (resmi tatil)';
      if (ayarlar.yarimGunTatilErtelerMi) return '${tatil.ad} (yarım gün tatil)';
    }
    if (ayarlar.haftaSonuTatil && gun.haftaSonu) return '${gun.gunAdi} (hafta sonu)';
    return null;
  }

  void _veriKontrol(Tarih baslangic, Tarih son, List<String> uyarilar) {
    final yillar = takvim.kapsananYillar;
    for (var yil = baslangic.yil; yil <= son.yil; yil++) {
      if (!yillar.contains(yil)) {
        uyarilar.add('$yil yılı için tatil verisi yok; sonuç güvenilir değil.');
      }
    }
  }
}
