import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Görev', () {
    test('Süreden doğan görev kanıtsız kapanmaz', () {
      const g = Gorev(id: 'g1', baslik: 'İstinaf dilekçesi', atanan: 'a1', kaynakSureId: 's1');
      expect(() => g.kapat(), throwsArgumentError);
      final kapali = g.kapat(kanit: 'UYAP 2026-1');
      expect(kapali.durum, GorevDurumu.tamamlandi);
      expect(() => kapali.kapat(kanit: 'x'), throwsStateError);
    });

    test('Sıradan görev kanıtsız kapanabilir; gecikme kontrolü', () {
      final g = Gorev(id: 'g2', baslik: 'Müvekkili ara', atanan: 'a1', sonTarih: Tarih(2026, 11, 20));
      expect(g.gecikti(Tarih(2026, 11, 25)), isTrue);
      expect(g.gecikti(Tarih(2026, 11, 20)), isFalse);
      expect(g.kapat().durum, GorevDurumu.tamamlandi);
    });

    test('Şablondan görevler rollere ve tarihlere göre üretilir', () {
      var n = 0;
      final gorevler = GorevSablonu.isDavasiAcilisi.uygula(
        dosyaId: 'd1',
        baslangic: Tarih(2026, 11, 25),
        roller: {'sorumlu': 'av1', 'yedek': 'av2', 'stajyer': 'st1'},
        idUret: () => 'g${++n}',
      );
      expect(gorevler, hasLength(5));
      expect(gorevler.first.atanan, 'st1');
      expect(gorevler.first.sonTarih, Tarih(2026, 11, 25));
      expect(gorevler[2].atanan, 'av1');
      expect(gorevler[2].yedek, 'av2');
      expect(gorevler.last.sonTarih, Tarih(2026, 12, 7));
      expect(gorevler.map((g) => g.id).toSet(), hasLength(5));
    });
  });

  group('Duruşma çakışması', () {
    Durusma d(String id, int saat, int dakika, String yer, {String avukat = 'a1'}) => Durusma(
          id: id,
          dosyaId: 'dosya-$id',
          baslangic: DateTime(2026, 12, 3, saat, dakika),
          yer: yer,
          katilan: avukat,
        );

    test('Aynı avukatın üst üste binen duruşmaları', () {
      final c = CakismaKontrolu.bul([
        d('1', 10, 0, 'Çağlayan Adliyesi'),
        d('2', 10, 30, 'Çağlayan Adliyesi'),
        d('3', 14, 0, 'Kartal Adliyesi'),
        d('4', 10, 0, 'Çağlayan Adliyesi', avukat: 'a2'),
      ]);
      expect(c, hasLength(1));
      expect(c.single.neden, 'Saatler çakışıyor');
    });

    test('Farklı adliyeye yetişme süresi yetersiz', () {
      final c = CakismaKontrolu.bul([
        d('1', 10, 0, 'Çağlayan Adliyesi'),
        d('2', 11, 30, 'Kartal Adliyesi'),
      ]);
      expect(c.single.neden, contains('yol süresi'));
    });

    test('Aynı adliyede art arda duruşma çakışma değildir', () {
      expect(CakismaKontrolu.bul([d('1', 10, 0, 'Çağlayan Adliyesi'), d('2', 11, 0, 'Çağlayan Adliyesi')]), isEmpty);
    });
  });
}
