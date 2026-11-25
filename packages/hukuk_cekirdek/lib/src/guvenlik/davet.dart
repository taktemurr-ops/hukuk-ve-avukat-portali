import 'dart:math';

import '../hesap/hesap_turu.dart';

/// Lisans koltuğu tüketmeyen roller (iş birimi talep edenleri, onaycılar, müvekkiller, denetçiler, dış avukatlar).
const Set<Rol> ucretsizRoller = {Rol.talepEden, Rol.onayci, Rol.muvekkil, Rol.denetci, Rol.disAvukat};

/// Ekip üyesi daveti. Davet edilen kişi kendi şifresini belirler; şifre e-postayla gönderilmez.
class Davet {
  Davet({
    required this.kod,
    required this.kiraciId,
    required this.eposta,
    required this.roller,
    required this.davetEden,
    required this.olusturma,
    this.gecerlilik = const Duration(hours: 72),
    this.kullanildi = false,
    this.iptal = false,
  });

  /// Rastgele 32 karakterlik kod (bağlantıda kullanılır).
  static String kodUret([Random? rastgele]) {
    final r = rastgele ?? Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[r.nextInt(16)]).join();
  }

  final String kod;
  final String kiraciId;
  final String eposta;
  final Set<Rol> roller;
  final String davetEden;
  final DateTime olusturma;
  final Duration gecerlilik;
  final bool kullanildi;
  final bool iptal;

  bool koltukTuketir() => roller.any((r) => !ucretsizRoller.contains(r));

  bool gecerliMi(DateTime simdi) => !kullanildi && !iptal && simdi.isBefore(olusturma.add(gecerlilik));

  /// Davet kabulü; hata varsa açıklaması fırlatılır.
  Davet kabulEt({required String eposta, required DateTime simdi}) {
    if (iptal) throw StateError('Davet iptal edilmiş.');
    if (kullanildi) throw StateError('Davet daha önce kullanılmış.');
    if (!simdi.isBefore(olusturma.add(gecerlilik))) throw StateError('Davetin süresi dolmuş.');
    if (eposta.trim().toLowerCase() != this.eposta.trim().toLowerCase()) {
      throw StateError('Davet bu e-posta adresi için oluşturulmamış.');
    }
    return Davet(
      kod: kod,
      kiraciId: kiraciId,
      eposta: this.eposta,
      roller: roller,
      davetEden: davetEden,
      olusturma: olusturma,
      gecerlilik: gecerlilik,
      kullanildi: true,
    );
  }
}

/// Lisans koltuğu kontrolü: aktif kullanıcılar + bekleyen davetler koltuk sayısını aşamaz.
String? koltukKontrolu({
  required int lisansKoltugu,
  required int koltukKullananAktifKullanici,
  required int koltukTuketenBekleyenDavet,
  required Set<Rol> yeniRoller,
}) {
  if (yeniRoller.isEmpty) return 'En az bir rol seçilmelidir.';
  if (yeniRoller.every(ucretsizRoller.contains)) return null;
  final dolu = koltukKullananAktifKullanici + koltukTuketenBekleyenDavet;
  if (dolu >= lisansKoltugu) {
    return 'Lisans koltukları dolu ($dolu/$lisansKoltugu). Kullanıcı eklemek için paketinizi güncelleyin.';
  }
  return null;
}
