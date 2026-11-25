import '../hesaplama/para.dart';
import '../takvim/tarih.dart';
import 'sozlesme.dart';

enum RiskSeviyesi {
  dusuk('Düşük'),
  orta('Orta'),
  yuksek('Yüksek');

  const RiskSeviyesi(this.ad);
  final String ad;

  int get puan => switch (this) { dusuk => 4, orta => 12, yuksek => 30 };
}

/// Taramada bulunan bir madde ya da risk. [alinti] sözleşmedeki ilgili cümledir (boş: madde bulunamadı).
class TaramaBulgusu {
  const TaramaBulgusu({
    required this.kod,
    required this.baslik,
    required this.seviye,
    required this.aciklama,
    this.alinti = '',
  });

  final String kod;
  final String baslik;
  final RiskSeviyesi seviye;
  final String aciklama;
  final String alinti;
}

/// Otomatik sözleşme taraması sonucu. Kural tabanlıdır, sözleşme metnini yurt dışına göndermez.
/// Sonuç bir öneridir; hukukçu kontrolünden geçmeden kesinleşmiş kabul edilmez.
class TaramaSonucu {
  const TaramaSonucu({
    this.tur,
    this.taraflar = const [],
    this.baslangic,
    this.bitis,
    this.sureAy,
    this.otomatikYenileme = false,
    this.ihbarSuresiGun,
    this.bedel,
    this.odemeVadesiGun,
    this.yetkiliYer,
    this.uygulanacakHukuk,
    this.tahkim = false,
    this.bulunanMaddeler = const {},
    this.bulgular = const [],
  });

  final SozlesmeTuru? tur;
  final List<String> taraflar;
  final Tarih? baslangic;
  final Tarih? bitis;
  final int? sureAy;
  final bool otomatikYenileme;
  final int? ihbarSuresiGun;
  final Para? bedel;
  final int? odemeVadesiGun;
  final String? yetkiliYer;
  final String? uygulanacakHukuk;
  final bool tahkim;
  final Set<String> bulunanMaddeler;
  final List<TaramaBulgusu> bulgular;

  int get riskPuani {
    final t = bulgular.fold<int>(0, (a, b) => a + b.seviye.puan);
    return t > 100 ? 100 : t;
  }

  RiskSeviyesi get genelSeviye => bulgular.any((b) => b.seviye == RiskSeviyesi.yuksek) || riskPuani >= 60
      ? RiskSeviyesi.yuksek
      : riskPuani >= 25
          ? RiskSeviyesi.orta
          : RiskSeviyesi.dusuk;

  static const uyari = 'Otomatik tarama sonucudur; hukukçu kontrolünden geçmeden kesin kabul edilmemelidir.';
}

class _Cumle {
  const _Cumle(this.ozgun, this.kucuk);
  final String ozgun;
  final String kucuk;
}

class SozlesmeTarayici {
  const SozlesmeTarayici();

