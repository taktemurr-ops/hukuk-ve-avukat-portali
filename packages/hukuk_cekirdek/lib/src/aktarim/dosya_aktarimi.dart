import '../dosya/dosya.dart';
import '../takvim/tarih.dart';
import '../taraf/isim_eslestirme.dart';
import 'veri_aktarimi.dart';

/// UYAP Avukat Portalı'ndan ya da başka bir programdan alınan dosya listesinin (Excel/CSV) aktarımı.
/// Sütunlar başlıktan tahmin edilir; mahkeme + esas no ile mükerrer kontrolü yapılır (dosyada ve büroda).
/// Not: UYAP çıktısının sütun adları sürüme göre değişebilir; gerçek çıktılarla doğrulanmalıdır.
enum DosyaAlani {
  mahkeme('Mahkeme / birim'),
  esasNo('Esas / dosya no'),
  tur('Dosya türü'),
  muvekkil('Müvekkil'),
  karsiTaraf('Karşı taraf'),
  taraflar('Taraflar'),
  acilis('Açılış tarihi'),
  durum('Durum');

  const DosyaAlani(this.ad);

  final String ad;
}

const Map<DosyaAlani, List<String>> _dosyaEsAnlamlilari = {
  DosyaAlani.mahkeme: ['mahkeme', 'birim', 'birim adi', 'mahkeme adi', 'daire', 'icra dairesi', 'yargi birimi'],
  DosyaAlani.esasNo: ['esas no', 'esas', 'dosya no', 'dosya numarasi', 'esas numarasi', 'takip no'],
  DosyaAlani.tur: ['dosya turu', 'tur', 'turu', 'yargi turu', 'dava turu'],
  DosyaAlani.muvekkil: ['muvekkil', 'muvekkil adi', 'vekil edilen', 'alacakli', 'davaci'],
  DosyaAlani.karsiTaraf: ['karsi taraf', 'borclu', 'davali'],
  DosyaAlani.taraflar: ['taraflar', 'taraf bilgisi', 'taraf'],
  DosyaAlani.acilis: ['acilis tarihi', 'dava tarihi', 'takip tarihi', 'kayit tarihi', 'acilis'],
  DosyaAlani.durum: ['durum', 'dosya durumu', 'durumu'],
};

Map<DosyaAlani, int> dosyaSutunEslemesiTahminEt(List<String> basliklar) {
  final esleme = <DosyaAlani, int>{};
  for (var i = 0; i < basliklar.length; i++) {
    final n = IsimEslestirme.normallestir(basliklar[i]);
    for (final e in _dosyaEsAnlamlilari.entries) {
      if (!esleme.containsKey(e.key) && e.value.contains(n)) {
        esleme[e.key] = i;
        break;
      }
    }
  }
  return esleme;
}

class DosyaAktarimSatiri {
  DosyaAktarimSatiri({required this.satirNo, required this.degerler});

  final int satirNo;
  final Map<DosyaAlani, String> degerler;
  final List<String> hatalar = [];
  final List<String> uyarilar = [];
  String? mukerrerAciklama;
  DosyaTuru tur = DosyaTuru.hukuk;
  String? esasNo;
  Tarih? acilis;
  bool kapali = false;

  String deger(DosyaAlani a) => degerler[a]?.trim() ?? '';

  String get mahkeme => deger(DosyaAlani.mahkeme);

  /// "Müvekkil - Karşı taraf"; yoksa taraflar sütunu; o da yoksa mahkeme ve esas no.
  String get baslik {
    final m = deger(DosyaAlani.muvekkil);
    final k = deger(DosyaAlani.karsiTaraf);
    if (m.isNotEmpty && k.isNotEmpty) return _kisalt('$m - $k');
    if (m.isNotEmpty || k.isNotEmpty) return _kisalt(m.isNotEmpty ? m : k);
    final t = deger(DosyaAlani.taraflar);
    if (t.isNotEmpty) return _kisalt(t);
    return '$mahkeme ${esasNo ?? ''}'.trim();
  }

  static String _kisalt(String s) => s.length <= 150 ? s : '${s.substring(0, 147)}...';

  SatirDurumu get durum => hatalar.isNotEmpty
      ? SatirDurumu.hatali
      : mukerrerAciklama != null
          ? SatirDurumu.mukerrer
          : SatirDurumu.aktarilacak;
}

class DosyaAktarimOnizlemesi {
  const DosyaAktarimOnizlemesi({required this.basliklar, required this.esleme, required this.satirlar});

  final List<String> basliklar;
  final Map<DosyaAlani, int> esleme;
  final List<DosyaAktarimSatiri> satirlar;

  int sayi(SatirDurumu d) => satirlar.where((s) => s.durum == d).length;

  bool get mutabik => satirlar.length == sayi(SatirDurumu.aktarilacak) + sayi(SatirDurumu.mukerrer) + sayi(SatirDurumu.hatali);
}

class DosyaAktarimi {
  DosyaAktarimi._();

