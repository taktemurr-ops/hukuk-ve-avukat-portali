import '../takvim/tarih.dart';

/// Açıkça verilmesi gereken özel yetkiler (HMK m.74 esas alınmıştır; avukat onayı bekler).
enum OzelYetki {
  sulh('Sulh olma'),
  hakimiRet('Hâkimi reddetme'),
  davayiKabul('Davayı kabul'),
  feragat('Davadan feragat'),
  yemin('Yemin teklifi, kabulü veya reddi'),
  tevkil('Başkasını tevkil (yetki belgesi verme)'),
  haczinKaldirilmasi('Haczin kaldırılması'),
  iflas('İflas isteme'),
  tahkim('Tahkim ve hakem sözleşmesi'),
  ibra('İbra'),
  ahzuKabz('Ahzu kabz (para ve mal tahsili)');

  const OzelYetki(this.ad);

  final String ad;
}

enum VekaletDurumu { gecerli, azil, istifa, sureDoldu }

class Vekaletname {
  const Vekaletname({
    required this.id,
    required this.kiraciId,
    required this.muvekkilId,
    required this.avukatlar,
    required this.duzenlemeTarihi,
    this.noter,
    this.yevmiyeNo,
    this.genel = true,
    this.ozelYetkiler = const {},
    this.dosyalar = const {},
    this.bitisTarihi,
    this.durum = VekaletDurumu.gecerli,
    this.durumTarihi,
    this.asilEvrakYeri,
  });

  final String id;
  final String kiraciId;
  final String muvekkilId;

  /// Vekil avukatların kullanıcı kimlikleri.
  final Set<String> avukatlar;
  final Tarih duzenlemeTarihi;
  final String? noter;
  final String? yevmiyeNo;

  /// Genel vekâletname tüm işleri kapsar; değilse yalnızca [dosyalar].
  final bool genel;
  final Set<OzelYetki> ozelYetkiler;
  final Set<String> dosyalar;
  final Tarih? bitisTarihi;
  final VekaletDurumu durum;

  /// Azil, istifa veya sona erme tarihi.
  final Tarih? durumTarihi;

  /// Fiziksel asıl evrakın yeri (ör. "Arşiv dolabı 3, klasör 12").
  final String? asilEvrakYeri;

  Vekaletname durumuDegistir(VekaletDurumu yeni, Tarih tarih) => Vekaletname(
        id: id,
        kiraciId: kiraciId,
        muvekkilId: muvekkilId,
        avukatlar: avukatlar,
        duzenlemeTarihi: duzenlemeTarihi,
        noter: noter,
        yevmiyeNo: yevmiyeNo,
        genel: genel,
        ozelYetkiler: ozelYetkiler,
        dosyalar: dosyalar,
        bitisTarihi: bitisTarihi,
        durum: yeni,
        durumTarihi: tarih,
        asilEvrakYeri: asilEvrakYeri,
      );
}

/// Yetki belgesiyle (tevkil) yetkilendirilen alt vekil.
class AltVekalet {
  const AltVekalet({
    required this.vekaletnameId,
    required this.verenAvukat,
    required this.alanAvukat,
    required this.tarih,
    this.dosyalar = const {},
    this.ozelYetkiler = const {},
  });

  final String vekaletnameId;
  final String verenAvukat;
  final String alanAvukat;
  final Tarih tarih;
  final Set<String> dosyalar;
  final Set<OzelYetki> ozelYetkiler;
}

class VekaletKontrolSonucu {
  const VekaletKontrolSonucu.uygun(this.vekaletname) : uygun = true, neden = null;

  const VekaletKontrolSonucu.uygunDegil(this.neden) : uygun = false, vekaletname = null;

  final bool uygun;
  final String? neden;
  final Vekaletname? vekaletname;
}

/// İşlem öncesi yetki kontrolü: feragat, sulh, tahsilat gibi işlemlerden önce çağrılır.
class VekaletKontrolu {
  VekaletKontrolu._();

