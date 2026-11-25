import 'package:flutter/foundation.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

/// Kaydedilmiş iş kabul kararı.
class KayitliKarar {
  const KayitliKarar({required this.adaylar, required this.rapor, required this.karar, required this.zaman});

  final List<AdayTaraf> adaylar;
  final CikarCatismasiRaporu rapor;
  final CikarCatismasiKarari karar;
  final DateTime zaman;
}

/// Geliştirme için bellekte çalışan veri deposu. Sunucu hazır olduğunda aynı
/// yüzeyi koruyan Serverpod uygulamasıyla değiştirilecek.
class BellekVeriDeposu extends ChangeNotifier {
  BellekVeriDeposu(this.kiraciId);

  /// Demo verisiyle doldurulmuş depo. [avukatId] oturumdaki kullanıcıdır.
  factory BellekVeriDeposu.demo({required String kiraciId, required String avukatId}) {
    final d = BellekVeriDeposu(kiraciId);
    Kisi k(String id, KisiTuru tur, String ad, {String? no, String? eposta}) =>
        Kisi(id: id, kiraciId: kiraciId, tur: tur, ad: ad, kimlikNo: no, eposta: eposta);

    d._kisiler.addAll([
      k('abc', KisiTuru.tuzel, 'ABC Gıda Sanayi ve Ticaret A.Ş.', no: '1234567890', eposta: 'hukuk@abcgida.com.tr'),
      k('abcHolding', KisiTuru.tuzel, 'ABC Holding A.Ş.'),
      k('ayse', KisiTuru.gercek, 'Ayşe Kara', no: '10000000146'),
      k('demirci', KisiTuru.gercek, 'Mehmet Demirci'),
      k('delta', KisiTuru.tuzel, 'Delta İnşaat Ltd. Şti.', no: '9876543217'),
      k('orman', KisiTuru.tuzel, 'Orman Enerji A.Ş.'),
    ]);
    d._iliskiler.add(const KisiIliskisi(kisiA: 'abcHolding', kisiB: 'abc', tur: IliskiTuru.istirak));
    d._dosyaKayitlari.addAll(const [
      DosyaTarafKaydi(dosyaId: 'd1', dosyaAdi: 'ABC Gıda - Tedarik alacağı', kisiId: 'abc', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(dosyaId: 'd1', dosyaAdi: 'ABC Gıda - Tedarik alacağı', kisiId: 'delta', sifat: TarafSifati.karsiTaraf),
      DosyaTarafKaydi(dosyaId: 'd2', dosyaAdi: 'Kara - İşe iade', kisiId: 'ayse', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(dosyaId: 'd2', dosyaAdi: 'Kara - İşe iade', kisiId: 'demirci', sifat: TarafSifati.karsiTaraf),
      DosyaTarafKaydi(dosyaId: 'd3', dosyaAdi: 'Holding birleşme danışmanlığı', kisiId: 'abcHolding', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(
          dosyaId: 'd4', dosyaAdi: 'Orman Enerji iç soruşturma', kisiId: 'orman', sifat: TarafSifati.muvekkil, gizli: true),
    ]);
    d._vekaletnameler.addAll([
      Vekaletname(
        id: 'v1',
        kiraciId: kiraciId,
        muvekkilId: 'abc',
        avukatlar: {avukatId},
        duzenlemeTarihi: Tarih(2025, 3, 14),
        noter: 'Kadıköy 5. Noterliği',
        yevmiyeNo: '04512',
        ozelYetkiler: const {OzelYetki.sulh, OzelYetki.tevkil, OzelYetki.ahzuKabz, OzelYetki.ibra},
        asilEvrakYeri: 'Arşiv dolabı 2, klasör 7',
      ),
      Vekaletname(
        id: 'v2',
        kiraciId: kiraciId,
        muvekkilId: 'ayse',
        avukatlar: {avukatId},
        duzenlemeTarihi: Tarih(2026, 2, 2),
        noter: 'Beşiktaş 12. Noterliği',
        yevmiyeNo: '00987',
        genel: false,
        dosyalar: const {'d2'},
      ),
    ]);
    return d;
  }

  final String kiraciId;
  final List<Kisi> _kisiler = [];
  final List<KisiIliskisi> _iliskiler = [];
  final List<DosyaTarafKaydi> _dosyaKayitlari = [];
  final List<Vekaletname> _vekaletnameler = [];
  final List<KayitliKarar> _kararlar = [];
  int _sayac = 0;

  List<Kisi> get kisiler => List.unmodifiable(_kisiler);
  List<DosyaTarafKaydi> get dosyaKayitlari => List.unmodifiable(_dosyaKayitlari);
  List<Vekaletname> get vekaletnameler => List.unmodifiable(_vekaletnameler);
  List<KayitliKarar> get kararlar => List.unmodifiable(_kararlar);

  Kisi? kisi(String id) {
    for (final k in _kisiler) {
      if (k.id == id) return k;
    }
    return null;
  }

  int dosyaSayisi(String kisiId) => _dosyaKayitlari.where((d) => d.kisiId == kisiId).map((d) => d.dosyaId).toSet().length;

  List<Kisi> ara(String sorgu) {
    final s = sorgu.trim();
    if (s.isEmpty) return kisiler;
    final n = IsimEslestirme.normallestir(s);
    return _kisiler
        .where((k) =>
            (k.kimlikNo?.contains(s) ?? false) ||
            k.tumAdlar.any((a) => IsimEslestirme.normallestir(a).contains(n)) ||
            IsimEslestirme.benzerlik(s, k.ad) >= IsimEslestirme.varsayilanEsik)
        .toList();
  }

  CikarCatismasiTarayici get tarayici =>
      CikarCatismasiTarayici(kisiler: _kisiler, iliskiler: _iliskiler, dosyaKayitlari: _dosyaKayitlari);

  Kisi kisiEkle({
    required KisiTuru tur,
    required String ad,
    String? kimlikNo,
    String? eposta,
    String? telefon,
  }) {
    _sayac++;
    final yeni = Kisi(
      id: 'yeni$_sayac',
      kiraciId: kiraciId,
      tur: tur,
      ad: ad.trim(),
      kimlikNo: (kimlikNo?.trim().isEmpty ?? true) ? null : kimlikNo!.trim(),
      eposta: (eposta?.trim().isEmpty ?? true) ? null : eposta!.trim(),
      telefon: (telefon?.trim().isEmpty ?? true) ? null : telefon!.trim(),
    );
    _kisiler.add(yeni);
    notifyListeners();
    return yeni;
  }

  void kararKaydet(KayitliKarar karar) {
    _kararlar.add(karar);
    notifyListeners();
  }
}
