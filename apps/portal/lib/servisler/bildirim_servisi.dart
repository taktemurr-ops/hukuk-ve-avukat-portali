import 'package:flutter/foundation.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'kimlik_servisi.dart';
import 'kurumsal_depo.dart';
import 'veri_deposu.dart';

/// Bildirimin hedefi: dosya, talep, sözleşme veya tebligat kuyruğu.
enum BildirimHedefi { dosya, talep, sozlesme, tebligatKuyrugu }

class HedefliBildirim {
  const HedefliBildirim(this.bildirim, this.hedef);
  final Bildirim bildirim;
  final BildirimHedefi hedef;
}

/// Kullanıcının görmeye yetkili olduğu kaynaklardan bildirimleri toplar.
/// Yetki tek kapıdan (görünür dosyalar) geçer; görülemeyen dosyanın bildirimi üretilmez.
class BildirimServisi extends ChangeNotifier {
  BildirimServisi({required this.depo, required this.oturum, this.kurumsal, DateTime Function()? saat})
      : _saat = saat ?? DateTime.now;

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final KurumsalDepo? kurumsal;
  final DateTime Function() _saat;
  final BildirimKutusu kutu = BildirimKutusu();

  static const _yoneticiRolleri = {Rol.buroSahibi, Rol.yoneticiOrtak, Rol.hukukDirektoru};

  bool get _yonetici => oturum.roller.any(_yoneticiRolleri.contains);

  List<HedefliBildirim> topla() {
    final simdi = _saat();
    final bugun = Tarih.from(simdi);
    final aktor = Aktor(kullaniciId: oturum.kullaniciId, kiraciId: oturum.kiraciId, roller: oturum.roller);
    final dosyalar = {for (final d in depo.gorunurDosyalar(aktor)) d.id: d};
    final sonuc = <HedefliBildirim>[];
    DateTime gun(Tarih t) => DateTime.utc(t.yil, t.ay, t.gun);

    for (final u in depo.uyarilar(bugun)) {
      final d = dosyalar[u.sure.dosyaId];
      if (d == null) continue;
      final bana = u.alicilar.contains(oturum.kullaniciId) || (_yonetici && u.alicilar.contains('yonetici'));
      if (!bana) continue;
      sonuc.add(HedefliBildirim(
        Bildirim(
          id: 'sure:${u.sure.id}:${u.seviye.name}',
          tur: BildirimTuru.sure,
          oncelik: switch (u.seviye) {
            UyariSeviyesi.kritik || UyariSeviyesi.yonetici => BildirimOnceligi.kritik,
            UyariSeviyesi.yedekSorumlu => BildirimOnceligi.uyari,
            UyariSeviyesi.hatirlatma => BildirimOnceligi.bilgi,
          },
          baslik: u.mesaj,
          aciklama: '${d.icNo} · ${d.baslik}',
          zaman: gun(u.sure.sonGun),
          hedefId: d.id,
        ),
        BildirimHedefi.dosya,
      ));
    }

    for (final du in depo.durusmalar) {
      final d = dosyalar[du.dosyaId];
      if (d == null || du.katilan != oturum.kullaniciId) continue;
      final kalan = du.baslangic.difference(simdi);
      if (kalan.isNegative || kalan > const Duration(hours: 48)) continue;
      sonuc.add(HedefliBildirim(
        Bildirim(
          id: 'durusma:${du.id}',
          tur: BildirimTuru.durusma,
          oncelik: kalan < const Duration(hours: 24) ? BildirimOnceligi.kritik : BildirimOnceligi.uyari,
          baslik: '${du.tur}: ${du.yer}',
          aciklama: '${d.icNo} · ${d.baslik}',
          zaman: du.baslangic,
          hedefId: d.id,
        ),
        BildirimHedefi.dosya,
      ));
    }

    final kuyruk = depo.eslesmeyenTebligatlar;
    if (kuyruk.isNotEmpty) {
      sonuc.add(HedefliBildirim(
        Bildirim(
          id: 'tebligat:${kuyruk.map((t) => t.id).join(',')}',
          tur: BildirimTuru.tebligat,
          oncelik: BildirimOnceligi.uyari,
          baslik: '${kuyruk.length} tebligat dosyayla eşleştirilmeyi bekliyor',
          aciklama: 'Süre hesabı eşleştirmeden sonra başlar.',
          zaman: gun(kuyruk.map((t) => t.ulasmaTarihi).reduce((a, b) => a.isAfter(b) ? a : b)),
        ),
        BildirimHedefi.tebligatKuyrugu,
      ));
    }

    for (final d in dosyalar.values) {
      final n = depo.okunmamisMuvekkilMesaji(d.id);
      if (n == 0) continue;
      final son = depo.dosyaMesajlari(d.id).last;
      sonuc.add(HedefliBildirim(
        Bildirim(
          id: 'mesaj:${son.id}',
          tur: BildirimTuru.mesaj,
          oncelik: BildirimOnceligi.bilgi,
          baslik: '$n yeni müvekkil mesajı',
          aciklama: '${d.icNo} · ${d.baslik}',
          zaman: son.zaman,
          hedefId: d.id,
        ),
        BildirimHedefi.dosya,
      ));
    }

    final k = kurumsal;
    if (k != null) {
      for (final t in k.defter.talepler.where((t) => !t.durum.kapali)) {
        if (t.atanan != oturum.kullaniciId && !(_yonetici && t.atanan.isEmpty)) continue;
        final sla = k.sla(t);
        if (sla != SlaDurumu.riskli && sla != SlaDurumu.gecikti && t.atanan.isNotEmpty) continue;
        sonuc.add(HedefliBildirim(
          Bildirim(
            id: 'talep:${t.id}:${t.atanan.isEmpty ? 'atanmamis' : sla.name}',
            tur: BildirimTuru.talep,
            oncelik: sla == SlaDurumu.gecikti ? BildirimOnceligi.kritik : BildirimOnceligi.uyari,
            baslik: t.atanan.isEmpty ? 'Atanmamış talep: ${t.baslik}' : '${sla.ad}: ${t.baslik}',
            aciklama: '${t.no} · ${t.birim} · hedef ${t.slaSonGun.turkceBicim}',
            zaman: gun(t.slaSonGun),
            hedefId: t.id,
          ),
          BildirimHedefi.talep,
        ));
      }
      for (final (s, u) in k.uyarilar(ufukGun: 30)) {
        final kritik = u.tur == SozlesmeUyariTuru.ihbarKacti || u.tur == SozlesmeUyariTuru.yukumlulukGecikti;
        sonuc.add(HedefliBildirim(
          Bildirim(
            id: 'sozlesme:${s.id}:${u.tur.name}:${u.tarih.isoBicim}',
            tur: BildirimTuru.sozlesme,
            oncelik: kritik ? BildirimOnceligi.kritik : BildirimOnceligi.uyari,
            baslik: u.mesaj,
            aciklama: '${s.no} · ${s.baslik}',
            zaman: gun(u.tarih),
            hedefId: s.id,
          ),
          BildirimHedefi.sozlesme,
        ));
      }
    }

    final siralama = kutu.sirala(sonuc.map((h) => h.bildirim));
    final bul = {for (final h in sonuc) h.bildirim.id: h};
    return [for (final b in siralama) bul[b.id]!];
  }

  int okunmamis() => kutu.okunmamis(topla().map((h) => h.bildirim));

  void oku(String id) {
    kutu.oku(id);
    notifyListeners();
  }

  void tumunuOku() {
    kutu.tumunuOku(topla().map((h) => h.bildirim));
    notifyListeners();
  }
}
