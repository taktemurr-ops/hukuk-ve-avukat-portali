/// Türkçe kişi ve şirket adlarını karşılaştırma.
///
/// "ABC Gıda Sanayi ve Ticaret A.Ş." ile "ABC GIDA SAN. TİC. AŞ" aynı kabul edilir;
/// "Mehmet Demir" ile "Mehmet Demirci" benzer olarak işaretlenir.
class IsimEslestirme {
  IsimEslestirme._();

  /// Benzer isim uyarısı için varsayılan eşik (0-1).
  static const double varsayilanEsik = 0.85;

  static const Map<String, String> _harfler = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
    'â': 'a',
    'î': 'i',
    'û': 'u',
  };

  /// Eşleştirmede yok sayılan şirket türü ve kalıp sözcükleri.
  static const Set<String> _kalipSozcukler = {
    'a',
    's',
    'as',
    'ltd',
    'sti',
    'limited',
    'sirketi',
    'sirket',
    'anonim',
    'ticaret',
    'tic',
    'sanayi',
    'san',
    've',
    'kollektif',
    'komandit',
    'kooperatifi',
  };

  /// Türkçe büyük/küçük harf kurallarıyla küçültür, aksanları kaldırır,
  /// noktalama ve şirket türü eklerini atar.
  static String normallestir(String ad) {
    final kucuk = ad.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final sade = kucuk.split('').map((c) => _harfler[c] ?? c).join();
    final temiz = sade.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return temiz.split(' ').where((s) => s.isNotEmpty && !_kalipSozcukler.contains(s)).join(' ');
  }

  /// 0 (hiç benzemiyor) ile 1 (aynı) arasında benzerlik. Sözcük sırası önemsizdir.
  static double benzerlik(String a, String b) {
    final na = normallestir(a);
    final nb = normallestir(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    final siraliA = (na.split(' ')..sort()).join(' ');
    final siraliB = (nb.split(' ')..sort()).join(' ');
    final s1 = _oran(na, nb);
    final s2 = _oran(siraliA, siraliB);
    return s1 > s2 ? s1 : s2;
  }

  static double _oran(String a, String b) {
    final uzun = a.length > b.length ? a.length : b.length;
    return 1 - levenshtein(a, b) / uzun;
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var onceki = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final simdiki = List<int>.filled(b.length + 1, 0);
      simdiki[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final maliyet = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final silme = onceki[j] + 1;
        final ekleme = simdiki[j - 1] + 1;
        final degistirme = onceki[j - 1] + maliyet;
        var enAz = silme < ekleme ? silme : ekleme;
        if (degistirme < enAz) enAz = degistirme;
        simdiki[j] = enAz;
      }
      onceki = simdiki;
    }
    return onceki[b.length];
  }
}
