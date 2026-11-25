import '../sure/onay_durumu.dart';
import '../takvim/tarih.dart';

enum VeriKategorisi {
  davaDosyasi('Dava ve icra dosyaları'),
  danismanlik('Danışmanlık dosyaları'),
  muhasebe('Makbuz, fatura ve muhasebe kayıtları'),
  adayKaydi('Kabul edilmeyen iş başvuruları (çıkar çatışması kaydı)'),
  iletisim('Müvekkil yazışmaları ve portal mesajları');

  const VeriKategorisi(this.ad);
  final String ad;
}

/// Bir veri kategorisinin, başlangıç olayından (dosyanın kapanışı vb.) itibaren saklanma süresi.
/// Süreler TASLAKTIR; büronun saklama ve imha politikasında avukat tarafından belirlenir.
class SaklamaKurali {
  const SaklamaKurali({required this.kategori, required this.sureYil, required this.dayanak, this.onayDurumu = OnayDurumu.taslak});

  final VeriKategorisi kategori;
  final int sureYil;
  final String dayanak;
  final OnayDurumu onayDurumu;

  static const varsayilanlar = [
    SaklamaKurali(
        kategori: VeriKategorisi.davaDosyasi,
        sureYil: 10,
        dayanak: 'Genel zamanaşımı (TBK m.146) ve mesleki sorumluluk; büro politikasıyla belirlenecek'),
    SaklamaKurali(
        kategori: VeriKategorisi.danismanlik, sureYil: 10, dayanak: 'Genel zamanaşımı (TBK m.146); büro politikasıyla belirlenecek'),
    SaklamaKurali(kategori: VeriKategorisi.muhasebe, sureYil: 10, dayanak: 'TTK m.82; VUK m.253'),
    SaklamaKurali(kategori: VeriKategorisi.adayKaydi, sureYil: 2, dayanak: 'Büro politikasıyla belirlenecek'),
    SaklamaKurali(kategori: VeriKategorisi.iletisim, sureYil: 10, dayanak: 'İlgili dosyanın süresine bağlı'),
  ];
}

/// Saklama takibindeki kayıt (dosya, arşiv kutusu, müvekkil kaydı...).
class SaklamaKaydi {
  const SaklamaKaydi({
    required this.id,
    required this.ad,
    required this.kategori,
    this.kapanis,
    this.yasalSaklamaEngeli,
  });

  final String id;
  final String ad;
  final VeriKategorisi kategori;

  /// Saklama süresinin başladığı tarih (ör. dosyanın kapanışı). Yoksa süre başlamamıştır.
  final Tarih? kapanis;

  /// Devam eden uyuşmazlık, denetim veya resmî talep varsa gerekçesi; doluysa imha edilemez.
  final String? yasalSaklamaEngeli;
}

enum ImhaDurumu {
  sureBaslamadi('Süre başlamadı'),
  saklaniyor('Saklanıyor'),
  imhayaHazir('İmhaya hazır'),
  engelli('Yasal saklama engeli');

  const ImhaDurumu(this.ad);
  final String ad;
}

class ImhaDegerlendirmesi {
  const ImhaDegerlendirmesi(this.kayit, this.durum, this.imhaTarihi);
  final SaklamaKaydi kayit;
  final ImhaDurumu durum;
  final Tarih? imhaTarihi;
}

enum ImhaYontemi {
  silme('Silme'),
  yokEtme('Yok etme'),
  anonimlestirme('Anonim hâle getirme');

  const ImhaYontemi(this.ad);
  final String ad;
}

class ImhaTutanagi {
  ImhaTutanagi({
    required this.no,
    required this.tarih,
    required this.kayitIdleri,
    required this.yontem,
    required this.hazirlayan,
  });

  final String no;
  final Tarih tarih;
  final List<String> kayitIdleri;
  final ImhaYontemi yontem;
  final String hazirlayan;
  String? onaylayan;
  Tarih? onayTarihi;

  bool get onaylandi => onaylayan != null;

