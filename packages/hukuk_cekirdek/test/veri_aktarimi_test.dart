import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('CSV ayrıştırıcı', () {
    test('Noktalı virgül, BOM, tırnak içinde ayraç ve satır sonu', () {
      final t = CsvAyristirici.ayristir('﻿a;b;c\r\n1;"x;y";"çok\nsatır"\n\n2;;3\n');
      expect(t, [
        ['a', 'b', 'c'],
        ['1', 'x;y', 'çok\nsatır'],
        ['2', '', '3'],
      ]);
    });

    test('Virgül ayraç otomatik bulunur; çift tırnak kaçışı', () {
      final t = CsvAyristirici.ayristir('ad,email\n"Kaya, Ali",ali@x.com\n"Av. ""Ali"" Kaya",y@x.com');
      expect(CsvAyristirici.ayiriciBul('ad,email'), ',');
      expect(t[1], ['Kaya, Ali', 'ali@x.com']);
      expect(t[2][0], 'Av. "Ali" Kaya');
    });

    test('Sekme ayraç', () {
      expect(CsvAyristirici.ayristir('a\tb\n1\t2')[1], ['1', '2']);
    });
  });

  test('Türkçe başlıklardan sütun eşlemesi tahmini', () {
    final e = sutunEslemesiTahminEt(['Adı Soyadı', 'TCKN/VKN', 'E-posta', 'Cep Telefonu', 'Adres', 'Not']);
    expect(e, {
      KisiAlani.ad: 0,
      KisiAlani.kimlikNo: 1,
      KisiAlani.eposta: 2,
      KisiAlani.telefon: 3,
      KisiAlani.adres: 4,
    });
  });

  test('Kişi aktarımı önizlemesi: doğrulama, mükerrer ve sayım mutabakatı', () {
    const csv = '﻿Adı Soyadı;TCKN/VKN;E-posta;Telefon;Adres\n'
        'Ayşe Kara;10000000146;ayse@ornek.com;0532 111 22 33;İstanbul\n'
        '"Delta İnşaat Ltd. Şti.";9876543217;info@delta;0212 000 00 00;"Ataşehir; İstanbul"\n'
        'Zeynep Aydın;;zeynep@ornek.com;;\n'
        'Hatalı Kişi;10000000147;;;\n'
        ';1234567890;;;\n'
        'Zeynep Aydın;;;;\n'
        'Yeni Şirket A.Ş.;;;;"Çok\nsatırlı adres"\n';
    const mevcut = [
      Kisi(id: 'ayse', kiraciId: 'b', tur: KisiTuru.gercek, ad: 'Ayşe Kara', kimlikNo: '10000000146'),
      Kisi(id: 'delta', kiraciId: 'b', tur: KisiTuru.tuzel, ad: 'Delta İnşaat Ltd. Şti.', kimlikNo: '9876543217'),
    ];
    final o = KisiAktarimi.onizle(csv: csv, mevcut: mevcut);
    SatirDurumu durum(int satirNo) => o.satirlar.firstWhere((s) => s.satirNo == satirNo).durum;

    expect(o.satirlar, hasLength(7));
    expect(durum(2), SatirDurumu.mukerrer);
    expect(durum(3), SatirDurumu.mukerrer);
    expect(durum(4), SatirDurumu.aktarilacak);
    expect(durum(5), SatirDurumu.hatali);
    expect(durum(6), SatirDurumu.hatali);
    expect(durum(7), SatirDurumu.mukerrer);
    expect(durum(8), SatirDurumu.aktarilacak);

    final delta = o.satirlar.firstWhere((s) => s.satirNo == 3);
    expect(delta.tur, KisiTuru.tuzel);
    expect(delta.deger(KisiAlani.adres), 'Ataşehir; İstanbul');
    expect(delta.deger(KisiAlani.eposta), '');
    expect(delta.uyarilar, hasLength(2));

    final yeniSirket = o.satirlar.firstWhere((s) => s.satirNo == 8);
    expect(yeniSirket.tur, KisiTuru.tuzel);
    expect(yeniSirket.deger(KisiAlani.adres), 'Çok\nsatırlı adres');

    expect(o.satirlar.firstWhere((s) => s.satirNo == 7).mukerrerAciklama, contains('4. satır'));
    expect(o.sayi(SatirDurumu.aktarilacak), 2);
    expect(o.sayi(SatirDurumu.mukerrer), 3);
    expect(o.sayi(SatirDurumu.hatali), 2);
    expect(o.mutabik, isTrue);
  });
}
