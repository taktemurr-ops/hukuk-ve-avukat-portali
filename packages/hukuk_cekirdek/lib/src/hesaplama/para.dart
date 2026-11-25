/// Kuruş hassasiyetinde para. Kayan nokta hatalarını önlemek için tamsayı kuruş tutar.
class Para implements Comparable<Para> {
  const Para.kurus(this.kurus, {this.birim = 'TRY'});

  /// 1234.565 → 123457 kuruş (yarım yukarı yuvarlama).
  factory Para.tl(num tutar, {String birim = 'TRY'}) => Para.kurus(_yuvarla(tutar * 100), birim: birim);

  static const sifir = Para.kurus(0);

  final int kurus;
  final String birim;

  double get tutar => kurus / 100;

  static int _yuvarla(num deger) {
    // 0.5 sınırındaki kayan nokta artığını tolere ederek yarım yukarı yuvarlar.
    final d = deger.toDouble();
    return d >= 0 ? (d + 1e-6).round() : -((-d + 1e-6).round());
  }

  void _ayniBirim(Para d) {
    if (d.birim != birim) throw ArgumentError('Farklı para birimleri toplanamaz: $birim / ${d.birim}');
  }

  Para operator +(Para d) {
    _ayniBirim(d);
    return Para.kurus(kurus + d.kurus, birim: birim);
  }

  Para operator -(Para d) {
    _ayniBirim(d);
    return Para.kurus(kurus - d.kurus, birim: birim);
  }

  Para operator -() => Para.kurus(-kurus, birim: birim);

  /// Oranla çarpar ve kuruşa yuvarlar.
  Para carp(num carpan) => Para.kurus(_yuvarla(kurus * carpan), birim: birim);

  bool operator <(Para d) => compareTo(d) < 0;
  bool operator >(Para d) => compareTo(d) > 0;
  bool operator <=(Para d) => compareTo(d) <= 0;
  bool operator >=(Para d) => compareTo(d) >= 0;

  bool get negatif => kurus < 0;
  bool get sifirMi => kurus == 0;

  static Para enBuyuk(Para a, Para b) => a >= b ? a : b;
  static Para enKucuk(Para a, Para b) => a <= b ? a : b;

  /// "1.234.567,89 TL"
  String get bicimli {
    final mutlak = kurus.abs();
    final tam = (mutlak ~/ 100).toString();
    final kesir = (mutlak % 100).toString().padLeft(2, '0');
    final gruplu = StringBuffer();
    for (var i = 0; i < tam.length; i++) {
      if (i > 0 && (tam.length - i) % 3 == 0) gruplu.write('.');
      gruplu.write(tam[i]);
    }
    final sembol = birim == 'TRY' ? 'TL' : birim;
    return '${kurus < 0 ? '-' : ''}$gruplu,$kesir $sembol';
  }

  @override
  int compareTo(Para other) {
    _ayniBirim(other);
    return kurus.compareTo(other.kurus);
  }

  @override
  bool operator ==(Object other) => other is Para && other.kurus == kurus && other.birim == birim;

  @override
  int get hashCode => Object.hash(kurus, birim);

  @override
  String toString() => bicimli;
}
