import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

final _kural = KuralKatalogu.bul('HMK_ISTINAF')!.onayla('test');
final _bugun = Tarih(2026, 11, 25);

SureKaydi _sure(
  String id, {
  required Tarih sonGun,
  String asil = 'a1',
  String? yedek = 'a2',
  SureDurumu durum = SureDurumu.teyitli,
  Tarih? olusturma,
}) =>
    SureKaydi(
      id: id,
      dosyaId: 'd1',
      aciklama: 'Süre $id',
      sonuc: SureSonucu(
        kural: _kural,
        baslangic: sonGun.gunEkle(-14),
        sonGun: sonGun,
        adimlar: const [],
        uyarilar: const [],
      ),
      olusturan: 'stajyer',
      olusturmaTarihi: olusturma ?? _bugun,
      asilSorumlu: asil,
      yedekSorumlu: yedek,
      durum: durum,
    );

void main() {
  group('Süre yaşam döngüsü', () {
    test('Yedek sorumlu asıl sorumluyla aynı olamaz', () {
      expect(() => _sure('x', sonGun: _bugun, yedek: 'a1'), throwsArgumentError);
    });

    test('Kesin süreyi hesabı yapan teyit edemez', () {
      final s = _sure('s', sonGun: Tarih(2026, 12, 9), durum: SureDurumu.teyitBekliyor);
      expect(() => s.teyitEt(kullanici: 'stajyer', tarih: _bugun), throwsStateError);
      final teyitli = s.teyitEt(kullanici: 'a1', tarih: _bugun);
      expect(teyitli.durum, SureDurumu.teyitli);
      expect(teyitli.teyitEden, 'a1');
    });

    test('Teyitsiz süre tamamlanamaz, tamamlama kanıt ister', () {
      final bekleyen = _sure('s', sonGun: Tarih(2026, 12, 9), durum: SureDurumu.teyitBekliyor);
      expect(() => bekleyen.tamamla(kanit: 'UYAP 123'), throwsStateError);
      final teyitli = _sure('s', sonGun: Tarih(2026, 12, 9));
      expect(() => teyitli.tamamla(kanit: '  '), throwsArgumentError);
      final bitti = teyitli.tamamla(kanit: 'UYAP gönderim no 2026-998877');
      expect(bitti.durum, SureDurumu.tamamlandi);
      expect(bitti.acik, isFalse);
    });

    test('Yeniden hesapta eski hesap saklanır ve teyit sıfırlanır', () {
      final s = _sure('s', sonGun: Tarih(2026, 12, 9));
      final yeni = s.yenidenHesapla(
        yeniSonuc: SureSonucu(
            kural: _kural, baslangic: _bugun, sonGun: Tarih(2026, 12, 11), adimlar: const [], uyarilar: const []),
        neden: 'Tebliğ tarihi düzeltildi',
        kullanici: 'a1',
        tarih: _bugun,
      );
      expect(yeni.sonGun, Tarih(2026, 12, 11));
      expect(yeni.durum, SureDurumu.teyitBekliyor);
      expect(yeni.teyitEden, isNull);
      expect(yeni.oncekiHesaplar.single.sonGun, Tarih(2026, 12, 9));
      expect(yeni.oncekiHesaplar.single.neden, 'Tebliğ tarihi düzeltildi');
    });
  });

  group('Eskalasyon', () {
    const motor = EskalasyonMotoru();

    SureUyarisi tek(SureKaydi s) => motor.degerlendir([s], _bugun).single;

    test('7 gün kala asıl sorumluya hatırlatma', () {
      final u = tek(_sure('s', sonGun: Tarih(2026, 12, 2)));
      expect(u.seviye, UyariSeviyesi.hatirlatma);
      expect(u.alicilar, {'a1'});
    });

    test('Son gün yarınsa yedek sorumlu da bilgilendirilir', () {
      final u = tek(_sure('s', sonGun: Tarih(2026, 11, 26)));
      expect(u.seviye, UyariSeviyesi.yedekSorumlu);
      expect(u.alicilar, {'a1', 'a2'});
    });

    test('Son gün bugünse yöneticiye çıkar', () {
      expect(tek(_sure('s', sonGun: _bugun)).seviye, UyariSeviyesi.yonetici);
    });

    test('Geçmiş ve tamamlanmamış süre kritiktir', () {
      final u = tek(_sure('s', sonGun: Tarih(2026, 11, 24)));
      expect(u.seviye, UyariSeviyesi.kritik);
      expect(u.alicilar, contains('yonetici'));
    });

    test('Bir günden uzun teyitsiz kalan süre yöneticiye çıkar', () {
      final u = tek(_sure('s',
          sonGun: Tarih(2026, 12, 20), durum: SureDurumu.teyitBekliyor, olusturma: Tarih(2026, 11, 23)));
      expect(u.seviye, UyariSeviyesi.yonetici);
      expect(u.mesaj, contains('teyit edilmedi'));
    });

    test('Yeni ve uzak süre için uyarı yok', () {
      final s = _sure('s', sonGun: Tarih(2026, 12, 20), durum: SureDurumu.teyitBekliyor);
      expect(motor.degerlendir([s], _bugun), isEmpty);
    });

    test('Sahipsiz süre yöneticiye çıkar', () {
      final s = _sure('s', sonGun: Tarih(2026, 12, 20), asil: '', yedek: null, durum: SureDurumu.teyitBekliyor);
      final u = tek(s);
      expect(u.mesaj, contains('sorumlu atanmamış'));
      expect(u.alicilar, {'yonetici'});
    });

    test('Tamamlanmış süre uyarı üretmez, uyarılar önem sırasına dizilir', () {
      final liste = motor.degerlendir([
        _sure('tamam', sonGun: Tarih(2026, 11, 20)).tamamla(kanit: 'makbuz 1'),
        _sure('yakin', sonGun: Tarih(2026, 12, 2)),
        _sure('gecmis', sonGun: Tarih(2026, 11, 24)),
      ], _bugun);
      expect(liste.map((u) => u.sure.id), ['gecmis', 'yakin']);
    });
  });

  group('Devir listesi', () {
    test('Ayrılan kullanıcının işleri; devralanı olmayanlar kritik ve en üstte', () {
      final liste = DevirListesi.olustur(
        ayrilan: 'a1',
        pasifKullanicilar: {'a4'},
        sureler: [
          _sure('yedekli', sonGun: Tarih(2026, 12, 1)),
          _sure('yedeksiz', sonGun: Tarih(2026, 12, 5), yedek: null),
          _sure('yedekOlarak', sonGun: Tarih(2026, 12, 3), asil: 'a3', yedek: 'a1'),
          _sure('yedekPasif', sonGun: Tarih(2026, 12, 2), yedek: 'a4'),
          _sure('baskasi', sonGun: Tarih(2026, 12, 2), asil: 'a5', yedek: 'a6'),
        ],
      );
      expect(liste.map((k) => k.sure.id), ['yedekPasif', 'yedeksiz', 'yedekli', 'yedekOlarak']);
      expect(liste.where((k) => k.kritik), hasLength(2));
      expect(liste.firstWhere((k) => k.sure.id == 'yedekOlarak').devralabilir, 'a3');
    });
  });
}
