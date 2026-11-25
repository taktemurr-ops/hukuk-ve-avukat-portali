import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final mevcut = [
    Dosya(
      id: 'd1',
      kiraciId: 'k',
      icNo: '2026/0001',
      tur: DosyaTuru.hukuk,
      baslik: 'ABC Gıda - Delta',
      sorumlu: 'a',
      acilisTarihi: Tarih(2026, 1, 5),
      mahkeme: 'İstanbul 5. Asliye Ticaret Mahkemesi',
      esasNo: '2026/123 E.',
    ),
  ];

  test('UYAP dosya listesi: sütun tahmini, tür, mükerrer ve hatalar', () {
    final o = DosyaAktarimi.onizle(tablo: [
      ['Birim Adı', 'Dosya No', 'Dosya Türü', 'Davacı', 'Davalı', 'Açılış Tarihi', 'Dosya Durumu'],
      ['İstanbul 5. Asliye Ticaret Mahkemesi', '2026/123', 'Hukuk', 'ABC Gıda', 'Delta', '05.01.2026', 'Açık'],
      ['İstanbul 12. İcra Dairesi', '2026/4521 E', 'İcra', 'ABC Gıda', 'Yıldız Ltd.', '10.02.2026', 'Açık'],
      ['Ankara 3. İş Mahkemesi', '2025/88', '', 'Ayşe Kara', 'XYZ A.Ş.', '', 'Kapalı'],
      ['İstanbul 12. İcra Dairesi', '2026/4521', 'İcra', '', '', '', ''],
      ['', '2026/1', '', '', '', '', ''],
      ['Kadıköy 2. Sulh Hukuk', '123/2026', '', '', '', '', ''],
    ], mevcut: mevcut);
    expect(o.esleme[DosyaAlani.mahkeme], 0);
    expect(o.esleme[DosyaAlani.muvekkil], 3);
    final s = o.satirlar;
    expect(s[0].durum, SatirDurumu.mukerrer);
    expect(s[0].mukerrerAciklama, contains('2026/0001'));
    expect(s[1].durum, SatirDurumu.aktarilacak);
    expect(s[1].tur, DosyaTuru.icra);
    expect(s[1].esasNo, '2026/4521 E.');
    expect(s[1].baslik, 'ABC Gıda - Yıldız Ltd.');
    expect(s[1].acilis, Tarih(2026, 2, 10));
    expect(s[2].kapali, isTrue);
    expect(s[2].tur, DosyaTuru.hukuk);
    expect(s[3].durum, SatirDurumu.mukerrer); // listede 2. satırla aynı
    expect(s[4].hatalar, contains('Mahkeme / birim boş.'));
    expect(s[5].hatalar.single, contains('biçiminde değil'));
    expect(o.mutabik, isTrue);
  });

  test('esas no biçimleme', () {
    expect(DosyaAktarimi.esasNoBicimle('2026 / 77 d'), '2026/77 D.');
    expect(DosyaAktarimi.esasNoBicimle('2026/77 Talimat'), '2026/77 Tal.');
    expect(DosyaAktarimi.esasNoBicimle('E.2026/77'), isNull);
  });
}
