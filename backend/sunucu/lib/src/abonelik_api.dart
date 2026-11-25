import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'hata.dart';
import 'kimlik_api.dart';
import 'odeme_saglayici.dart';
import 'ortak.dart';
import 'veritabani.dart';

/// Abonelik ve ödeme. Tutar her zaman sunucuda, paket ve KDV kurallarıyla hesaplanır; abonelik yalnızca imzası
/// doğrulanmış sağlayıcı bildirimiyle uzar. Kart bilgisi platformdan geçmez (sağlayıcının sayfasında girilir).
class AbonelikApi {
  AbonelikApi(this.vt, this.saglayici);

  final Veritabani vt;

  /// Seçilmemişse ödeme başlatılamaz (503).
  final OdemeSaglayici? saglayici;

  Router get router {
    final r = Router()
      ..get('/abonelik', _bilgi)
      ..post('/abonelik/odeme', _odemeBaslat)
      ..post('/abonelik/iptal', _iptal)
      ..post('/acik/odeme-bildirimi/<ad>', _bildirim);
    final s = saglayici;
    if (s is SahteOdemeSaglayici) {
      r.get('/acik/sahte-odeme/<referans>', (Request istek, String referans) => s.sayfa(referans, istek.url.queryParameters));
    }
    return r;
  }

  static Map<String, Object?> _fiyat(Paket p, OdemeDonemi donem, int koltuk) {
    final f = FaturaTutari.hesapla(p.donemTutari(donem, ucretliKoltuk: koltuk));
    return {'donem': donem.name, 'koltuk': koltuk, 'matrahKurus': f.matrah.kurus, 'kdvKurus': f.kdv.kurus, 'toplamKurus': f.toplam.kurus};
  }

  Future<Response> _bilgi(Request istek) async {
    final k = kimlik(istek);
    final (bilgi, koltuk, odemeler) = await vt.kiraciIcin(k, (tx) async {
      final b = await tx.execute('SELECT durum, etkin_durum, donem, donem_basi, donem_sonu, ucretli_koltuk, donem_sonunda_iptal, '
          'hesap_turu FROM hukuk.abonelik_bilgisi()');
      final kt = await tx.execute('SELECT lisans, dolu FROM hukuk.koltuk_durumu()');
      // Ödeme geçmişini yalnızca yöneticiler görür (RLS); diğerlerinde liste boş döner.
      final o = await tx.execute('SELECT id::text, olusturma, donem, koltuk, toplam_kurus, durum, hata FROM hukuk.odeme '
          'ORDER BY olusturma DESC LIMIT 24');
      return (b, kt, o);
    });
    if (bilgi.isEmpty) throw const ApiHatasi(404, 'Abonelik kaydı bulunamadı.', kod: 'bulunamadi');
    final b = bilgi.first;
    final tur = HesapTuru.values.byName(b[7]! as String);
    final paket = Paket.taslakPaketler[tur]!;
    final dolu = koltuk.first[1]! as int;
    final ucretli = (b[5]! as int) > dolu ? b[5]! as int : dolu;
    return jsonYanit({
      'durum': b[0],
      'etkinDurum': b[1],
      'etkinDurumAdi': AbonelikDurumu.values.where((d) => d.name == b[1]).map((d) => d.ad).firstOrNull ?? b[1],
      'donem': b[2],
      'donemBasi': tarihMetni(b[3]),
      'donemSonu': tarihMetni(b[4]),
      'ucretliKoltuk': b[5],
      'kullanilanKoltuk': dolu,
      'donemSonundaIptal': b[6],
      'yazilabilir': b[1] != 'askida' && b[1] != 'iptal',
      'paket': {'hesapTuru': tur.name, 'fiyatTuru': paket.fiyatTuru.name, 'aylikFiyatKurus': paket.aylikFiyat.kurus},
      'fiyatlar': paket.fiyatTuru == FiyatTuru.teklif
          ? <Object>[]
          : [for (final d in OdemeDonemi.values) _fiyat(paket, d, paket.fiyatTuru == FiyatTuru.koltukBasi ? ucretli : 1)],
      'odemeAltyapisi': saglayici != null,
      'odemeler': [
        for (final o in odemeler)
          {
            'id': o[0],
            'zaman': (o[1]! as DateTime).toIso8601String(),
            'donem': o[2],
            'koltuk': o[3],
            'toplamKurus': o[4],
            'durum': o[5],
            'hata': o[6],
          },
      ],
    });
  }

