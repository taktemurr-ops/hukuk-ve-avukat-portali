import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final bugun = Tarih(2026, 11, 25);
  const eski = SaklamaKaydi(id: 'a1', ad: '2013/45 Alacak davası', kategori: VeriKategorisi.davaDosyasi);
  final kayitlar = [
    SaklamaKaydi(id: 'a1', ad: '2013/45 Alacak davası', kategori: VeriKategorisi.davaDosyasi, kapanis: Tarih(2015, 3, 12)),
    SaklamaKaydi(id: 'a2', ad: '2020/8 İşe iade', kategori: VeriKategorisi.davaDosyasi, kapanis: Tarih(2021, 6, 1)),
    SaklamaKaydi(
        id: 'a3',
        ad: '2012/3 Tazminat',
        kategori: VeriKategorisi.davaDosyasi,
        kapanis: Tarih(2013, 1, 10),
        yasalSaklamaEngeli: 'Bağlı rücu davası devam ediyor'),
    SaklamaKaydi(id: 'a4', ad: 'Reddedilen başvuru', kategori: VeriKategorisi.adayKaydi, kapanis: Tarih(2024, 11, 25)),
    eski,
  ];

  test('saklama süresi kapanıştan işler; engel ve başlamamış süre ayrı', () {
    final s = SaklamaVeImha();
    final d = {for (final x in s.degerlendirTumu(kayitlar.take(4), bugun)) x.kayit.id: x};
    expect(d['a1']!.durum, ImhaDurumu.imhayaHazir);
    expect(d['a1']!.imhaTarihi, Tarih(2025, 3, 12));
    expect(d['a2']!.durum, ImhaDurumu.saklaniyor);
    expect(d['a2']!.imhaTarihi, Tarih(2031, 6, 1));
    expect(d['a3']!.durum, ImhaDurumu.engelli);
    expect(d['a4']!.durum, ImhaDurumu.imhayaHazir);
    expect(s.degerlendir(eski, bugun).durum, ImhaDurumu.sureBaslamadi);
    expect(s.degerlendirTumu(kayitlar.take(4), bugun).first.kayit.id, 'a3');
  });

  test('tutanak yalnızca imhaya hazır kayıtlarla; dört göz onayı; periyodik imha 6 ay', () {
    final s = SaklamaVeImha(sonPeriyodikImha: Tarih(2026, 4, 1));
    expect(s.sonrakiPeriyodikImha(), Tarih(2026, 10, 1));
    expect(s.periyodikImhaGecikti(bugun), isTrue);
    expect(() => s.tutanakHazirla(secilen: [kayitlar[1]], yontem: ImhaYontemi.silme, hazirlayan: 'ayse', bugun: bugun),
        throwsStateError);
    expect(() => s.tutanakHazirla(secilen: [], yontem: ImhaYontemi.silme, hazirlayan: 'ayse', bugun: bugun),
        throwsArgumentError);
    final t = s.tutanakHazirla(
        secilen: [kayitlar[0], kayitlar[3]], yontem: ImhaYontemi.yokEtme, hazirlayan: 'ayse', bugun: bugun);
    expect(t.no, 'IT-2026-001');
    expect(t.kayitIdleri, ['a1', 'a4']);
    expect(() => s.tutanakOnayla(t, 'ayse', bugun), throwsStateError);
    s.tutanakOnayla(t, 'mert', bugun);
    expect(t.onaylandi, isTrue);
    expect(s.sonrakiPeriyodikImha(), Tarih(2027, 5, 25));
    expect(s.periyodikImhaGecikti(bugun), isFalse);
    expect(() => s.tutanakOnayla(t, 'can', bugun), throwsStateError);
  });
}
