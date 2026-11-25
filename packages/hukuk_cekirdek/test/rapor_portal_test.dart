import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

final _kural = KuralKatalogu.bul('HMK_ISTINAF')!.onayla('test');
final _bugun = Tarih(2026, 11, 25);

SureKaydi _sure(String id, int kalan, {String asil = 'a1', SureDurumu durum = SureDurumu.teyitli}) => SureKaydi(
      id: id,
      dosyaId: 'd1',
      aciklama: id,
      sonuc: SureSonucu(
          kural: _kural,
          baslangic: _bugun.gunEkle(kalan - 14),
          sonGun: _bugun.gunEkle(kalan),
          adimlar: const [],
          uyarilar: const []),
      olusturan: 'x',
      olusturmaTarihi: _bugun,
      asilSorumlu: asil,
      durum: durum,
    );

Dosya _dosya(String id, String sorumlu, {DosyaAsamasi asama = DosyaAsamasi.ilkDerece}) => Dosya(
    id: id, kiraciId: 'k', icNo: id, tur: DosyaTuru.hukuk, baslik: 'Dosya $id', sorumlu: sorumlu,
    acilisTarihi: Tarih(2026, 1, 1), asama: asama, mahkeme: 'İstanbul 3. Asliye Ticaret', esasNo: '2026/41');

CariHareket _h(String id, CariHareketTuru tur, num tl, Tarih t, {String m = 'm1'}) =>
    CariHareket(id: id, muvekkilId: m, tur: tur, tutar: Para.tl(tl), tarih: t, aciklama: '');