  static VekaletKontrolSonucu kontrolEt({
    required Iterable<Vekaletname> vekaletnameler,
    Iterable<AltVekalet> altVekaletler = const [],
    required String muvekkilId,
    required String avukatId,
    required String dosyaId,
    required Tarih tarih,
    OzelYetki? gerekenYetki,
  }) {
    String? sonNeden;
    for (final v in vekaletnameler.where((v) => v.muvekkilId == muvekkilId)) {
      final neden = _uygunsuzluk(v, tarih, dosyaId);
      if (neden != null) {
        sonNeden = neden;
        continue;
      }

      if (v.avukatlar.contains(avukatId)) {
        if (gerekenYetki != null && !v.ozelYetkiler.contains(gerekenYetki)) {
          sonNeden = 'Vekâletnamede "${gerekenYetki.ad}" özel yetkisi yok.';
          continue;
        }
        return VekaletKontrolSonucu.uygun(v);
      }

      for (final alt in altVekaletler.where((a) => a.vekaletnameId == v.id && a.alanAvukat == avukatId)) {
        if (alt.dosyalar.isNotEmpty && !alt.dosyalar.contains(dosyaId)) continue;
        if (gerekenYetki != null &&
            !(alt.ozelYetkiler.contains(gerekenYetki) && v.ozelYetkiler.contains(gerekenYetki))) {
          sonNeden = 'Yetki belgesinde "${gerekenYetki.ad}" yetkisi devredilmemiş.';
          continue;
        }
        return VekaletKontrolSonucu.uygun(v);
      }
      sonNeden ??= 'Avukat bu vekâletnamede vekil değil.';
    }
    return VekaletKontrolSonucu.uygunDegil(sonNeden ?? 'Müvekkile ait vekâletname bulunamadı.');
  }

  static String? _uygunsuzluk(Vekaletname v, Tarih tarih, String dosyaId) {
    if (v.durum != VekaletDurumu.gecerli) {
      final ne = switch (v.durum) {
        VekaletDurumu.azil => 'azledilmiş',
        VekaletDurumu.istifa => 'istifa edilmiş',
        _ => 'süresi dolmuş',
      };
      return 'Vekâlet $ne.';
    }
    if (tarih.isBefore(v.duzenlemeTarihi)) return 'İşlem tarihi vekâletname tarihinden önce.';
    final bitis = v.bitisTarihi;
    if (bitis != null && tarih.isAfter(bitis)) return 'Vekâletnamenin süresi dolmuş.';
    if (!v.genel && !v.dosyalar.contains(dosyaId)) return 'Vekâletname bu dosyayı kapsamıyor.';
    return null;
  }

  /// Yetki belgesi (tevkil) oluşturur. Veren avukatın tevkil yetkisi olmalıdır.
  static AltVekalet yetkiBelgesiVer({
    required Vekaletname vekaletname,
    required String verenAvukat,
    required String alanAvukat,
    required Tarih tarih,
    Set<String> dosyalar = const {},
    Set<OzelYetki> devredilenYetkiler = const {},
  }) {
    if (vekaletname.durum != VekaletDurumu.gecerli) {
      throw StateError('Geçerli olmayan vekâletnameyle yetki belgesi verilemez.');
    }
    if (!vekaletname.avukatlar.contains(verenAvukat)) {
      throw StateError('Yetki belgesini yalnızca vekâletnamedeki avukat verebilir.');
    }
    if (!vekaletname.ozelYetkiler.contains(OzelYetki.tevkil)) {
      throw StateError('Vekâletnamede tevkil yetkisi yok.');
    }
    final fazla = devredilenYetkiler.difference(vekaletname.ozelYetkiler);
    if (fazla.isNotEmpty) {
      throw StateError('Sahip olunmayan yetki devredilemez: ${fazla.map((y) => y.ad).join(', ')}.');
    }
    return AltVekalet(
      vekaletnameId: vekaletname.id,
      verenAvukat: verenAvukat,
      alanAvukat: alanAvukat,
      tarih: tarih,
      dosyalar: dosyalar,
      ozelYetkiler: devredilenYetkiler,
    );
  }
}
