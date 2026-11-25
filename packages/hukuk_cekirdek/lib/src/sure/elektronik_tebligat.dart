import '../takvim/tarih.dart';

/// Elektronik tebligat tarihleri.
///
/// Elektronik tebligat, muhatabın elektronik adresine ulaştığı tarihi izleyen
/// beşinci günün sonunda yapılmış sayılır (Tebligat Kanunu m.7/a ve
/// Elektronik Tebligat Yönetmeliği; avukat onayı bekler).
class ElektronikTebligat {
  ElektronikTebligat._();

  /// Ulaşma tarihinden tebliğ tarihini hesaplar.
  static Tarih tebligTarihi(Tarih ulasmaTarihi) => ulasmaTarihi.gunEkle(5);
}

/// Bir tebligatın ayrı ayrı tutulan tarihleri.
class TebligatTarihleri {
  TebligatTarihleri.elektronik(this.ulasma) : tebligEdilen = ElektronikTebligat.tebligTarihi(ulasma);

  TebligatTarihleri.fiziki({required Tarih tebligTarihi})
      : ulasma = tebligTarihi,
        tebligEdilen = tebligTarihi;

  /// Evrakın elektronik adrese veya kişiye ulaştığı gün.
  final Tarih ulasma;

  /// Hukuken tebliğ edilmiş sayıldığı gün; süreler bu günden başlar.
  final Tarih tebligEdilen;
}