void main() {
  group('Raporlar', () {
    test('iş yükü kişi bazında toplanır ve yüke göre sıralanır', () {
      final satirlar = Raporlar.isYuku(
        dosyalar: [_dosya('d1', 'a1'), _dosya('d2', 'a2'), _dosya('d3', 'a2', asama: DosyaAsamasi.kapandi)],
        sureler: [_sure('s1', 3), _sure('s2', 20, durum: SureDurumu.teyitBekliyor), _sure('s3', 1, asil: '')],
        gorevler: [
          Gorev(id: 'g1', baslik: 'g', atanan: 'a2', sonTarih: _bugun.gunEkle(-1)),
          Gorev(id: 'g2', baslik: 'g', atanan: 'a2', sonTarih: _bugun.gunEkle(5)),
          const Gorev(id: 'g3', baslik: 'g', atanan: 'a2', durum: GorevDurumu.tamamlandi),
        ],
        bugun: _bugun,
      );
      expect(satirlar.map((s) => s.kullanici), ['a1', 'a2']);
      final a1 = satirlar.first;
      expect([a1.acikDosya, a1.acikSure, a1.kritikSure, a1.teyitBekleyen], [1, 2, 1, 1]);
      final a2 = satirlar.last;
      expect([a2.acikDosya, a2.acikGorev, a2.gecikenGorev], [1, 2, 1]);
      expect(a1.yukPuani, 1 + 4 + 5);
      expect(a2.yukPuani, 1 + 2 + 4);
    });

    test('süre dağılımı', () {
      final d = Raporlar.sureDagilimi([
        _sure('a', -1),
        _sure('b', 0),
        _sure('c', 1),
        _sure('d', 5, durum: SureDurumu.teyitBekliyor),
        _sure('e', 30),
        _sure('f', 31, asil: ''),
        _sure('g', 2, durum: SureDurumu.tamamlandi),
      ], _bugun);
      expect([d.kacan, d.bugunYarin, d.buHafta, d.buAy, d.sonra], [1, 2, 1, 1, 1]);
      expect(d.toplam, 6);
      expect(d.teyitBekleyen, 1);
      expect(d.sahipsiz, 1);
    });

    test('alacak yaşlandırma: tahsilat en eski tahakkuktan düşer', () {
      final y = Raporlar.alacakYaslandirma([
        _h('1', CariHareketTuru.ucretTahakkuku, 10000, _bugun.gunEkle(-100)),
        _h('2', CariHareketTuru.ucretTahakkuku, 20000, _bugun.gunEkle(-45)),
        _h('3', CariHareketTuru.ucretTahakkuku, 5000, _bugun.gunEkle(-10)),
        _h('4', CariHareketTuru.ucretTahsilati, 15000, _bugun.gunEkle(-5)),
        _h('5', CariHareketTuru.masrafYapildi, 732, _bugun.gunEkle(-3)),
        _h('6', CariHareketTuru.ucretTahakkuku, 1000, _bugun.gunEkle(-200), m: 'm2'),
        _h('7', CariHareketTuru.ucretTahsilati, 1000, _bugun, m: 'm2'),
      ], _bugun);
      expect(y, hasLength(1));
      final m1 = y.single;
      expect(m1.kovalar.map((p) => p.kurus), [500000, 1500000, 0, 0]);
      expect(m1.masrafAlacagi, Para.tl(732));
      expect(m1.toplam, Para.tl(20732));
      expect(m1.geciken, isFalse);
    });

    test('talep performansı ve sözleşme özeti', () {
      final hesap = IsGunuHesabi(TurkiyeTatilleri.takvim([2026]));
      final defter = TalepDefteri(hesap: hesap, yonlendirici: const TalepYonlendirici({TalepTuru.diger: ['x']}));
      final gun = Tarih(2026, 11, 16);
      HukukTalebi ac(TalepTuru tur) => defter.olustur(
          baslik: 'b', aciklama: '', tur: tur, oncelik: Oncelik.normal, talepEden: 't', birim: 'b', bugun: gun);
      final t1 = ac(TalepTuru.ihtarname)..durumDegistir(TalepDurumu.incelemede, kullanici: 'x', bugun: gun, hesap: hesap);
      t1.durumDegistir(TalepDurumu.tamamlandi, kullanici: 'x', bugun: Tarih(2026, 11, 18), hesap: hesap);
      final t2 = ac(TalepTuru.ihtarname)..durumDegistir(TalepDurumu.incelemede, kullanici: 'x', bugun: gun, hesap: hesap);
      t2.durumDegistir(TalepDurumu.tamamlandi, kullanici: 'x', bugun: Tarih(2026, 11, 20), hesap: hesap);
      ac(TalepTuru.kvkk);
      ac(TalepTuru.hukukiGorus);
      final p = Raporlar.talepPerformansi(defter.talepler, _bugun, hesap);
      expect([p.acik, p.kapanan, p.zamanindaKapanan, p.geciken], [2, 2, 1, 2]);
      expect(p.slaUyumu, 50);
      expect(p.ortalamaCozum, 3);
      expect(p.acikTurlere, {TalepTuru.kvkk: 1, TalepTuru.hukukiGorus: 1});

      final s1 = Sozlesme(id: '1', no: '1', baslik: 'a', tur: SozlesmeTuru.hizmet, karsiTaraf: '', sorumlu: '')
        ..durum = SozlesmeDurumu.yururlukte
        ..bitis = Tarih(2027, 3, 31)
        ..tarama = const TaramaSonucu();
      final s2 = Sozlesme(id: '2', no: '2', baslik: 'b', tur: SozlesmeTuru.hizmet, karsiTaraf: '', sorumlu: '')
        ..bitis = Tarih(2027, 3, 1);
      final o = Raporlar.sozlesmeOzeti([s1, s2], _bugun);
      expect(o.bitisAylari, {'2027-03': 1});
      expect(o.taranmamis, 1);
      expect(o.risk[RiskSeviyesi.dusuk], 1);
      expect(o.durum[SozlesmeDurumu.taslak], 1);
    });

    test('CSV noktalı virgül ayraçlı ve tırnaklı', () {
      expect(Raporlar.csv(['Ad', 'Not'], [
        ['Ayşe', 'a;b'],
        ['Mert', null],
      ]), 'Ad;Not\nAyşe;"a;b"\nMert;');
    });
  });

  group('Müvekkil portalı', () {
    final simdi = DateTime.utc(2026, 11, 25, 10);
    BelgeSurumu surum(String ad) =>
        BelgeSurumu(no: 1, ozet: 'x', boyut: 1, yukleyen: 'a1', tarih: _bugun, dosyaAdi: ad);
    final belgeler = [
      Belge(id: 'b1', kiraciId: 'k', ad: 'Dava dilekçesi', tur: BelgeTuru.dilekce, ilkSurum: surum('dilekce.pdf'), dosyaId: 'd1'),
      Belge(id: 'b2', kiraciId: 'k', ad: 'İç not', tur: BelgeTuru.diger, ilkSurum: surum('not.docx'), dosyaId: 'd1'),
      Belge(
          id: 'b3', kiraciId: 'k', ad: 'Gizli', tur: BelgeTuru.delil, ilkSurum: surum('g.pdf'), dosyaId: 'd1', gizli: true),
    ];

    test('yalnızca müvekkilin ve paylaşılan dosyalar; yalnızca paylaşılan ve gizli olmayan belgeler', () {
      final o = MuvekkilPortali.ozetler(
        muvekkilinDosyalari: {'d1', 'd2'},
        portaldaPaylasilan: {'d1', 'd3'},
        dosyalar: [_dosya('d1', 'a1'), _dosya('d2', 'a1'), _dosya('d3', 'a1')],
        durusmalar: [
          Durusma(id: 'x1', dosyaId: 'd1', baslangic: DateTime.utc(2026, 11, 1, 10), yer: 'Eski', katilan: 'a1'),
          Durusma(id: 'x2', dosyaId: 'd1', baslangic: DateTime.utc(2027, 2, 3, 10), yer: 'Çağlayan', katilan: 'a1'),
          Durusma(id: 'x3', dosyaId: 'd1', baslangic: DateTime.utc(2026, 12, 8, 9), yer: 'Çağlayan B', katilan: 'a1'),
        ],
        belgeler: belgeler,
        paylasilanBelgeler: {'b1', 'b3'},
        mesajlar: [
          PortalMesaji(id: 'm1', dosyaId: 'd1', gonderen: 'a1', muvekkildenMi: false, metin: 'Merhaba', zaman: simdi),
          PortalMesaji(id: 'm2', dosyaId: 'd2', gonderen: 'm', muvekkildenMi: true, metin: 'x', zaman: simdi),
        ],
        simdi: simdi,
      );
      expect(o.map((x) => x.dosyaId), ['d1']);
      final d1 = o.single;
      expect(d1.sonrakiDurusma, DateTime.utc(2026, 12, 8, 9));
      expect(d1.durusmaYeri, 'Çağlayan B');
      expect(d1.belgeler.map((b) => b.id), ['b1']);
      expect(d1.mesajlar.map((m) => m.id), ['m1']);
      expect(d1.okunmamis, 1);
      expect(d1.mesajlar.single.okunduIsaretle().okundu, isTrue);
    });

    test('mesaj doğrulama', () {
      expect(PortalMesaji.dogrula('  '), isNotNull);
      expect(PortalMesaji.dogrula('a' * 4001), isNotNull);
      expect(PortalMesaji.dogrula('Duruşma saati nedir?'), isNull);
    });
  });
}