  static final _esas = RegExp(r'^(\d{4})\s*/\s*(\d{1,7})\s*(E|D|Tal|Talimat)?\.?$', caseSensitive: false);
  static final _tarih = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})');

  /// "2026/123", "2026/123 E" → "2026/123 E."; biçim dışıysa null.
  static String? esasNoBicimle(String v) {
    final m = _esas.firstMatch(v.trim());
    if (m == null) return null;
    final ek = (m[3] ?? 'E').toUpperCase();
    return '${m[1]}/${m[2]} ${ek == 'D' ? 'D.' : ek == 'E' ? 'E.' : 'Tal.'}';
  }

  /// Türü önce "dosya türü" sütunundan, yoksa birim adından tahmin eder.
  static DosyaTuru turTahmin(String turMetni, String mahkeme) {
    final t = IsimEslestirme.normallestir('$turMetni $mahkeme');
    if (t.contains('icra')) return DosyaTuru.icra;
    if (t.contains('ceza') || t.contains('sorusturma') || t.contains('savcilik') || t.contains('basavcilik')) {
      return DosyaTuru.ceza;
    }
    if (t.contains('vergi')) return DosyaTuru.vergi;
    if (t.contains('idare') || t.contains('idari')) return DosyaTuru.idari;
    if (t.contains('arabulucu')) return DosyaTuru.arabuluculuk;
    if (t.contains('tahkim')) return DosyaTuru.tahkim;
    if (t.contains('iflas') || t.contains('konkordato')) return DosyaTuru.konkordatoIflas;
    return DosyaTuru.hukuk;
  }

  static DosyaAktarimOnizlemesi onizle({
    required List<List<String>> tablo,
    required Iterable<Dosya> mevcut,
    Map<DosyaAlani, int>? esleme,
  }) {
    if (tablo.isEmpty) return const DosyaAktarimOnizlemesi(basliklar: [], esleme: {}, satirlar: []);
    final basliklar = tablo.first;
    final e = esleme ?? dosyaSutunEslemesiTahminEt(basliklar);
    // Kalıp sözcükleri ("ticaret" gibi) silen isim normalleştirmesi burada kullanılmaz: "Asliye Ticaret" ile
    // "Asliye Hukuk" ayrı mahkemelerdir.
    String anahtar(String mahkeme, String esas) =>
        '${mahkeme.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim()}|$esas';
    final burodaki = <String, String>{
      for (final d in mevcut)
        if (d.mahkeme != null && d.esasNo != null) anahtar(d.mahkeme!, d.esasNo!): d.icNo,
    };
    final dosyada = <String, int>{};
    final satirlar = <DosyaAktarimSatiri>[];
    for (var i = 1; i < tablo.length; i++) {
      final h = tablo[i];
      final s = DosyaAktarimSatiri(satirNo: i + 1, degerler: {
        for (final x in e.entries)
          if (x.value < h.length) x.key: h[x.value],
      });
      if (s.mahkeme.isEmpty) s.hatalar.add('Mahkeme / birim boş.');
      if (s.mahkeme.length > 200) s.hatalar.add('Mahkeme adı çok uzun.');
      final esasHam = s.deger(DosyaAlani.esasNo);
      s.esasNo = esasHam.isEmpty ? null : esasNoBicimle(esasHam);
      if (esasHam.isEmpty) {
        s.hatalar.add('Esas / dosya no boş.');
      } else if (s.esasNo == null) {
        s.hatalar.add('Esas no "2026/123" biçiminde değil.');
      }
      s.tur = turTahmin(s.deger(DosyaAlani.tur), s.mahkeme);
      final t = _tarih.firstMatch(s.deger(DosyaAlani.acilis));
      if (t != null) {
        try {
          s.acilis = Tarih(int.parse(t[3]!), int.parse(t[2]!), int.parse(t[1]!));
        } on ArgumentError {
          s.uyarilar.add('Açılış tarihi okunamadı; bugünün tarihi kullanılacak.');
        }
      } else if (s.deger(DosyaAlani.acilis).isNotEmpty) {
        s.uyarilar.add('Açılış tarihi okunamadı; bugünün tarihi kullanılacak.');
      }
      final durum = IsimEslestirme.normallestir(s.deger(DosyaAlani.durum));
      s.kapali = durum.contains('kapal') || durum.contains('kesinles') || durum.contains('arsiv') || durum.contains('dustu');
      if (s.kapali) s.uyarilar.add('Kapalı dosya; açık olarak aktarılır, gerekirse kapatın.');
      if (s.hatalar.isEmpty) {
        final a = anahtar(s.mahkeme, s.esasNo!);
        final b = burodaki[a];
        final d = dosyada[a];
        if (b != null) {
          s.mukerrerAciklama = 'Büroda zaten kayıtlı ($b).';
        } else if (d != null) {
          s.mukerrerAciklama = 'Listede $d. satırla aynı dosya.';
        } else {
          dosyada[a] = s.satirNo;
        }
      }
      satirlar.add(s);
    }
    return DosyaAktarimOnizlemesi(basliklar: basliklar, esleme: e, satirlar: satirlar);
  }
}
