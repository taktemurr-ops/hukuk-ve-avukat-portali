/// Saat bilgisi olmayan takvim günü.
///
/// Süre hesaplarında saat dilimi ve yaz saati hatalarını önlemek için
/// tüm tarihler UTC gece yarısı olarak tutulur.
class Tarih implements Comparable<Tarih> {
  Tarih(int yil, int ay, int gun) : _dt = DateTime.utc(yil, ay, gun) {
    if (_dt.year != yil || _dt.month != ay || _dt.day != gun) {
      throw ArgumentError('Geçersiz tarih: $yil-$ay-$gun');
    }
  }

  Tarih._(this._dt);

  /// Herhangi bir [DateTime] değerinin yalnızca gün kısmını alır.
  factory Tarih.from(DateTime dt) => Tarih._(DateTime.utc(dt.year, dt.month, dt.day));

  /// `YYYY-AA-GG` biçimindeki metni çözer.
  factory Tarih.parse(String metin) {
    final parcalar = metin.split('-');
    if (parcalar.length != 3) {
      throw FormatException('Tarih YYYY-AA-GG biçiminde olmalı', metin);
    }
    return Tarih(int.parse(parcalar[0]), int.parse(parcalar[1]), int.parse(parcalar[2]));
  }

  final DateTime _dt;

  int get yil => _dt.year;
  int get ay => _dt.month;
  int get gun => _dt.day;

  /// 1 = Pazartesi ... 7 = Pazar
  int get haftaninGunu => _dt.weekday;

  bool get haftaSonu => haftaninGunu == DateTime.saturday || haftaninGunu == DateTime.sunday;

  Tarih gunEkle(int gunSayisi) => Tarih._(DateTime.utc(yil, ay, gun + gunSayisi));

  /// Ay ekler. Hedef ayda aynı gün yoksa ayın son günü alınır (ör. 31 Ocak + 1 ay = 28/29 Şubat).
  Tarih ayEkle(int aySayisi) {
    final toplamAy = (yil * 12 + (ay - 1)) + aySayisi;
    final hedefYil = toplamAy ~/ 12;
    final hedefAy = toplamAy % 12 + 1;
    final sonGun = DateTime.utc(hedefYil, hedefAy + 1, 0).day;
    return Tarih(hedefYil, hedefAy, gun > sonGun ? sonGun : gun);
  }

  Tarih yilEkle(int yilSayisi) => ayEkle(yilSayisi * 12);

  /// İki tarih arasındaki gün farkı (`diger - this`).
  int farkGun(Tarih diger) => diger._dt.difference(_dt).inDays;

  bool isBefore(Tarih diger) => _dt.isBefore(diger._dt);
  bool isAfter(Tarih diger) => _dt.isAfter(diger._dt);

  bool arasinda(Tarih baslangic, Tarih bitis) => !isBefore(baslangic) && !isAfter(bitis);

  static const _gunAdlari = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

  String get gunAdi => _gunAdlari[haftaninGunu - 1];

  /// `GG.AA.YYYY` biçimi.
  String get turkceBicim =>
      '${gun.toString().padLeft(2, '0')}.${ay.toString().padLeft(2, '0')}.${yil.toString().padLeft(4, '0')}';

  String get isoBicim =>
      '${yil.toString().padLeft(4, '0')}-${ay.toString().padLeft(2, '0')}-${gun.toString().padLeft(2, '0')}';

  @override
  int compareTo(Tarih other) => _dt.compareTo(other._dt);

  @override
  bool operator ==(Object other) => other is Tarih && other._dt == _dt;

  @override
  int get hashCode => _dt.hashCode;

  @override
  String toString() => isoBicim;
}
