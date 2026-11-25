import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final tablo = FaizTablosu.sabit(24);
  final talep = TakipTalebi(
    tur: TakipTuru.ilamsiz,
    asilAlacak: Para.tl(100000),
    temerrutTarihi: Tarih(2026, 1, 1),
    takipTarihi: Tarih(2026, 3, 2),
    takipOncesiMasraf: Para.tl(500),
  );

  test('işlemiş faiz ve açılış harçları (ilamsız: başvurma + binde 5 peşin)', () {
    final f = IcraHesabi.islemisFaiz(talep, tablo);
    expect(f, Para.kurus(394521));
    final h = IcraHesabi.acilisHarclari(talep, f);
    expect(h.basvurma, Para.tl(732));
    expect(h.pesin, Para.kurus(51973));
    final ilamli = TakipTalebi(
        tur: TakipTuru.ilamli,
        asilAlacak: Para.tl(100000),
        temerrutTarihi: Tarih(2026, 1, 1),
        takipTarihi: Tarih(2026, 3, 2));
    expect(IcraHesabi.acilisHarclari(ilamli, f).pesin, Para.sifir);
    final elle = TakipTalebi(
        tur: TakipTuru.ilamsiz,
        asilAlacak: Para.tl(100),
        temerrutTarihi: Tarih(2026, 1, 1),
        takipTarihi: Tarih(2026, 3, 2),
        islemisFaizElle: Para.tl(7));
    expect(IcraHesabi.islemisFaiz(elle, tablo), Para.tl(7));
  });

  test('kısmi ödeme önce masraf ve vekâlet ücretine, sonra faize, sonra asıl alacağa', () {
    final k = IcraHesabi.hesapla(
      talep: talep,
      tablo: tablo,
      hesapTarihi: Tarih(2026, 5, 1),
      tahsilatlar: [Tahsilat(id: 't1', tarih: Tarih(2026, 4, 1), tutar: Para.tl(20000))],
      takipSonrasiMasraf: Para.tl(268),
      vekaletUcreti: Para.tl(10000),
    );
    expect(k.masraflar, Para.kurus(201973));
    final m = k.mahsuplar.single;
    expect(m.masrafa, Para.kurus(1201973));
    expect(m.faize, Para.kurus(591781));
    expect(m.anaparaya, Para.kurus(206246));
    expect(m.fazla, Para.sifir);
    expect(k.kalanAnapara, Para.kurus(9793754));
    expect(k.kalanFaiz, Para.kurus(193192));
    expect(k.kalanMasraf, Para.sifir);
    expect(k.takipSonrasiFaiz, Para.kurus(390452));
    expect(k.kalanBorc, Para.kurus(9986946));
    expect(k.tahsilHarci, Para.kurus(454406));
    expect(k.pesinHarcMahsubu, Para.sifir);
    expect(k.cezaeviHarci, Para.kurus(40000));
    expect(k.uyarilar, contains('2026 icra harç tarifesi avukat onayı bekliyor.'));
  });

  test('peşin harç tahsil harcına mahsup edilir; fazla ödeme bildirilir; dosya kapanır', () {
    final ilk = IcraHesabi.hesapla(talep: talep, tablo: tablo, hesapTarihi: Tarih(2026, 3, 2), vekaletUcreti: Para.tl(10000));
    expect(ilk.masraflar, Para.kurus(175173));
    expect(ilk.kalanBorc, Para.kurus(11569694));
    expect(ilk.pesinHarcMahsubu, Para.kurus(51973));
    expect(ilk.tahsilHarci, Para.kurus(474448));
    expect(ilk.toplamAlacak, Para.kurus(11569694));

    final fazla = IcraHesabi.hesapla(
      talep: talep,
      tablo: tablo,
      hesapTarihi: Tarih(2026, 3, 2),
      tahsilatlar: [Tahsilat(id: 't', tarih: Tarih(2026, 3, 2), tutar: Para.tl(200000))],
    );
    expect(fazla.kapandi, isTrue);
    expect(fazla.mahsuplar.single.fazla.kurus, 20000000 - 10000000 - 394521 - 175173);
    expect(fazla.uyarilar.any((u) => u.contains('fazla ödeme')), isTrue);
    expect(() => IcraHesabi.hesapla(talep: talep, tablo: tablo, hesapTarihi: Tarih(2026, 3, 1)), throwsArgumentError);
  });

  test('icra durumu tahsil harcı aşamasını belirler', () {
    final d = IcraDosyasi(id: 'i1', dosyaId: 'd1', icraDairesi: 'İstanbul 3. İcra', borclu: 'Delta', talep: talep)
      ..durum = IcraDurumu.haciz;
    expect(d.durum.tahsilAsamasi, TahsilAsamasi.hacizSonrasi);
    final k = d.hesap(Tarih(2026, 3, 2), tablo);
    expect(k.tahsilHarci.kurus, (k.kalanBorc.kurus * 9.10 / 100).round() - 51973);
  });

  test('toplu takip satırları doğrulanır', () {
    final s = TopluTakip.dogrula([
      ['Ayşe Kara', '10000000146', '12.500,00', '01.10.2026'],
      ['', '', '0', '1.1.2026'],
      ['Mehmet Demirci', '10000000146', '5000', '31.02.2026'],
      ['Delta İnşaat', '', '1.250', '01.12.2026'],
    ], Tarih(2026, 11, 25), kimlikGecerli: (s) => Dogrulayicilar.tcknVeyaVkn(s) == null);
    expect(s[0].gecerli, isTrue);
    expect(s[0].alacak, Para.tl(12500));
    expect(s[0].temerrut, Tarih(2026, 10, 1));
    expect(s[1].hatalar, hasLength(2));
    expect(s[2].hatalar, containsAll(['Aynı borçlu listede birden fazla.', 'Temerrüt tarihi geçersiz.']));
    expect(s[3].alacak, Para.tl(1250));
    expect(s[3].hatalar, ['Temerrüt tarihi takip tarihinden sonra olamaz.']);
  });
}
