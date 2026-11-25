/// Grup şirketi (tüzel kişilik).
class Sirket {
  const Sirket({required this.id, required this.unvan, this.vkn, this.anaSirketId, this.kisaAd});

  final String id;
  final String unvan;
  final String? vkn;
  final String? anaSirketId;
  final String? kisaAd;

  String get gorunenAd => kisaAd ?? unvan;
}

/// Holding ve bağlı şirketlerin ağacı. Döngü ve bilinmeyen ana şirket reddedilir.
class GrupYapisi {
  GrupYapisi(Iterable<Sirket> sirketler) : _sirketler = {for (final s in sirketler) s.id: s} {
    for (final s in _sirketler.values) {
      final ana = s.anaSirketId;
      if (ana != null && !_sirketler.containsKey(ana)) throw ArgumentError('${s.unvan}: ana şirket bulunamadı.');
      final gorulen = <String>{s.id};
      var x = ana;
      while (x != null) {
        if (!gorulen.add(x)) throw ArgumentError('${s.unvan}: şirket ağacında döngü var.');
        x = _sirketler[x]?.anaSirketId;
      }
    }
  }

  final Map<String, Sirket> _sirketler;

  Iterable<Sirket> get tumu => _sirketler.values;

  Sirket? sirket(String id) => _sirketler[id];

  List<Sirket> altlar(String id) => _sirketler.values.where((s) => s.anaSirketId == id).toList()
    ..sort((a, b) => a.unvan.compareTo(b.unvan));

  List<Sirket> get kokler =>
      _sirketler.values.where((s) => s.anaSirketId == null).toList()..sort((a, b) => a.unvan.compareTo(b.unvan));

  /// Şirket ve tüm alt şirketleri.
  Set<String> kapsam(String id) => {id, for (final a in altlar(id)) ...kapsam(a.id)};

  int derinlik(String id) {
    var d = 0;
    var x = _sirketler[id]?.anaSirketId;
    while (x != null) {
      d++;
      x = _sirketler[x]?.anaSirketId;
    }
    return d;
  }

  /// Ağaç sırasıyla (ana şirket, ardından altları) ve derinlikle.
  List<(Sirket, int)> agacSirasi() {
    final l = <(Sirket, int)>[];
    void gez(Sirket s, int d) {
      l.add((s, d));
      for (final a in altlar(s.id)) {
        gez(a, d + 1);
      }
    }

    for (final k in kokler) {
      gez(k, 0);
    }
    return l;
  }

  /// Kullanıcıya atanan şirketler alt şirketleriyle birlikte yetki kapsamıdır.
  Set<String> yetkiKapsami(Iterable<String> atananlar) => {for (final a in atananlar) ...kapsam(a)};

  GrupYapisi ekle(Sirket s) {
    if (_sirketler.containsKey(s.id)) throw ArgumentError('Şirket zaten kayıtlı.');
    if (s.vkn != null && _sirketler.values.any((x) => x.vkn == s.vkn)) throw ArgumentError('Bu VKN ile şirket zaten kayıtlı.');
    return GrupYapisi([..._sirketler.values, s]);
  }
}
