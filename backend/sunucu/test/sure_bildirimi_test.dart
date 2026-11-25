import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  final bugun = Tarih(2026, 11, 25);
  SureKaydi sure({required Tarih son, SureDurumu durum = SureDurumu.teyitli, String? yedek = 'u2'}) => SureKaydi(
        id: 's1',
        dosyaId: 'd1',
        aciklama: 'Cevap dilekçesi · ABC Gıda A.Ş.',
        sonuc: SureSonucu(
            kural: KuralKatalogu.tohumKurallar.first, baslangic: son, sonGun: son, adimlar: const [], uyarilar: const []),
        olusturan: 'u3',
        olusturmaTarihi: bugun,
        asilSorumlu: 'u1',
        yedekSorumlu: yedek,
        durum: durum,
      );

  List<SureUyarisi> uyar(SureKaydi s) => const EskalasyonMotoru().degerlendir([s], bugun);

  test('üç gün kala yalnızca asıl sorumluya hatırlatma; metinde müvekkil adı yok', () {
    final u = uyar(sure(son: Tarih(2026, 11, 28))).single;
    expect(u.seviye, UyariSeviyesi.hatirlatma);
    expect(u.alicilar, {'u1'});
    final (konu, metin) = SureBildirimGorevi.epostaMetni(u, '2026/0001', bugun, portalAdresi: Uri.parse('https://app.ornek/'));
    expect(konu, contains('3 gün'));
    expect(metin, contains('28.11.2026'));
    expect(metin, contains('https://app.ornek/'));
    expect('$konu $metin', isNot(contains('ABC')));
  });

  test('süre geçtiyse kritik; yöneticiler de alıcı', () {
    final u = uyar(sure(son: Tarih(2026, 11, 24))).single;
    expect(u.seviye, UyariSeviyesi.kritik);
    expect(u.alicilar, containsAll(['u1', 'u2', 'yonetici']));
    expect(SureBildirimGorevi.epostaMetni(u, '2026/0001', bugun).$1, startsWith('KRİTİK'));
  });

  test('teyit edilmemiş ve yaklaşan süre yöneticiye çıkar', () {
    final u = uyar(sure(son: Tarih(2026, 11, 27), durum: SureDurumu.teyitBekliyor)).single;
    expect(u.seviye, UyariSeviyesi.yonetici);
    expect(SureBildirimGorevi.epostaMetni(u, '2026/0001', bugun).$1, contains('teyit'));
  });
}
