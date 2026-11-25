import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'sunucu_senkronu.dart';
import 'veri_deposu.dart';

/// Müvekkil portalı oturumunda sunucudan yalnızca `portal/...` uçlarıyla veri alır ve yerel önbelleği doldurur.
/// Müvekkil yalnızca büronun paylaştığı ve müvekkili olduğu dosyaları, paylaşılan belgeleri ve yazışmaları görür.
class PortalSenkronu implements MesajUzak {
  PortalSenkronu(this.api, this.depo, {required this.kisiId}) {
    depo.mesajUzak = this;
  }

  final ApiIstemcisi api;
  final BellekVeriDeposu depo;
  final String kisiId;

  static List<Map<String, dynamic>> _liste(Object? v) => (v! as List).cast<Map<String, dynamic>>();

  Future<void> yenile() async {
    final dosyalarJ = _liste(await api.get('/portal/dosyalar'));
    final dosyalar = <Dosya>[];
    final durusmalar = <Durusma>[];
    final belgeler = <Belge>[];
    final paylasilanBelgeler = <String>{};
    final mesajlar = <PortalMesaji>[];
    for (final j in dosyalarJ) {
      final id = j['id'] as String;
      // Sorumlu alanına müvekkile kullanıcı kimliği değil avukatın adı konur.
      dosyalar.add(Dosya(
        id: id,
        kiraciId: depo.kiraciId,
        icNo: j['icNo'] as String,
        tur: DosyaTuru.values.firstWhere((t) => t.name == j['tur'], orElse: () => DosyaTuru.hukuk),
        baslik: j['baslik'] as String,
        sorumlu: j['sorumluAvukat'] as String,
        asama: DosyaAsamasi.values.firstWhere((a) => a.name == j['asama'], orElse: () => DosyaAsamasi.onDegerlendirme),
        acilisTarihi: Tarih.parse(j['acilis'] as String),
      ));
      final d = j['sonrakiDurusma'] as String?;
      if (d != null) {
        durusmalar.add(Durusma(
          id: 'du-$id',
          dosyaId: id,
          baslangic: DateTime.parse(d).toLocal(),
          yer: j['sonrakiDurusmaYeri'] as String? ?? '',
          katilan: j['sorumluAvukat'] as String,
        ));
      }
      for (final b in _liste(await api.get('/portal/dosyalar/$id/belgeler'))) {
        final zaman = DateTime.parse(b['zaman'] as String).toLocal();
        belgeler.add(Belge(
          id: b['id'] as String,
          kiraciId: depo.kiraciId,
          ad: b['ad'] as String,
          tur: BelgeTuru.values.firstWhere((t) => t.name == b['tur'], orElse: () => BelgeTuru.diger),
          dosyaId: id,
          ilkSurum: BelgeSurumu(
            no: b['surum'] as int,
            ozet: b['sha256'] as String,
            boyut: b['boyut'] as int,
            yukleyen: '',
            tarih: Tarih.from(zaman),
            dosyaAdi: b['dosyaAdi'] as String,
          ),
        ));
        paylasilanBelgeler.add(b['id'] as String);
      }
      for (final m in _liste(await api.get('/portal/dosyalar/$id/mesajlar'))) {
        mesajlar.add(SunucuSenkronu.mesajJson(m, id));
      }
    }
    depo.sunucuVerisiniYukle(dosyalar: dosyalar, sureler: const [], belgeler: belgeler);
    depo.sunucuBuroVerisiniYukle(
      taraflar: [
        for (final d in dosyalar) DosyaTarafKaydi(dosyaId: d.id, dosyaAdi: d.baslik, kisiId: kisiId, sifat: TarafSifati.muvekkil),
      ],
      gorevler: const [],
      durusmalar: durusmalar,
      tebligatlar: const [],
      vekaletnameler: const [],
    );
    depo.sunucuPortalVerisiniYukle(
      portalDosyalari: {for (final d in dosyalar) d.id},
      paylasilanBelgeler: paylasilanBelgeler,
      mesajlar: mesajlar,
    );
  }

  @override
  Future<void> mesajGonder(String dosyaId, String metin) async {
    await api.post('/portal/dosyalar/$dosyaId/mesajlar', {'metin': metin.trim()});
    await yenile();
  }

  @override
  Future<void> mesajlariOku(String dosyaId) async {
    await api.post('/portal/dosyalar/$dosyaId/okundu');
    await yenile();
  }
}