  /// Dört göz ilkesi: hazırlayan kendi tutanağını onaylayamaz.
  void onayla(String kullanici, Tarih tarih) {
    if (onaylandi) throw StateError('Tutanak zaten onaylandı.');
    if (kullanici == hazirlayan) throw StateError('Tutanağı hazırlayan onaylayamaz.');
    onaylayan = kullanici;
    onayTarihi = tarih;
  }
}

class SaklamaVeImha {
  SaklamaVeImha({List<SaklamaKurali> kurallar = SaklamaKurali.varsayilanlar, this.sonPeriyodikImha})
      : _kurallar = {for (final k in kurallar) k.kategori: k};

  /// Kişisel Verilerin Silinmesi, Yok Edilmesi veya Anonim Hale Getirilmesi Hakkında Yönetmelik m.11:
  /// periyodik imha aralığı 6 ayı geçemez.
  static const periyodikImhaAyi = 6;

  final Map<VeriKategorisi, SaklamaKurali> _kurallar;
  final List<ImhaTutanagi> tutanaklar = [];
  Tarih? sonPeriyodikImha;
  int _sira = 0;

  Iterable<SaklamaKurali> get kurallar => _kurallar.values;

  ImhaDegerlendirmesi degerlendir(SaklamaKaydi k, Tarih bugun) {
    final kapanis = k.kapanis;
    if (k.yasalSaklamaEngeli != null && k.yasalSaklamaEngeli!.trim().isNotEmpty) {
      return ImhaDegerlendirmesi(k, ImhaDurumu.engelli, null);
    }
    if (kapanis == null) return ImhaDegerlendirmesi(k, ImhaDurumu.sureBaslamadi, null);
    final kural = _kurallar[k.kategori];
    if (kural == null) return ImhaDegerlendirmesi(k, ImhaDurumu.saklaniyor, null);
    final imha = kapanis.yilEkle(kural.sureYil);
    return ImhaDegerlendirmesi(k, bugun.isBefore(imha) ? ImhaDurumu.saklaniyor : ImhaDurumu.imhayaHazir, imha);
  }

  List<ImhaDegerlendirmesi> degerlendirTumu(Iterable<SaklamaKaydi> kayitlar, Tarih bugun) =>
      kayitlar.map((k) => degerlendir(k, bugun)).toList()
        ..sort((a, b) {
          final d = b.durum.index.compareTo(a.durum.index);
          if (d != 0) return d;
          final ta = a.imhaTarihi, tb = b.imhaTarihi;
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });

  /// Sonraki periyodik imhanın en geç tarihi; hiç yapılmadıysa null.
  Tarih? sonrakiPeriyodikImha() => sonPeriyodikImha?.ayEkle(periyodikImhaAyi);

  bool periyodikImhaGecikti(Tarih bugun) {
    final s = sonrakiPeriyodikImha();
    return s != null && bugun.isAfter(s);
  }

  /// Yalnızca imhaya hazır kayıtlar için tutanak hazırlanır.
  ImhaTutanagi tutanakHazirla({
    required Iterable<SaklamaKaydi> secilen,
    required ImhaYontemi yontem,
    required String hazirlayan,
    required Tarih bugun,
  }) {
    final l = secilen.toList();
    if (l.isEmpty) throw ArgumentError('İmha edilecek kayıt seçilmedi.');
    for (final k in l) {
      final d = degerlendir(k, bugun);
      if (d.durum != ImhaDurumu.imhayaHazir) throw StateError('${k.ad}: ${d.durum.ad.toLowerCase()}; imha edilemez.');
    }
    _sira++;
    final t = ImhaTutanagi(
      no: 'IT-${bugun.yil}-${_sira.toString().padLeft(3, '0')}',
      tarih: bugun,
      kayitIdleri: [for (final k in l) k.id],
      yontem: yontem,
      hazirlayan: hazirlayan,
    );
    tutanaklar.add(t);
    return t;
  }

  /// Onaylanan tutanakla periyodik imha tarihi güncellenir.
  void tutanakOnayla(ImhaTutanagi t, String onaylayan, Tarih bugun) {
    t.onayla(onaylayan, bugun);
    sonPeriyodikImha = bugun;
  }
}
