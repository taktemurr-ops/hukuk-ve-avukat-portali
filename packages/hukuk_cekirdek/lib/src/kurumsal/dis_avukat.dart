import '../hesaplama/para.dart';
import '../takvim/tarih.dart';

class DisAvukat {
  const DisAvukat({
    required this.id,
    required this.buro,
    required this.sorumluAvukat,
    required this.eposta,
    this.uzmanliklar = const [],
    this.saatlikUcret,
  });

  final String id;
  final String buro;
  final String sorumluAvukat;
  final String eposta;
  final List<String> uzmanliklar;
  final Para? saatlikUcret;
}

enum FaturaDurumu {
  bekliyor('Onay bekliyor'),
  onaylandi('Onaylandı'),
  finansaGonderildi('Finansa gönderildi'),
  reddedildi('Reddedildi');

  const FaturaDurumu(this.ad);
  final String ad;

  bool get harcamaSayilir => this == onaylandi || this == finansaGonderildi;
}

class DisAvukatFaturasi {
  DisAvukatFaturasi({required this.id, required this.no, required this.tarih, required this.tutar, required this.aciklama});

  final String id;
  final String no;
  final Tarih tarih;

  /// KDV hariç tutar.
  final Para tutar;
  final String aciklama;
  FaturaDurumu durum = FaturaDurumu.bekliyor;
  String? onaylayan;
  String? retGerekcesi;
}

class ButceArtisi {
  const ButceArtisi(this.tutar, this.gerekce, this.onaylayan, this.tarih);
  final Para tutar;
  final String gerekce;
  final String onaylayan;
  final Tarih tarih;
}

enum ButceDurumu {
  normal('Bütçe içinde'),
  uyari('Bütçenin %80\'i aşıldı'),
  asim('Bütçe aşıldı');

  const ButceDurumu(this.ad);
  final String ad;
}

/// Dış avukata verilen iş (dava, danışmanlık, icra takibi...) ve bütçesi.
class DisAvukatIsi {
  DisAvukatIsi({
    required this.id,
    required this.disAvukatId,
    required this.konu,
    required this.ilkButce,
    required this.baslangic,
    this.dosyaId,
    this.talepId,
  });

  static const uyariOrani = 80;

  final String id;
  final String disAvukatId;
  final String konu;
  final Para ilkButce;
  final Tarih baslangic;
  final String? dosyaId;
  final String? talepId;
  bool kapali = false;
  final List<DisAvukatFaturasi> faturalar = [];
  final List<ButceArtisi> butceArtislari = [];

  Para get butce => butceArtislari.fold(ilkButce, (a, b) => a + b.tutar);

  Para get harcanan => faturalar.where((f) => f.durum.harcamaSayilir).fold(Para.sifir, (a, f) => a + f.tutar);

  Para get bekleyen => faturalar.where((f) => f.durum == FaturaDurumu.bekliyor).fold(Para.sifir, (a, f) => a + f.tutar);

  /// Harcanan / bütçe yüzdesi.
  int get kullanimYuzdesi => butce.kurus == 0 ? 0 : (harcanan.kurus * 100 / butce.kurus).round();

  ButceDurumu get butceDurumu {
    if (harcanan > butce) return ButceDurumu.asim;
    if (harcanan.kurus * 100 >= butce.kurus * uyariOrani) return ButceDurumu.uyari;
    return ButceDurumu.normal;
  }

  DisAvukatFaturasi faturaEkle({required String id, required String no, required Tarih tarih, required Para tutar, required String aciklama}) {
    if (kapali) throw StateError('Kapalı işe fatura eklenemez.');
    if (tutar.kurus <= 0) throw ArgumentError('Fatura tutarı sıfırdan büyük olmalı.');
    if (faturalar.any((f) => f.no.trim().toLowerCase() == no.trim().toLowerCase())) {
      throw StateError('Bu numarayla fatura zaten kayıtlı.');
    }
    final f = DisAvukatFaturasi(id: id, no: no.trim(), tarih: tarih, tutar: tutar, aciklama: aciklama.trim());
    faturalar.add(f);
    return f;
  }

  /// Onay bütçeyi aşacaksa önce gerekçeli bütçe artışı gerekir.
  void faturaOnayla(DisAvukatFaturasi f, String onaylayan) {
    if (f.durum != FaturaDurumu.bekliyor) throw StateError('Fatura ${f.durum.ad.toLowerCase()}.');
    if (harcanan + f.tutar > butce) {
      throw StateError('Onay bütçeyi aşıyor (${(harcanan + f.tutar).bicimli} / ${butce.bicimli}); önce bütçe artışı onaylanmalı.');
    }
    f
      ..durum = FaturaDurumu.onaylandi
      ..onaylayan = onaylayan;
  }

  void faturaReddet(DisAvukatFaturasi f, String onaylayan, String gerekce) {
    if (f.durum != FaturaDurumu.bekliyor) throw StateError('Fatura ${f.durum.ad.toLowerCase()}.');
    if (gerekce.trim().length < 5) throw ArgumentError('Ret gerekçesi yazılmalı.');
    f
      ..durum = FaturaDurumu.reddedildi
      ..onaylayan = onaylayan
      ..retGerekcesi = gerekce.trim();
  }

  void finansaGonder(DisAvukatFaturasi f) {
    if (f.durum != FaturaDurumu.onaylandi) throw StateError('Yalnızca onaylı fatura finansa gönderilir.');
    f.durum = FaturaDurumu.finansaGonderildi;
  }

  void butceArtir(Para tutar, String gerekce, String onaylayan, Tarih tarih) {
    if (tutar.kurus <= 0) throw ArgumentError('Artış tutarı sıfırdan büyük olmalı.');
    if (gerekce.trim().length < 10) throw ArgumentError('Bütçe artışı için gerekçe en az 10 karakter olmalı.');
    butceArtislari.add(ButceArtisi(tutar, gerekce.trim(), onaylayan, tarih));
  }
}

/// Dış avukat bazında harcama özeti.
class DisAvukatOzeti {
  const DisAvukatOzeti(this.avukat, this.isSayisi, this.acikIs, this.butce, this.harcanan, this.bekleyen);
  final DisAvukat avukat;
  final int isSayisi;
  final int acikIs;
  final Para butce;
  final Para harcanan;
  final Para bekleyen;

  static List<DisAvukatOzeti> hesapla(Iterable<DisAvukat> avukatlar, Iterable<DisAvukatIsi> isler) => [
        for (final a in avukatlar)
          () {
            final l = isler.where((i) => i.disAvukatId == a.id).toList();
            return DisAvukatOzeti(
              a,
              l.length,
              l.where((i) => !i.kapali).length,
              l.fold(Para.sifir, (t, i) => t + i.butce),
              l.fold(Para.sifir, (t, i) => t + i.harcanan),
              l.fold(Para.sifir, (t, i) => t + i.bekleyen),
            );
          }(),
      ]..sort((x, y) => y.harcanan.compareTo(x.harcanan));
}
