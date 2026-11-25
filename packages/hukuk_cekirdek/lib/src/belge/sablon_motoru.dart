import '../sure/onay_durumu.dart';

/// Alan birleştirmeli belge şablonu.
///
/// Sözdizimi:
/// - `{{muvekkil.ad}}` alan değeri
/// - `{{#varsa dosya.esasNo}}...{{/varsa}}` alan doluysa içerik yazılır
///
/// Eksik alanlar sessizce boş bırakılmaz; `[EKSİK: alan]` olarak işaretlenir ve raporlanır.
class BelgeSablonu {
  const BelgeSablonu({
    required this.kod,
    required this.ad,
    required this.metin,
    this.surum = 1,
    this.onayDurumu = OnayDurumu.taslak,
    this.dayanak,
  });

  final String kod;
  final String ad;
  final String metin;
  final int surum;
  final OnayDurumu onayDurumu;

  /// Mevzuat veya içtihat kaynağı.
  final String? dayanak;

  static final _kosul = RegExp(r'\{\{#varsa\s+([\w.]+)\s*\}\}([\s\S]*?)\{\{/varsa\}\}');
  static final _alan = RegExp(r'\{\{\s*([\w.]+)\s*\}\}');

  /// Şablonda geçen tüm alanlar (koşul alanları dahil).
  Set<String> get alanlar => {
        for (final m in _kosul.allMatches(metin)) m.group(1)!,
        for (final m in _alan.allMatches(metin.replaceAll(_kosul, ''))) m.group(1)!,
        for (final m in _kosul.allMatches(metin))
          for (final i in _alan.allMatches(m.group(2)!)) i.group(1)!,
      };

  SablonCiktisi uygula(Map<String, String?> veri) {
    final eksik = <String>{};
    String? deger(String alan) {
      final v = veri[alan];
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    }

    var sonuc = metin.replaceAllMapped(_kosul, (m) => deger(m.group(1)!) == null ? '' : m.group(2)!);
    sonuc = sonuc.replaceAllMapped(_alan, (m) {
      final alan = m.group(1)!;
      final v = deger(alan);
      if (v == null) {
        eksik.add(alan);
        return '[EKSİK: $alan]';
      }
      return v;
    });
    return SablonCiktisi(metin: sonuc, eksikAlanlar: eksik, sablon: this);
  }

  // ---------------------------------------------------------------------------
  // Hazır şablonlar (TASLAK — ekipteki avukat metinleri gözden geçirip onaylayacak)
  // ---------------------------------------------------------------------------

  static const mazeretDilekcesi = BelgeSablonu(
    kod: 'MAZERET_DILEKCESI',
    ad: 'Duruşma mazeret dilekçesi',
    dayanak: 'HMK m.150 vd. (avukat kontrol edecek)',
    metin: '''{{mahkeme}} HAKİMLİĞİNE

DOSYA NO: {{dosya.esasNo}}

MAZERET SAHİBİ: {{muvekkil.ad}} vekili {{avukat.ad}}

KONU: {{durusma.tarih}} tarihli duruşmaya katılamama mazeretimizin bildirilmesidir.

AÇIKLAMALAR:
Yukarıda esas numarası yazılı dosyanın {{durusma.tarih}} tarihli duruşması ile aynı gün ve saatte {{mazeret.aciklama}} nedeniyle duruşmaya katılmam mümkün olmayacaktır.
{{#varsa mazeret.belge}}Mazeretimize ilişkin belge ({{mazeret.belge}}) ekte sunulmuştur.
{{/varsa}}
SONUÇ VE İSTEM: Mazeretimin kabulü ile duruşmanın ertelenmesini saygılarımla vekaleten arz ve talep ederim. {{bugun}}

{{muvekkil.ad}} Vekili
{{avukat.ad}}''',
  );

  static const ihtarname = BelgeSablonu(
    kod: 'IHTARNAME_ALACAK',
    ad: 'Alacak ihtarnamesi',
    dayanak: 'TBK m.117 (temerrüt) — avukat kontrol edecek',
    metin: '''İHTARNAME

KEŞİDECİ: {{muvekkil.ad}}
VEKİLİ: {{avukat.ad}}
MUHATAP: {{karsiTaraf.ad}}{{#varsa karsiTaraf.adres}}, {{karsiTaraf.adres}}{{/varsa}}

KONU: {{alacak.tutar}} tutarındaki alacağın ödenmesi ihtarıdır.

Müvekkilimizin {{alacak.dayanak}} kaynaklı {{alacak.tutar}} tutarındaki alacağı vadesinde ödenmemiştir. İşbu ihtarnamenin tebliğinden itibaren {{odeme.sureGun}} gün içinde söz konusu tutarın ödenmemesi halinde yasal yollara başvurulacağını, doğacak faiz, masraf ve vekâlet ücretinin tarafınıza ait olacağını ihtaren bildiririz. {{bugun}}

{{muvekkil.ad}} Vekili
{{avukat.ad}}''',
  );

  static const ucretSozlesmesi = BelgeSablonu(
    kod: 'UCRET_SOZLESMESI',
    ad: 'Avukatlık ücret sözleşmesi',
    dayanak: 'Av. K. m.163-164 (avukat kontrol edecek; yüzde ücret %25 sınırı)',
    metin: '''AVUKATLIK ÜCRET SÖZLEŞMESİ

İŞ SAHİBİ: {{muvekkil.ad}}{{#varsa muvekkil.kimlikNo}} (TCKN/VKN: {{muvekkil.kimlikNo}}){{/varsa}}
AVUKAT: {{avukat.ad}}, {{buro.ad}}

1. KONU: {{is.tanimi}}
2. ÜCRET: {{ucret.tutar}} ({{ucret.odemeSekli}})
3. MASRAFLAR: Harç, posta, bilirkişi ve benzeri yargılama giderleri iş sahibine aittir; avans olarak peşin ödenir.
4. KARŞI TARAF VEKÂLET ÜCRETİ: Avukatlık Kanunu m.164 uyarınca avukata aittir.
5. KİŞİSEL VERİLER: İş sahibinin kişisel verileri KVKK kapsamında yalnızca işin yürütülmesi amacıyla işlenir.

Tarih: {{bugun}}

İŞ SAHİBİ                    AVUKAT
{{muvekkil.ad}}               {{avukat.ad}}''',
  );

  static const List<BelgeSablonu> hazir = [mazeretDilekcesi, ihtarname, ucretSozlesmesi];
}

class SablonCiktisi {
  const SablonCiktisi({required this.metin, required this.eksikAlanlar, required this.sablon});

  final String metin;
  final Set<String> eksikAlanlar;
  final BelgeSablonu sablon;

  bool get tamam => eksikAlanlar.isEmpty;
}
