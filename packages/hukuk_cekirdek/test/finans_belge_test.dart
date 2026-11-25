import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Serbest meslek makbuzu', () {
    test('Brütten: KDV eklenir, stopaj kesilir', () {
      final m = MakbuzHesabi.bruttenHesapla(Para.tl(10000));
      expect(m.kdv, Para.tl(2000));
      expect(m.stopaj, Para.tl(2000));
      expect(m.netUcret, Para.tl(8000));
      expect(m.tahsilEdilecek, Para.tl(10000));
    });

    test('Netten brüte', () {
      expect(MakbuzHesabi.nettenHesapla(Para.tl(8000)).brut, Para.tl(10000));
    });

    test('Stopajsız (gerçek kişi müvekkil)', () {
      final m = MakbuzHesabi.bruttenHesapla(Para.tl(10000), stopajVar: false);
      expect(m.tahsilEdilecek, Para.tl(12000));
      expect(m.netUcret, Para.tl(10000));
    });
  });

  group('Müvekkil cari hesabı', () {
    CariHareket h(CariHareketTuru tur, num tutar) =>
        CariHareket(id: '$tur$tutar', muvekkilId: 'm1', tur: tur, tutar: Para.tl(tutar), tarih: Tarih(2026, 11, 1), aciklama: '');

    test('Avans, masraf ve ücret ayrı izlenir', () {
      final o = CariOzet([
        h(CariHareketTuru.masrafAvansiAlindi, 5000),
        h(CariHareketTuru.masrafYapildi, 1200),
        h(CariHareketTuru.masrafYapildi, 732),
        h(CariHareketTuru.ucretTahakkuku, 20000),
        h(CariHareketTuru.ucretTahsilati, 15000),
      ]);
      expect(o.avansBakiyesi, Para.tl(3068));
      expect(o.toplamMasraf, Para.tl(1932));
      expect(o.ucretAlacagi, Para.tl(5000));
      expect(o.avansYetersiz(Para.tl(5000)), isTrue);
    });

    test('Negatif tutar reddedilir', () {
      expect(() => CariOzet([h(CariHareketTuru.masrafYapildi, -10)]), throwsArgumentError);
    });
  });

  group('Emanet hesabı', () {
    EmanetHareketi e(String id, EmanetHareketTuru tur, num tutar, Tarih tarih, {String? onay}) => EmanetHareketi(
        id: id, muvekkilId: 'm1', dosyaId: 'd1', tur: tur, tutar: Para.tl(tutar), tarih: tarih, aciklama: '', mahsupOnayi: onay);

    test('Müvekkil parası eksiye düşemez, mahsup onay ister, bekleyen emanet uyarır', () {
      final hesap = EmanetHesabi();
      hesap.ekle(e('1', EmanetHareketTuru.giris, 100000, Tarih(2026, 6, 1)));
      hesap.ekle(e('2', EmanetHareketTuru.muvekkileAktarim, 60000, Tarih(2026, 6, 3)));
      expect(() => hesap.ekle(e('3', EmanetHareketTuru.muvekkileAktarim, 50000, Tarih(2026, 6, 4))), throwsStateError);
      expect(() => hesap.ekle(e('4', EmanetHareketTuru.ucretMahsubu, 10000, Tarih(2026, 6, 4))), throwsStateError);
      hesap.ekle(e('5', EmanetHareketTuru.ucretMahsubu, 10000, Tarih(2026, 6, 4), onay: 'Ücret sözleşmesi m.2'));
      expect(hesap.bakiye('m1'), Para.tl(30000));

      expect(hesap.bekleyenler(Tarih(2026, 6, 10)), isEmpty);
      final bekleyen = hesap.bekleyenler(Tarih(2026, 6, 20)).single;
      expect(bekleyen.$3, Para.tl(30000));
      expect(bekleyen.$4, 19);
    });
  });

  group('Belge', () {
    test('SHA-256 özeti', () {
      expect(metinOzeti('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('Yükleme kontrolü', () {
      expect(yuklemeKontrol(dosyaAdi: 'karar.PDF', boyut: 1000), isNull);
      expect(yuklemeKontrol(dosyaAdi: 'dava.exe', boyut: 1000), contains('.exe'));
      expect(yuklemeKontrol(dosyaAdi: 'bos.pdf', boyut: 0), isNotNull);
      expect(yuklemeKontrol(dosyaAdi: 'buyuk.pdf', boyut: azamiBoyut + 1), contains('MB'));
      expect(yuklemeKontrol(dosyaAdi: 'uzantisiz', boyut: 10), isNotNull);
    });

    test('Sürümler: orijinal korunur, aynı içerik ikinci kez eklenmez, bütünlük doğrulanır', () {
      final b = Belge(
        id: 'b1',
        kiraciId: 'k',
        ad: 'Dava dilekçesi',
        tur: BelgeTuru.dilekce,
        ilkSurum: BelgeSurumu(
            no: 1, ozet: metinOzeti('v1'), boyut: 2, yukleyen: 'a1', tarih: Tarih(2026, 11, 1), dosyaAdi: 'dilekce.docx'),
      );
      final s2 = b.yeniSurum(ozet: metinOzeti('v2'), boyut: 2, yukleyen: 'a1', tarih: Tarih(2026, 11, 2), dosyaAdi: 'dilekce.docx');
      expect(s2.no, 2);
      expect(b.orijinal.no, 1);
      expect(b.guncel.no, 2);
      expect(
        () => b.yeniSurum(ozet: metinOzeti('v1'), boyut: 2, yukleyen: 'a2', tarih: Tarih(2026, 11, 3), dosyaAdi: 'x.docx'),
        throwsStateError,
      );
      expect(b.butunlukDogrula(metinOzeti('v2'))?.no, 2);
      expect(b.butunlukDogrula(metinOzeti('degistirilmis')), isNull);
    });
  });

  group('Şablon motoru', () {
    const s = BelgeSablonu.mazeretDilekcesi;

    test('Alanlar birleşir, eksik alan işaretlenir, koşullu blok çıkarılır', () {
      final c = s.uygula({
        'dosya.esasNo': '2026/123 E.',
        'muvekkil.ad': 'ABC Gıda A.Ş.',
        'avukat.ad': 'Av. Ayşe Yılmaz',
        'durusma.tarih': '27.11.2026 10:30',
        'mazeret.aciklama': 'Kartal Adliyesinde başka bir duruşma',
        'bugun': '25.11.2026',
      });
      expect(c.tamam, isFalse);
      expect(c.eksikAlanlar, {'mahkeme'});
      expect(c.metin, contains('[EKSİK: mahkeme]'));
      expect(c.metin, contains('2026/123 E.'));
      expect(c.metin, isNot(contains('ekte sunulmuştur')));
      expect(c.metin, isNot(contains('{{')));
    });

    test('Koşul alanı doluysa blok yazılır', () {
      final c = s.uygula({'mazeret.belge': 'Duruşma zaptı'});
      expect(c.metin, contains('Duruşma zaptı'));
    });

    test('Şablon alanları listelenir; hazır şablonlar taslak başlar', () {
      expect(s.alanlar, containsAll(['mahkeme', 'dosya.esasNo', 'mazeret.belge']));
      for (final h in BelgeSablonu.hazir) {
        expect(h.onayDurumu, OnayDurumu.taslak, reason: h.kod);
      }
    });
  });
}
