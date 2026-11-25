import '../takvim/tarih.dart';

enum GorevOnceligi { dusuk, normal, yuksek, kritik }

enum GorevDurumu { acik, tamamlandi, iptal }

class Gorev {
  const Gorev({
    required this.id,
    required this.baslik,
    required this.atanan,
    this.dosyaId,
    this.yedek,
    this.sonTarih,
    this.oncelik = GorevOnceligi.normal,
    this.durum = GorevDurumu.acik,
    this.kaynakSureId,
    this.kanitGerekir = false,
    this.kapanisKaniti,
  });

  final String id;
  final String baslik;
  final String atanan;
  final String? dosyaId;
  final String? yedek;
  final Tarih? sonTarih;
  final GorevOnceligi oncelik;
  final GorevDurumu durum;

  /// Görev bir kritik süreden doğduysa o sürenin kimliği.
  final String? kaynakSureId;

  /// Kritik görevler işlem no, makbuz veya belgeyle kapanır.
  final bool kanitGerekir;
  final String? kapanisKaniti;

  bool gecikti(Tarih bugun) => durum == GorevDurumu.acik && sonTarih != null && sonTarih!.isBefore(bugun);

  Gorev kapat({String? kanit}) {
    if (durum != GorevDurumu.acik) throw StateError('Görev zaten kapalı.');
    final gerekli = kanitGerekir || kaynakSureId != null;
    if (gerekli && (kanit == null || kanit.trim().isEmpty)) {
      throw ArgumentError('Bu görev kanıtla (işlem no, makbuz veya belge) kapatılmalıdır.');
    }
    return Gorev(
      id: id,
      baslik: baslik,
      atanan: atanan,
      dosyaId: dosyaId,
      yedek: yedek,
      sonTarih: sonTarih,
      oncelik: oncelik,
      durum: GorevDurumu.tamamlandi,
      kaynakSureId: kaynakSureId,
      kanitGerekir: kanitGerekir,
      kapanisKaniti: kanit?.trim(),
    );
  }
}

/// Şablondaki tek adım: başlangıçtan kaç gün sonra, kime.
class SablonAdimi {
  const SablonAdimi(this.baslik, this.gunSonra, {this.rol = 'sorumlu', this.oncelik = GorevOnceligi.normal});

  final String baslik;
  final int gunSonra;

  /// "sorumlu", "yedek" veya "stajyer" gibi; şablon uygulanırken kişiye çevrilir.
  final String rol;
  final GorevOnceligi oncelik;

  static const roller = {'sorumlu', 'yedek', 'stajyer'};

  Map<String, Object> toJson() => {'baslik': baslik, 'gunSonra': gunSonra, 'rol': rol, 'oncelik': oncelik.name};
}

/// "İş davası açılışı" gibi tekrar eden işlerin görev listesi.
class GorevSablonu {
  const GorevSablonu({required this.ad, required this.adimlar});

  final String ad;
  final List<SablonAdimi> adimlar;

  List<Gorev> uygula({
    required String dosyaId,
    required Tarih baslangic,
    required Map<String, String> roller,
    required String Function() idUret,
  }) {
    return [
      for (final a in adimlar)
        Gorev(
          id: idUret(),
          baslik: a.baslik,
          atanan: roller[a.rol] ?? roller['sorumlu']!,
          dosyaId: dosyaId,
          yedek: a.rol == 'sorumlu' ? roller['yedek'] : roller['sorumlu'],
          sonTarih: baslangic.gunEkle(a.gunSonra),
          oncelik: a.oncelik,
        ),
    ];
  }

  Map<String, Object> toJson() => {'ad': ad, 'adimlar': [for (final a in adimlar) a.toJson()]};

