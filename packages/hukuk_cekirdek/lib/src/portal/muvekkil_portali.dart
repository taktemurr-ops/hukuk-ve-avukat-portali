import '../belge/belge.dart';
import '../dosya/dosya.dart';
import '../dosya/gorev.dart';
import '../takvim/tarih.dart';

/// Müvekkil ile büro arasındaki dosya bazlı yazışma.
class PortalMesaji {
  const PortalMesaji({
    required this.id,
    required this.dosyaId,
    required this.gonderen,
    required this.muvekkildenMi,
    required this.metin,
    required this.zaman,
    this.okundu = false,
  });

  static const azamiUzunluk = 4000;

  final String id;
  final String dosyaId;
  final String gonderen;
  final bool muvekkildenMi;
  final String metin;
  final DateTime zaman;
  final bool okundu;

  PortalMesaji okunduIsaretle() => PortalMesaji(
      id: id, dosyaId: dosyaId, gonderen: gonderen, muvekkildenMi: muvekkildenMi, metin: metin, zaman: zaman, okundu: true);

  /// Mesaj metni kontrolü; hata yoksa null.
  static String? dogrula(String metin) {
    final t = metin.trim();
    if (t.isEmpty) return 'Mesaj boş olamaz.';
    if (t.length > azamiUzunluk) return 'Mesaj en fazla $azamiUzunluk karakter olabilir.';
    return null;
  }
}

class PaylasilanBelge {
  const PaylasilanBelge({required this.id, required this.ad, required this.tarih, required this.dosyaAdi});
  final String id;
  final String ad;
  final Tarih tarih;
  final String dosyaAdi;
}

/// Müvekkilin portalda gördüğü dosya özeti. Süreler, görevler, iç notlar ve ekip bilgisi bilinçli olarak yoktur.
class MuvekkilDosyaOzeti {
  const MuvekkilDosyaOzeti({
    required this.dosyaId,
    required this.baslik,
    required this.tur,
    required this.asama,
    this.mahkeme,
    this.esasNo,
    this.sonrakiDurusma,
    this.durusmaYeri,
    this.belgeler = const [],
    this.mesajlar = const [],
  });

  final String dosyaId;
  final String baslik;
  final String tur;
  final String asama;
  final String? mahkeme;
  final String? esasNo;
  final DateTime? sonrakiDurusma;
  final String? durusmaYeri;
  final List<PaylasilanBelge> belgeler;
  final List<PortalMesaji> mesajlar;

  /// Büro tarafından gönderilmiş, müvekkilin henüz okumadığı mesajlar.
  int get okunmamis => mesajlar.where((m) => !m.muvekkildenMi && !m.okundu).length;
}

class MuvekkilPortali {
  MuvekkilPortali._();

  /// Müvekkilin görebileceği dosyalar: müvekkili olduğu VE büronun portalda paylaştığı dosyalar.
  /// Belgeler yalnızca açıkça paylaşılmışsa ve gizli değilse görünür.
  static List<MuvekkilDosyaOzeti> ozetler({
    required Set<String> muvekkilinDosyalari,
    required Set<String> portaldaPaylasilan,
    required Iterable<Dosya> dosyalar,
    required Iterable<Durusma> durusmalar,
    required Iterable<Belge> belgeler,
    required Set<String> paylasilanBelgeler,
    required Iterable<PortalMesaji> mesajlar,
    required DateTime simdi,
  }) {
    final sonuc = <MuvekkilDosyaOzeti>[];
    for (final d in dosyalar) {
      if (!muvekkilinDosyalari.contains(d.id) || !portaldaPaylasilan.contains(d.id)) continue;
      final gelecek = durusmalar.where((x) => x.dosyaId == d.id && x.baslangic.isAfter(simdi)).toList()
        ..sort((a, b) => a.baslangic.compareTo(b.baslangic));
      final paylasilan = belgeler
          .where((x) => x.dosyaId == d.id && !x.gizli && paylasilanBelgeler.contains(x.id))
          .map((x) => PaylasilanBelge(id: x.id, ad: x.ad, tarih: x.guncel.tarih, dosyaAdi: x.guncel.dosyaAdi))
          .toList()
        ..sort((x, y) => y.tarih.compareTo(x.tarih));
      final m = mesajlar.where((x) => x.dosyaId == d.id).toList()..sort((a, b) => a.zaman.compareTo(b.zaman));
      sonuc.add(MuvekkilDosyaOzeti(
        dosyaId: d.id,
        baslik: d.baslik,
        tur: d.tur.ad,
        asama: d.asama.ad,
        mahkeme: d.mahkeme,
        esasNo: d.esasNo,
        sonrakiDurusma: gelecek.isEmpty ? null : gelecek.first.baslangic,
        durusmaYeri: gelecek.isEmpty ? null : gelecek.first.yer,
        belgeler: paylasilan,
        mesajlar: m,
      ));
    }
    return sonuc;
  }
}
