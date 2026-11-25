import '../takvim/tarih.dart';

enum DosyaTuru {
  hukuk('Hukuk davası'),
  ceza('Ceza'),
  idari('İdari dava'),
  vergi('Vergi davası'),
  icra('İcra takibi'),
  arabuluculuk('Arabuluculuk'),
  tahkim('Tahkim'),
  konkordatoIflas('Konkordato / iflas'),
  danismanlik('Danışmanlık');

  const DosyaTuru(this.ad);

  final String ad;
}

enum DosyaAsamasi {
  onDegerlendirme('Ön değerlendirme'),
  ilkDerece('İlk derece'),
  istinaf('İstinaf'),
  temyiz('Temyiz'),
  kesinlesti('Kesinleşti'),
  icraAsamasi('İcra'),
  kapandi('Kapandı');

  const DosyaAsamasi(this.ad);

  final String ad;
}

/// Dava, takip veya danışmanlık dosyası.
class Dosya {
  Dosya({
    required this.id,
    required this.kiraciId,
    required this.icNo,
    required this.tur,
    required this.baslik,
    required this.sorumlu,
    required this.acilisTarihi,
    this.yedekSorumlu,
    this.ekip = const {},
    this.mahkeme,
    this.esasNo,
    this.kararNo,
    this.asama = DosyaAsamasi.onDegerlendirme,
    this.davaDegeri,
    this.paraBirimi = 'TRY',
    this.gizli = false,
    this.bagliDosyalar = const {},
    this.kapanisTarihi,
  }) {
    if (yedekSorumlu != null && yedekSorumlu == sorumlu) {
      throw ArgumentError('Yedek sorumlu, asıl sorumludan farklı olmalıdır.');
    }
  }

  final String id;
  final String kiraciId;

  /// Büro içi numara, ör. 2026/0042.
  final String icNo;
  final DosyaTuru tur;
  final String baslik;
  final String sorumlu;
  final String? yedekSorumlu;
  final Set<String> ekip;
  final String? mahkeme;

  /// Mahkeme veya icra dairesi esas numarası, ör. 2026/123 E.
  final String? esasNo;
  final String? kararNo;
  final DosyaAsamasi asama;
  final double? davaDegeri;
  final String paraBirimi;
  final bool gizli;
  final Set<String> bagliDosyalar;
  final Tarih acilisTarihi;
  final Tarih? kapanisTarihi;

  /// Dosyaya erişimi olan herkes (sorumlu, yedek, ekip).
  Set<String> get tumEkip => {sorumlu, if (yedekSorumlu != null) yedekSorumlu!, ...ekip};

  bool get acik => asama != DosyaAsamasi.kapandi;
}

/// Tüzel kişilik ve belge türü bazında sıra numarası (ör. 2026/0001).
class NumaraSerisi {
  NumaraSerisi({required this.yil, this.onek = '', int sonNumara = 0}) : _son = sonNumara;

  final int yil;
  final String onek;
  int _son;

  int get sonNumara => _son;

  String sonraki() {
    _son++;
    return '$onek$yil/${_son.toString().padLeft(4, '0')}';
  }
}

/// Esas/karar numaralarını karşılaştırma için normalleştirir: "2026/123 E." → "2026/123".
String esasNoNormallestir(String no) {
  final eslesme = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(no);
  if (eslesme == null) return no.trim().toLowerCase();
  return '${eslesme.group(1)}/${int.parse(eslesme.group(2)!)}';
}