  /// Yönetici ödeme başlatır: tutar sunucuda hesaplanır, ödeme kaydı açılır, sağlayıcının sayfa adresi döner.
  Future<Response> _odemeBaslat(Request istek) async {
    final k = kimlik(istek);
    final s = saglayici;
    if (s == null) {
      throw const ApiHatasi(503, 'Ödeme altyapısı henüz bağlanmadı; lütfen bizimle iletişime geçin.', kod: 'odeme_yok');
    }
    final j = await jsonGovde(istek);
    final donem = enumAlani(j, 'donem', OdemeDonemi.values);
    final referans = rastgeleReferans();
    final (istekBilgisi, toplam) = await vt.kiraciIcin(k, (tx) async {
      final b = await tx.execute('SELECT hesap_turu, etkin_durum FROM hukuk.abonelik_bilgisi()');
      if (b.isEmpty) throw const ApiHatasi(404, 'Abonelik kaydı bulunamadı.', kod: 'bulunamadi');
      if (b.first[1] == 'iptal') throw const ApiHatasi(409, 'İptal edilmiş abonelik yeniden ödenemez; bizimle iletişime geçin.', kod: 'kural');
      final paket = Paket.taslakPaketler[HesapTuru.values.byName(b.first[0]! as String)]!;
      if (paket.fiyatTuru == FiyatTuru.teklif) {
        throw const ApiHatasi(409, 'Kurumsal paket teklif usulüdür; ödeme sözleşmeye göre faturalanır.', kod: 'teklif');
      }
      final kt = await tx.execute('SELECT dolu FROM hukuk.koltuk_durumu()');
      final dolu = kt.first[0]! as int;
      var koltuk = 1;
      if (paket.fiyatTuru == FiyatTuru.koltukBasi) {
        koltuk = j['koltuk'] is int ? j['koltuk'] as int : dolu;
        if (koltuk < dolu) {
          throw ApiHatasi(400, 'Ücretli koltuk sayısı kullanılan koltuktan ($dolu) az olamaz.', kod: 'gecersiz_istek');
        }
        if (koltuk > 500) throw const ApiHatasi(400, 'Koltuk sayısı çok yüksek; teklif için bizimle iletişime geçin.');
      }
      final f = FaturaTutari.hesapla(paket.donemTutari(donem, ucretliKoltuk: koltuk));
      await tx.execute(
        Sql.named('INSERT INTO hukuk.odeme (kiraci_id, saglayici, referans, donem, koltuk, matrah_kurus, kdv_kurus, toplam_kurus) '
            'VALUES (CAST(@k AS uuid), @s, @r, @d, @ko, @m, @kd, @t)'),
        parameters: {
          'k': k.kiraciId,
          's': s.ad,
          'r': referans,
          'd': donem.name,
          'ko': koltuk,
          'm': f.matrah.kurus,
          'kd': f.kdv.kurus,
          't': f.toplam.kurus,
        },
      );
      final u = await tx.execute(
        Sql.named('SELECT u.eposta, u.ad_soyad, k.ad FROM hukuk.kullanici u JOIN hukuk.kiraci k ON k.id = u.kiraci_id '
            'WHERE u.id = CAST(@u AS uuid)'),
        parameters: {'u': k.kullaniciId},
      );
      return (
        OdemeIstegi(
          referans: referans,
          toplamKurus: f.toplam.kurus,
          aciklama: '${u.first[2]} · ${donem.ad} abonelik${koltuk > 1 ? ' · $koltuk kullanıcı' : ''}',
          eposta: u.first[0]! as String,
          adSoyad: u.first[1]! as String,
          istemciIp: istek.headers['x-forwarded-for']?.split(',').first.trim() ?? '',
        ),
        f.toplam.kurus
      );
    });
    final baslangic = await s.baslat(istekBilgisi);
    return jsonYanit({'referans': referans, 'toplamKurus': toplam, 'odemeAdresi': baslangic.odemeAdresi.toString()}, durum: 201);
  }

  Future<Response> _iptal(Request istek) async {
    final k = kimlik(istek);
    final iptal = (await jsonGovde(istek))['iptal'] != false;
    await vt.kiraciIcin(k, (tx) => tx.execute(Sql.named('SELECT hukuk.abonelik_iptal(@i)'), parameters: {'i': iptal}));
    return jsonYanit({'donemSonundaIptal': iptal});
  }

  /// Sağlayıcı bildirimi (oturumsuz). İmza doğrulanmazsa hiçbir şey yazılmaz.
  Future<Response> _bildirim(Request istek, String ad) async {
    final s = saglayici;
    if (s == null || s.ad != ad) return Response.notFound('Bulunamadı');
    final govde = await istek.readAsString();
    if (govde.length > 64 * 1024) throw const ApiHatasi(413, 'İstek çok büyük.');
    final alanlar = (istek.headers['content-type'] ?? '').contains('json')
        ? {for (final e in (jsonGovdeMetinden(govde)).entries) e.key: '${e.value}'}
        : Uri.splitQueryString(govde);
    final b = s.bildirimDogrula(alanlar, istek.headers);
    if (b == null) throw const ApiHatasi(400, 'Bildirim imzası doğrulanamadı.', kod: 'imza');
    await vt.genel((tx) => tx.execute(
          Sql.named('SELECT hukuk.odeme_sonuclandi(@r, @b, @t, @i, @h)'),
          parameters: {'r': b.referans, 'b': b.basarili, 't': b.tutarKurus, 'i': b.islemNo, 'h': b.hata},
        ));
    return s.bildirimYaniti();
  }
}