  /// JSON'dan şablon; kurala uymayan şablonda Türkçe iletiyle [FormatException].
  /// Kurallar: ad 3–100 karakter, 1–50 adım, adım başlığı en az 3 karakter, gün 0–3650, bilinen rol ve öncelik.
  factory GorevSablonu.json(Map<String, dynamic> j) {
    final ad = '${j['ad'] ?? ''}'.trim();
    if (ad.length < 3 || ad.length > 100) throw const FormatException('Şablon adı 3–100 karakter olmalıdır.');
    final ham = j['adimlar'];
    if (ham is! List || ham.isEmpty || ham.length > 50) throw const FormatException('Şablonda 1–50 adım olmalıdır.');
    final adimlar = <SablonAdimi>[];
    for (var i = 0; i < ham.length; i++) {
      final a = ham[i];
      if (a is! Map) throw FormatException('${i + 1}. adım geçersiz.');
      final baslik = '${a['baslik'] ?? ''}'.trim();
      final gun = a['gunSonra'];
      final rol = '${a['rol'] ?? 'sorumlu'}';
      final oncelik = GorevOnceligi.values.where((o) => o.name == (a['oncelik'] ?? 'normal')).firstOrNull;
      if (baslik.length < 3 || baslik.length > 200) throw FormatException('${i + 1}. adım: başlık 3–200 karakter olmalıdır.');
      if (gun is! int || gun < 0 || gun > 3650) throw FormatException('${i + 1}. adım: gün 0–3650 arasında olmalıdır.');
      if (!SablonAdimi.roller.contains(rol)) throw FormatException('${i + 1}. adım: rol sorumlu, yedek veya stajyer olmalıdır.');
      if (oncelik == null) throw FormatException('${i + 1}. adım: öncelik geçersiz.');
      adimlar.add(SablonAdimi(baslik, gun, rol: rol, oncelik: oncelik));
    }
    return GorevSablonu(ad: ad, adimlar: adimlar);
  }

  static const hazirSablonlar = [isDavasiAcilisi, icraTakibiBaslatma];

  static const isDavasiAcilisi = GorevSablonu(ad: 'İş davası açılışı', adimlar: [
    SablonAdimi('Arabuluculuk son tutanağını dosyaya ekle', 0, rol: 'stajyer'),
    SablonAdimi('Bordro, SGK hizmet dökümü ve iş sözleşmesini topla', 3, rol: 'stajyer'),
    SablonAdimi('İşçilik alacaklarını hesapla', 5),
    SablonAdimi('Dava dilekçesi taslağı', 10),
    SablonAdimi('Dilekçe kontrolü ve UYAP\'tan gönderim', 12, oncelik: GorevOnceligi.yuksek),
  ]);

  static const icraTakibiBaslatma = GorevSablonu(ad: 'İlamsız icra takibi başlatma', adimlar: [
    SablonAdimi('Alacak belgelerini ve borçlu bilgisini doğrula', 0),
    SablonAdimi('Faiz ve takip tutarını hesapla', 1),
    SablonAdimi('Takip talebini hazırla ve gönder', 2, oncelik: GorevOnceligi.yuksek),
    SablonAdimi('Ödeme emri tebliğini takip et', 15, rol: 'stajyer'),
  ]);
}

/// Duruşma, keşif, bilirkişi incelemesi gibi zamanlı etkinlik.
class Durusma {
  const Durusma({
    required this.id,
    required this.dosyaId,
    required this.baslangic,
    required this.yer,
    required this.katilan,
    this.sureDakika = 60,
    this.tur = 'Duruşma',
  });

  final String id;
  final String dosyaId;
  final DateTime baslangic;
  final String yer;

  /// Katılacak avukat.
  final String katilan;
  final int sureDakika;
  final String tur;

  DateTime get bitis => baslangic.add(Duration(minutes: sureDakika));
}

class Cakisma {
  const Cakisma(this.a, this.b, this.neden);

  final Durusma a;
  final Durusma b;
  final String neden;
}

/// Aynı avukatın üst üste binen veya yetişilemeyecek etkinliklerini bulur.
class CakismaKontrolu {
  CakismaKontrolu._();

  /// Farklı adliyeler arasında gereken varsayılan yol süresi.
  static const Duration varsayilanYolSuresi = Duration(minutes: 60);

  static List<Cakisma> bul(Iterable<Durusma> durusmalar, {Duration yolSuresi = varsayilanYolSuresi}) {
    final liste = durusmalar.toList()..sort((x, y) => x.baslangic.compareTo(y.baslangic));
    final sonuc = <Cakisma>[];
    for (var i = 0; i < liste.length; i++) {
      for (var j = i + 1; j < liste.length; j++) {
        final a = liste[i];
        final b = liste[j];
        if (a.katilan != b.katilan) continue;
        final ayniYer = a.yer.trim().toLowerCase() == b.yer.trim().toLowerCase();
        final gereken = ayniYer ? Duration.zero : yolSuresi;
        if (b.baslangic.isBefore(a.bitis)) {
          sonuc.add(Cakisma(a, b, 'Saatler çakışıyor'));
        } else if (b.baslangic.isBefore(a.bitis.add(gereken))) {
          sonuc.add(Cakisma(a, b, 'Farklı yerler arasında yol süresi yetersiz'));
        }
      }
    }
    return sonuc;
  }
}