  /// Türkçe küçük harf (İ→i, I→ı); uzunluğu korur.
  static String kucukHarf(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  static const _harf = 'a-zçğıöşüâîû';
  static final _tarih = RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})');
  static final _sayiKelime = <String, int>{
    'bir': 1, 'iki': 2, 'üç': 3, 'dört': 4, 'beş': 5, 'altı': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9, 'on': 10,
    'on iki': 12, 'on beş': 15, 'yirmi': 20, 'otuz': 30, 'altmış': 60, 'doksan': 90,
  };
  static const _sayi = '(?<![$_harf\\d])'
      r'(\d+|(?:on iki|on beş|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on|yirmi|otuz|altmış|doksan)(?=\s))';
  static const _parantez = r'(?:\([^)]*\)\s*)?';

  static final _sure1 = RegExp('süre(?:si)?\\s+$_sayi\\s*$_parantez(yıl|ay)');
  static final _sure2 = RegExp('$_sayi\\s*$_parantez(yıl|ay)(?:lık|lik)?\\s+(?:süre|müddet)');
  static final _yenileme = RegExp(
      '(kendiliğinden|otomatik(?:man)?(?:\\s+olarak)?|aynı\\s+(?:şart|koşul)lar(?:la|\\s+ile))[^.]{0,80}?'
      '(uzar|uzayacak|uzatılmış|uzamış|yenilen|yenilenecek|yenilenmiş)');
  static final _ihbar = RegExp('$_sayi\\s*$_parantez(gün|ay|hafta)\\s+(?:önce|evvel|öncesinden)');
  static final _tutar = RegExp(
      r'(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\s*(?:\([^)]*\)\s*)?(türk lirası|tl|₺|usd|abd doları|dolar|eur|euro|avro)');
  static final _odemeVadesi = RegExp('$_sayi\\s*$_parantez(?:iş\\s+)?gün\\s+içinde[^.]{0,60}?öde');
  static final _mahkeme = RegExp('([$_harf]+)\\s+(?:\\([^)]*\\)\\s+)?'
      '(?:(?:merkez|merkezi|adliyesi|anadolu|asliye|ticaret|tüketici|iş|sulh|bölge)\\s+)*'
      'mahkeme(?:leri|si)?[^.]{0,60}?yetkili');
  static final _hukuk = RegExp(
      '(türk|ingiliz|alman|isviçre|fransız|amerikan|new york|delaware|hollanda|lüksemburg)\\s+(?:hukuku|kanunları|yasaları)');
  static final _yurtdisiTahkim = RegExp(r'\b(icc|lcia|siac|uncitral)\b|londra|cenevre|paris|stockholm|viyana|zürih|singapur');
  static final _sirket = RegExp(
      r'((?:[A-ZÇĞİÖŞÜ0-9][A-Za-zÇĞİÖŞÜçğıöşü0-9&.\-]*\s+)(?:(?:[A-ZÇĞİÖŞÜ0-9][A-Za-zÇĞİÖŞÜçğıöşü0-9&.\-]*|ve)\s+){0,7}'
      r'(?:A\.Ş\.|Ltd\.\s?Şti\.|Limited Şirketi|Anonim Şirketi))');

  static final _kurallar = <String, RegExp>{
    'cezaiSart': RegExp(r'cezai\s+şart'),
    'sinirsizSorumluluk': RegExp('sınırsız(?:\\s+olarak|ca)?\\s+(?:ve\\s+müteselsilen\\s+)?sorumlu'),
    'sorumlulukSiniri': RegExp('sorumlulu[ğk][^.]{0,120}?(ile\\s+sınırlı|aşamaz|aşmayacak|sınırlandırıl|azami)'),
    'tekTarafliFesih': RegExp('(tek\\s+taraflı(?:\\s+olarak)?|sebep\\s+göstermeksizin|gerekçe\\s+göstermeksizin)[^.]{0,80}?fesh'),
    'tekTarafliFiyat':
        RegExp('tek\\s+taraflı[^.]{0,80}?(fiyat|bedel|ücret)[^.]{0,60}?(değiştir|artır|güncelle)'),
    'gizlilik': RegExp('gizli(?:lik)?|ticari\\s+sır'),
    'kvkk': RegExp(r'kişisel\s+veri|6698|kvkk'),
    'mucbirSebep': RegExp(r'mücbir\s+sebep|force\s+majeure'),
    'rekabetYasagi': RegExp('rekabet\\s+(?:yasağı|etmeme|etmeyeceğ)'),
    'devirYasagi': RegExp(r'devred(?:emez|ilemez|emeyecek)|devir\s+ve\s+temlik'),
    'tahkim': RegExp(r'tahkim|hakem\s+heyeti|istac'),
    'fesih': RegExp('fesih|fesh|sona\\s+erdir'),
    'temerrut': RegExp(r'temerrüt\s+faizi|gecikme\s+faizi'),
  };

  static int? _sayiyaCevir(String s) => int.tryParse(s) ?? _sayiKelime[s];

  static String _buyukBaslat(String s) {
    if (s.isEmpty) return s;
    final ilk = s[0] == 'i' ? 'İ' : s[0] == 'ı' ? 'I' : s[0].toUpperCase();
    return ilk + s.substring(1);
  }

  /// Satırlara, sonra noktalı virgül ve cümle sonlarına böler (tarih ve tutar içindeki noktalar bölünmez).
  static List<_Cumle> _cumleler(String metin) {
    final sonuc = <_Cumle>[];
    final ayirici = RegExp(r'(?<=[.;!?])\s+(?=[A-ZÇĞİÖŞÜ0-9(])');
    for (final satir in metin.split(RegExp(r'\r?\n'))) {
      for (final c in satir.split(ayirici)) {
        final t = c.trim();
        if (t.isNotEmpty) sonuc.add(_Cumle(t, kucukHarf(t)));
      }
    }
    return sonuc;
  }

  static Tarih? _tarihOku(RegExpMatch m) {
    final g = int.parse(m[1]!), a = int.parse(m[2]!), y = int.parse(m[3]!);
    try {
      return Tarih(y, a, g);
    } on ArgumentError {
      return null;
    }
  }

  static Para? _paraOku(RegExpMatch m) {
    final tam = int.parse(m[1]!.replaceAll('.', ''));
    final kesir = int.parse((m[2] ?? '0').padRight(2, '0'));
    final birim = switch (m[3]!) {
      'usd' || 'abd doları' || 'dolar' => 'USD',
      'eur' || 'euro' || 'avro' => 'EUR',
      _ => 'TRY',
    };
    return Para.kurus(tam * 100 + kesir, birim: birim);
  }

  static SozlesmeTuru? _turTahmin(String kucuk) {
    int say(String desen) => RegExp(desen).allMatches(kucuk).length;
    final basKisim = kucuk.length > 400 ? kucuk.substring(0, 400) : kucuk;
    final baslikta = <SozlesmeTuru, String>{
      SozlesmeTuru.gizlilik: r'gizlilik\s+sözleşmesi|gizlilik\s+taahhüt',
      SozlesmeTuru.kira: r'kira\s+sözleşmesi',
      SozlesmeTuru.isSozlesmesi: r'iş\s+sözleşmesi',
      SozlesmeTuru.lisans: r'lisans\s+sözleşmesi|yazılım',
      SozlesmeTuru.distributorluk: r'distribütör|bayilik',
      SozlesmeTuru.satis: r'satış\s+sözleşmesi|satım\s+sözleşmesi|tedarik\s+sözleşmesi',
      SozlesmeTuru.hizmet: r'hizmet\s+sözleşmesi|danışmanlık\s+sözleşmesi',
    };
    for (final e in baslikta.entries) {
      if (RegExp(e.value).hasMatch(basKisim)) return e.key;
    }
    final puanlar = <SozlesmeTuru, int>{
      SozlesmeTuru.kira: say(r'kiracı|kiraya\s+veren|kira\s+bedeli'),
      SozlesmeTuru.isSozlesmesi: say(r'işçi|işveren'),
      SozlesmeTuru.lisans: say(r'lisans|yazılım'),
      SozlesmeTuru.satis: say(r'alıcı|satıcı|tedarik'),
      SozlesmeTuru.hizmet: say(r'hizmet'),
    };
    final enIyi = puanlar.entries.reduce((a, b) => b.value > a.value ? b : a);
    return enIyi.value >= 2 ? enIyi.key : null;
  }

  TaramaSonucu tara(String metin) {
    final cumleler = _cumleler(metin);
    final tamKucuk = kucukHarf(metin);
    final bulunan = <String>{};
    final alinti = <String, String>{};

    Tarih? baslangic;
    Tarih? bitis;
    int? sureAy;
    int? ihbarGun;
    Para? bedel;
    int? vade;
    String? yetkiliYer;
    String? hukuk;
    var yenileme = false;
    var yurtdisiTahkim = false;

    for (final c in cumleler) {
      final s = c.kucuk;
      for (final e in _kurallar.entries) {
        if (e.value.hasMatch(s)) {
          bulunan.add(e.key);
          alinti.putIfAbsent(e.key, () => c.ozgun);
        }
      }

      final tarihler = _tarihAyikla(s);
      final basKelime = RegExp('başla|yürürlüğe\\s+gir|yürürlük\\s+tarihi|itibaren|imza\\s+tarihi').hasMatch(s);
      final bitKelime = RegExp('sona\\s+er|bitiş|tarihine\\s+kadar|kadar\\s+geçerli|son\\s+bulur').hasMatch(s);
      if (tarihler.isNotEmpty) {
        if (basKelime) baslangic ??= tarihler.first;
        if (bitKelime) {
          if (tarihler.length >= 2) {
            bitis ??= tarihler.last;
          } else if (!basKelime) {
            bitis ??= tarihler.first;
          }
        }
      }

      if (sureAy == null) {
        final m = _sure1.firstMatch(s) ?? _sure2.firstMatch(s);
        final n = m == null ? null : _sayiyaCevir(m[1]!);
        if (m != null && n != null) {
          sureAy = m[2] == 'yıl' ? n * 12 : n;
          alinti.putIfAbsent('sure', () => c.ozgun);
        }
      }

      if (_yenileme.hasMatch(s)) {
        yenileme = true;
        alinti.putIfAbsent('yenileme', () => c.ozgun);
      }

      if (ihbarGun == null && RegExp('ihbar|bildir|fesh|yenilenmeyeceğ|uzatılmayacağ|sona\\s+erdir').hasMatch(s)) {
        final m = _ihbar.firstMatch(s);
        final n = m == null ? null : _sayiyaCevir(m[1]!);
        if (m != null && n != null) {
          ihbarGun = switch (m[2]) { 'ay' => n * 30, 'hafta' => n * 7, _ => n };
          alinti.putIfAbsent('ihbar', () => c.ozgun);
        }
      }

      if (bedel == null && RegExp('bedel|ücret|fiyat|tutar').hasMatch(s) && !s.contains('cezai')) {
        final m = _tutar.firstMatch(s);
        if (m != null) {
          bedel = _paraOku(m);
          alinti.putIfAbsent('bedel', () => c.ozgun);
        }
      }

      if (vade == null) {
        final m = _odemeVadesi.firstMatch(s);
        if (m != null) vade = _sayiyaCevir(m[1]!);
      }

      if (yetkiliYer == null) {
        final m = _mahkeme.firstMatch(s);
        if (m != null) {
          yetkiliYer = _buyukBaslat(m[1]!);
          alinti.putIfAbsent('yetki', () => c.ozgun);
        }
      }

      if (hukuk == null && RegExp('tabi|uygulan|geçerli\\s+(?:hukuk|olacak)|yorumlan').hasMatch(s)) {
        final m = _hukuk.firstMatch(s);
        if (m != null) {
          hukuk = '${_buyukBaslat(m[1]!)} hukuku';
          alinti.putIfAbsent('hukuk', () => c.ozgun);
        }
      }

      if (bulunan.contains('tahkim') && _yurtdisiTahkim.hasMatch(s) && RegExp('tahkim|hakem').hasMatch(s)) {
        yurtdisiTahkim = true;
        alinti.putIfAbsent('yurtdisiTahkim', () => c.ozgun);
      }
    }

    final taraflar = <String>[];
    for (final m in _sirket.allMatches(metin)) {
      final ad = m[1]!.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (!taraflar.contains(ad)) taraflar.add(ad);
      if (taraflar.length == 4) break;
    }

    final tur = _turTahmin(tamKucuk);
    final b = <TaramaBulgusu>[];
    void ekle(String kod, String baslik, RiskSeviyesi seviye, String aciklama, [String? alintiKodu]) =>
        b.add(TaramaBulgusu(
            kod: kod, baslik: baslik, seviye: seviye, aciklama: aciklama, alinti: alinti[alintiKodu ?? kod] ?? ''));

    if (hukuk != null && hukuk != 'Türk hukuku') {
      ekle('yabanciHukuk', 'Yabancı hukuk seçilmiş', RiskSeviyesi.yuksek,
          '$hukuk uygulanacak. Uyuşmazlıkta yabancı hukuk danışmanlığı ve maliyet gerekir.', 'hukuk');
    }
    if (yurtdisiTahkim) {
      ekle('yurtdisiTahkim', 'Yurt dışı tahkim', RiskSeviyesi.yuksek,
          'Uyuşmazlık yurt dışında tahkimle çözülecek; masraf ve süre yüksek olabilir.');
    }
    if (bulunan.contains('sinirsizSorumluluk')) {
      ekle('sinirsizSorumluluk', 'Sınırsız sorumluluk', RiskSeviyesi.yuksek,
          'Sorumluluk için üst sınır yok. Tarafın kim olduğunu kontrol edin; bizse sınır önerin.');
    } else if (!bulunan.contains('sorumlulukSiniri') && tur != SozlesmeTuru.gizlilik) {
      ekle('sorumlulukSiniriYok', 'Sorumluluk sınırı yok', RiskSeviyesi.orta,
          'Sorumluluğu sözleşme bedeliyle sınırlayan bir madde bulunamadı.');
    }
    if (yenileme) {
      ekle(
          'otomatikYenileme',
          'Otomatik yenileme',
          ihbarGun == null ? RiskSeviyesi.orta : RiskSeviyesi.dusuk,
          ihbarGun == null
              ? 'Sözleşme kendiliğinden uzuyor ancak ihbar süresi bulunamadı.'
              : 'Sözleşme kendiliğinden uzuyor; bitişten $ihbarGun gün önce ihbar edilmezse yenilenir. Hatırlatma kurulacak.',
          'yenileme');
    }
    if (bulunan.contains('cezaiSart')) {
      ekle('cezaiSart', 'Cezai şart', RiskSeviyesi.orta,
          'Cezai şart var. Tutarını, hangi tarafa yüklendiğini ve ifayla birlikte istenip istenemeyeceğini kontrol edin.');
    }
    if (bulunan.contains('tekTarafliFesih')) {
      ekle('tekTarafliFesih', 'Tek taraflı fesih hakkı', RiskSeviyesi.orta,
          'Bir taraf gerekçe göstermeden feshedebiliyor. Hakkın kime tanındığını ve ihbar süresini kontrol edin.');
    }
    if (bulunan.contains('tekTarafliFiyat')) {
      ekle('tekTarafliFiyat', 'Tek taraflı fiyat değişikliği', RiskSeviyesi.orta,
          'Bedel tek taraflı değiştirilebiliyor; üst sınır veya endeks önerin.');
    }
    if (bulunan.contains('rekabetYasagi')) {
      ekle('rekabetYasagi', 'Rekabet yasağı', RiskSeviyesi.orta,
          'Rekabet yasağının süresi, yeri ve konusu makul ölçüde sınırlı olmalıdır.');
    }
    if (!bulunan.contains('mucbirSebep') && tur != SozlesmeTuru.gizlilik) {
      ekle('mucbirSebepYok', 'Mücbir sebep maddesi yok', RiskSeviyesi.dusuk,
          'Mücbir sebep hâlinde yükümlülüklerin askıya alınmasını düzenleyen madde bulunamadı.');
    }
    if (!bulunan.contains('gizlilik') && tur != SozlesmeTuru.kira) {
      ekle('gizlilikYok', 'Gizlilik maddesi yok', RiskSeviyesi.dusuk, 'Ticari bilgilerin korunmasına ilişkin madde bulunamadı.');
    }
    if (!bulunan.contains('kvkk') &&
        {SozlesmeTuru.hizmet, SozlesmeTuru.lisans, SozlesmeTuru.isSozlesmesi}.contains(tur)) {
      ekle('kvkkYok', 'KVKK maddesi yok', RiskSeviyesi.orta,
          'Kişisel veri aktarılacaksa 6698 sayılı Kanun kapsamında veri işleme hükümleri eklenmelidir.');
    }
    if (yetkiliYer == null && !bulunan.contains('tahkim')) {
      ekle('yetkiYok', 'Yetkili mahkeme belirtilmemiş', RiskSeviyesi.dusuk,
          'Uyuşmazlıkta yetkili mahkeme veya tahkim belirlenmemiş.');
    }
    if (bitis == null && sureAy == null && tur != SozlesmeTuru.isSozlesmesi) {
      ekle('sureYok', 'Süre bulunamadı', RiskSeviyesi.dusuk, 'Sözleşmenin bitiş tarihi veya süresi tespit edilemedi.');
    }

    return TaramaSonucu(
      tur: tur,
      taraflar: taraflar,
      baslangic: baslangic,
      bitis: bitis,
      sureAy: sureAy,
      otomatikYenileme: yenileme,
      ihbarSuresiGun: ihbarGun,
      bedel: bedel,
      odemeVadesiGun: vade,
      yetkiliYer: yetkiliYer,
      uygulanacakHukuk: hukuk,
      tahkim: bulunan.contains('tahkim'),
      bulunanMaddeler: bulunan,
      bulgular: b..sort((x, y) => y.seviye.index.compareTo(x.seviye.index)),
    );
  }

  static List<Tarih> _tarihAyikla(String s) =>
      _tarih.allMatches(s).map(_tarihOku).whereType<Tarih>().toList();
}
