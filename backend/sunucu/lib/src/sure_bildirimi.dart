import 'dart:async';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';

import 'ortak.dart';
import 'veritabani.dart';

/// Süre hatırlatma ve eskalasyon e-postaları. Kurallar çekirdekteki [EskalasyonMotoru]'ndan gelir (uygulamadaki
/// uyarılarla aynı); her uyarı aynı gün bir kez gönderilir (veritabanı tekilliği). Alıcı adresleri veritabanında
/// çözülür ve uygulamaya çıkmaz. E-posta metni müvekkil ya da dosya başlığı içermez: yalnızca dosya iç numarası
/// ve tarih (e-posta üçüncü taraf sunuculardan geçebilir).
class SureBildirimGorevi {
  SureBildirimGorevi(
    this.vt, {
    this.motor = const EskalasyonMotoru(),
    this.portalAdresi,
    this.aralik = const Duration(hours: 1),
    this.baslangicSaati = 8,
    this.saat,
    this.kaydet,
  });

  final Veritabani vt;
  final EskalasyonMotoru motor;
  final Uri? portalAdresi;
  final Duration aralik;

  /// Türkiye saatiyle bu saatten önce e-posta gönderilmez (gece yarısı uyandırmamak için).
  final int baslangicSaati;

  /// Testler için; verilmezse şimdiki an.
  final DateTime Function()? saat;
  final void Function(Object hata)? kaydet;
  Timer? _zamanlayici;
  bool _calisiyor = false;

  static const _yonetici = 'yonetici';

  void baslat() {
    unawaited(birTur());
    _zamanlayici ??= Timer.periodic(aralik, (_) => birTur());
  }

  void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  /// Türkiye'de yaz saati uygulanmıyor: UTC+3.
  DateTime get _turkiyeSaati => (saat?.call() ?? DateTime.now()).toUtc().add(const Duration(hours: 3));

  /// Bir tur: kuyruğa yazılan e-posta sayısını döner.
  Future<int> birTur() async {
    if (_calisiyor) return 0;
    final simdi = _turkiyeSaati;
    if (simdi.hour < baslangicSaati) return 0;
    _calisiyor = true;
    var toplam = 0;
    try {
      final bugun = Tarih(simdi.year, simdi.month, simdi.day);
      final rs = await vt.genel((tx) => tx.execute(
          'SELECT kiraci_id::text, sure_id::text, dosya_id::text, ic_no, kural_kodu, son_gun, durum, olusturma, '
          'olusturan::text, asil_sorumlu::text, yedek_sorumlu::text FROM hukuk.sure_bildirim_adaylari()'));
      final kiraci = <String, String>{};
      final icNo = <String, String>{};
      final sureler = <SureKaydi>[];
      for (final r in rs) {
        kiraci[r[1]! as String] = r[0]! as String;
        icNo[r[1]! as String] = r[3]! as String;
        final sonGun = tarihDegeri(r[5]);
        sureler.add(SureKaydi(
          id: r[1]! as String,
          dosyaId: r[2]! as String,
          aciklama: '',
          // Motor kuralı kullanmaz; katalogda olmayan eski bir kod da hatırlatılsın diye yedek kural.
          sonuc: SureSonucu(
            kural: KuralKatalogu.bul(r[4]! as String) ?? KuralKatalogu.tohumKurallar.first,
            baslangic: sonGun,
            sonGun: sonGun,
            adimlar: const [],
            uyarilar: const [],
          ),
          olusturan: r[8]! as String,
          olusturmaTarihi: tarihDegeri(r[7]),
          asilSorumlu: r[9]! as String,
          yedekSorumlu: r[10] as String?,
          durum: SureDurumu.values.byName(r[6]! as String),
        ));
      }
      for (final u in motor.degerlendir(sureler, bugun)) {
        final s = u.sure;
        final (konu, metin) = epostaMetni(u, icNo[s.id]!, bugun, portalAdresi: portalAdresi);
        try {
          final n = await vt.genel((tx) => tx.execute(
                Sql.named('SELECT hukuk.sure_bildirimi_gonder(CAST(@k AS uuid), CAST(@s AS uuid), CAST(@g AS date), @v, '
                    'CAST(@u AS uuid[]), @y, @konu, @metin)'),
                parameters: {
                  'k': kiraci[s.id],
                  's': s.id,
                  'g': bugun.isoBicim,
                  'v': u.seviye.name,
                  'u': '{${u.alicilar.where((a) => a != _yonetici && a.isNotEmpty).join(',')}}',
                  'y': u.alicilar.contains(_yonetici),
                  'konu': konu,
                  'metin': metin,
                },
              ));
          toplam += n.first[0]! as int;
        } on Object catch (e) {
          kaydet?.call(e); // bir sürenin hatası diğerlerini durdurmasın
        }
      }
    } on Object catch (e) {
      kaydet?.call(e);
    } finally {
      _calisiyor = false;
    }
    return toplam;
  }

  /// Konu ve metin; müvekkil adı, dosya başlığı ya da süre açıklaması içermez.
  static (String, String) epostaMetni(SureUyarisi u, String icNo, Tarih bugun, {Uri? portalAdresi}) {
    final s = u.sure;
    final son = s.sonGun.turkceBicim;
    final kalan = s.kalanGun(bugun);
    final (konu, govde) = switch (u.seviye) {
      UyariSeviyesi.kritik => (
          'KRİTİK: $icNo dosyasında süre geçti',
          '$icNo numaralı dosyadaki bir sürenin son günü ($son) geçti ve işlem kaydı yok. '
              'Lütfen hemen kontrol edin ve yapılan işlemi kanıtıyla kaydedin.'
        ),
      UyariSeviyesi.yonetici when s.sahipsiz => (
          '$icNo dosyasında sorumlusu olmayan süre',
          '$icNo numaralı dosyadaki bir sürenin (son gün $son) sorumlusu yok. Bir avukat atanmalı.'
        ),
      UyariSeviyesi.yonetici when s.durum == SureDurumu.teyitBekliyor => (
          '$icNo dosyasında teyit edilmemiş süre',
          '$icNo numaralı dosyadaki bir sürenin hesabı henüz ikinci bir avukatça teyit edilmedi (son gün $son). '
              'Teyit edilmeden süre kesinleşmiş sayılmaz.'
        ),
      UyariSeviyesi.yonetici => (
          'Bugün son gün: $icNo',
          '$icNo numaralı dosyadaki bir sürenin son günü bugün ($son).'
        ),
      UyariSeviyesi.yedekSorumlu => (
          'Yarın son gün: $icNo',
          '$icNo numaralı dosyadaki bir sürenin son günü yarın ($son). Asıl veya yedek sorumlu olarak listelisiniz.'
        ),
      UyariSeviyesi.hatirlatma => (
          'Süre hatırlatması: $icNo · $kalan gün kaldı',
          'Sorumlusu olduğunuz $icNo numaralı dosyadaki bir sürenin son gününe $kalan gün kaldı (son gün $son).'
        ),
    };
    final adres = portalAdresi;
    return (
      konu,
      '$govde\n\nAyrıntılar için portala giriş yapın${adres == null ? '' : ': $adres'}.\n'
          'Güvenliğiniz için bu e-postada müvekkil ya da dosya bilgisi yer almaz.'
    );
  }
}
