import '../sure/elektronik_tebligat.dart';
import '../taraf/isim_eslestirme.dart';
import '../takvim/tarih.dart';
import 'dosya.dart';

enum TebligatKanali {
  uets('PTT UETS'),
  kep('KEP'),
  uyap('UYAP'),
  elektronik('Elektronik tebligat'),
  fiziki('Fiziki tebligat');

  const TebligatKanali(this.ad);

  final String ad;

  /// Ulaşmayı izleyen 5. gün tebliğ sayılan kanallar.
  bool get elektronikMi => this != TebligatKanali.fiziki;
}

enum EslesmeDurumu { eslesmedi, onerildi, eslesti }

/// Gelen resmî evrak. Ulaşma ve tebliğ tarihi ayrı tutulur.
class Tebligat {
  Tebligat({
    required this.id,
    required this.kiraciId,
    required this.kanal,
    required this.ulasmaTarihi,
    required this.gonderen,
    required this.konu,
    Tarih? tebligTarihi,
    this.esasNo,
    this.taraflar = const [],
    this.belgeOzeti,
    this.dosyaId,
    this.eslesmeDurumu = EslesmeDurumu.eslesmedi,
  }) : tebligTarihi = tebligTarihi ??
            (kanal.elektronikMi ? ElektronikTebligat.tebligTarihi(ulasmaTarihi) : ulasmaTarihi);

  final String id;
  final String kiraciId;
  final TebligatKanali kanal;
  final Tarih ulasmaTarihi;

  /// Hukuken tebliğ edilmiş sayılan gün; süreler buradan başlar.
  final Tarih tebligTarihi;

  /// Mahkeme, icra dairesi veya kurum.
  final String gonderen;
  final String konu;
  final String? esasNo;
  final List<String> taraflar;

  /// Orijinal belgenin SHA-256 özeti; mükerrer kontrolü ve delil bütünlüğü için.
  final String? belgeOzeti;
  final String? dosyaId;
  final EslesmeDurumu eslesmeDurumu;

  Tebligat dosyayaBagla(String dosya) => Tebligat(
        id: id,
        kiraciId: kiraciId,
        kanal: kanal,
        ulasmaTarihi: ulasmaTarihi,
        tebligTarihi: tebligTarihi,
        gonderen: gonderen,
        konu: konu,
        esasNo: esasNo,
        taraflar: taraflar,
        belgeOzeti: belgeOzeti,
        dosyaId: dosya,
        eslesmeDurumu: EslesmeDurumu.eslesti,
      );

  /// Aynı evrakın ikinci kez kaydını önleyen anahtar.
  String get tekillikAnahtari =>
      belgeOzeti ?? '${kanal.name}|${IsimEslestirme.normallestir(gonderen)}|$ulasmaTarihi|${IsimEslestirme.normallestir(konu)}';
}

class EslesmeOnerisi {
  const EslesmeOnerisi({required this.dosya, required this.puan, required this.gerekce});

  final Dosya dosya;

  /// 0-1 arası güven.
  final double puan;
  final String gerekce;
}

/// Tebligatı açık dosyalarla eşleştirir; emin olunamayanlar ekip kuyruğuna düşer.
class TebligatEslestirici {
  TebligatEslestirici._();

  /// Bu puanın üzerindeki tek öneri otomatik eşleştirilebilir (yine de insan görür).
  static const double otomatikEsik = 0.95;

  static List<EslesmeOnerisi> oner(Tebligat t, Iterable<Dosya> dosyalar, {Map<String, List<String>>? dosyaTaraflari}) {
    final sonuc = <EslesmeOnerisi>[];
    final tEsas = t.esasNo == null ? null : esasNoNormallestir(t.esasNo!);
    for (final d in dosyalar.where((d) => d.acik && d.kiraciId == t.kiraciId)) {
      var puan = 0.0;
      final gerekceler = <String>[];
      if (tEsas != null && d.esasNo != null && esasNoNormallestir(d.esasNo!) == tEsas) {
        final ayniMahkeme = d.mahkeme != null && IsimEslestirme.benzerlik(d.mahkeme!, t.gonderen) >= 0.85;
        puan = ayniMahkeme ? 1.0 : 0.8;
        gerekceler.add(ayniMahkeme ? 'Esas no ve mahkeme aynı' : 'Esas no aynı, mahkeme farklı');
      }
      final taraflar = dosyaTaraflari?[d.id] ?? const <String>[];
      var tarafPuani = 0.0;
      for (final a in t.taraflar) {
        for (final b in taraflar) {
          final s = IsimEslestirme.benzerlik(a, b);
          if (s > tarafPuani) tarafPuani = s;
        }
      }
      if (tarafPuani >= IsimEslestirme.varsayilanEsik) {
        final tp = 0.5 * tarafPuani;
        if (tp > puan) puan = tp;
        gerekceler.add('Taraf adı eşleşiyor');
      }
      if (puan > 0) sonuc.add(EslesmeOnerisi(dosya: d, puan: puan, gerekce: gerekceler.join(', ')));
    }
    sonuc.sort((a, b) => b.puan.compareTo(a.puan));
    return sonuc;
  }

  /// Tek ve yüksek güvenli öneri varsa onu döner; aksi halde kuyruğa düşmesi gerekir.
  static Dosya? otomatikEslesme(List<EslesmeOnerisi> oneriler) {
    final yuksek = oneriler.where((o) => o.puan >= otomatikEsik).toList();
    return yuksek.length == 1 ? yuksek.single.dosya : null;
  }
}
