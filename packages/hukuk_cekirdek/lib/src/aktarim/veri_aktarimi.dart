import '../kimlik/dogrulayicilar.dart';
import '../taraf/isim_eslestirme.dart';
import '../taraf/kisi.dart';

/// RFC 4180 uyumlu CSV ayrıştırıcı. Excel'in Türkçe sürümünün ürettiği ";" ayraçlı
/// dosyaları, tırnak içindeki satır sonlarını ve UTF-8 BOM'u destekler.
class CsvAyristirici {
  CsvAyristirici._();

  static String ayiriciBul(String metin) {
    final ilkSatir = metin.split(RegExp(r'\r?\n')).first;
    final adaylar = {';': ';'.allMatches(ilkSatir).length, ',': ','.allMatches(ilkSatir).length, '\t': '\t'.allMatches(ilkSatir).length};
    var enIyi = ';';
    var enCok = -1;
    adaylar.forEach((a, n) {
      if (n > enCok) {
        enIyi = a;
        enCok = n;
      }
    });
    return enIyi;
  }

  static List<List<String>> ayristir(String metin, {String? ayirici}) {
    var m = metin;
    if (m.startsWith('﻿')) m = m.substring(1);
    final a = ayirici ?? ayiriciBul(m);
    final satirlar = <List<String>>[];
    var satir = <String>[];
    final alan = StringBuffer();
    var tirnakta = false;
    for (var i = 0; i < m.length; i++) {
      final c = m[i];
      if (tirnakta) {
        if (c == '"') {
          if (i + 1 < m.length && m[i + 1] == '"') {
            alan.write('"');
            i++;
          } else {
            tirnakta = false;
          }
        } else {
          alan.write(c);
        }
        continue;
      }
      if (c == '"' && alan.isEmpty) {
        tirnakta = true;
      } else if (c == a) {
        satir.add(alan.toString());
        alan.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < m.length && m[i + 1] == '\n') i++;
        satir.add(alan.toString());
        alan.clear();
        if (satir.any((s) => s.trim().isNotEmpty)) satirlar.add(satir);
        satir = <String>[];
      } else {
        alan.write(c);
      }
    }
    if (alan.isNotEmpty || satir.isNotEmpty) {
      satir.add(alan.toString());
      if (satir.any((s) => s.trim().isNotEmpty)) satirlar.add(satir);
    }
    return satirlar;
  }
}

enum KisiAlani {
  ad('Ad soyad / unvan'),
  tur('Tür'),
  kimlikNo('TCKN / VKN'),
  eposta('E-posta'),
  telefon('Telefon'),
  adres('Adres');

  const KisiAlani(this.ad);

  final String ad;
}

const Map<KisiAlani, List<String>> _esAnlamlilar = {
  KisiAlani.ad: ['ad', 'adi', 'ad soyad', 'adi soyadi', 'isim', 'unvan', 'unvani', 'muvekkil', 'musteri', 'firma', 'kisi'],
  KisiAlani.tur: ['tur', 'turu', 'tip', 'kisi turu'],
  KisiAlani.kimlikNo: ['tckn', 'tc', 'tc no', 'tc kimlik', 'tc kimlik no', 'kimlik no', 'vkn', 'vergi no', 'vergi kimlik no', 'tckn vkn'],
  KisiAlani.eposta: ['eposta', 'e posta', 'email', 'e mail', 'mail'],
  KisiAlani.telefon: ['telefon', 'tel', 'gsm', 'cep', 'cep telefonu', 'telefon no'],
  KisiAlani.adres: ['adres', 'adresi', 'acik adres'],
};

/// Başlık satırından sütun eşlemesini tahmin eder; kullanıcı ekranda düzeltebilir.
Map<KisiAlani, int> sutunEslemesiTahminEt(List<String> basliklar) {
  final esleme = <KisiAlani, int>{};
  for (var i = 0; i < basliklar.length; i++) {
    final n = IsimEslestirme.normallestir(basliklar[i]);
    for (final e in _esAnlamlilar.entries) {
      if (!esleme.containsKey(e.key) && e.value.contains(n)) {
        esleme[e.key] = i;
        break;
      }
    }
  }
  return esleme;
}

enum SatirDurumu { aktarilacak, mukerrer, hatali }

class AktarimSatiri {
  AktarimSatiri({required this.satirNo, required this.degerler});

  /// Dosyadaki satır numarası (başlık 1. satır).
  final int satirNo;
  final Map<KisiAlani, String> degerler;
  final List<String> hatalar = [];
  final List<String> uyarilar = [];
  KisiTuru tur = KisiTuru.gercek;
  String? mukerrerAciklama;

  SatirDurumu get durum => hatalar.isNotEmpty
      ? SatirDurumu.hatali
      : mukerrerAciklama != null
          ? SatirDurumu.mukerrer
          : SatirDurumu.aktarilacak;

  String deger(KisiAlani a) => degerler[a]?.trim() ?? '';
}

class AktarimOnizlemesi {
  const AktarimOnizlemesi({required this.basliklar, required this.esleme, required this.satirlar});

  final List<String> basliklar;
  final Map<KisiAlani, int> esleme;
  final List<AktarimSatiri> satirlar;

  int sayi(SatirDurumu d) => satirlar.where((s) => s.durum == d).length;

  /// Sayım mutabakatı: okunan = aktarılacak + mükerrer + hatalı.
  bool get mutabik => satirlar.length == sayi(SatirDurumu.aktarilacak) + sayi(SatirDurumu.mukerrer) + sayi(SatirDurumu.hatali);
}

/// Excel/CSV'den müvekkil ve taraf aktarımı: önizleme, doğrulama, mükerrer kontrolü.
class KisiAktarimi {
  KisiAktarimi._();

  static final _tuzelIpucu = RegExp(r'\b(a\.?\s?ş\.?|ltd\.?|şti\.?|limited|anonim|holding|koop|vakf|derne)', caseSensitive: false);

  static AktarimOnizlemesi onizle({required String csv, required Iterable<Kisi> mevcut, Map<KisiAlani, int>? esleme}) {
    final tablo = CsvAyristirici.ayristir(csv);
    if (tablo.isEmpty) return const AktarimOnizlemesi(basliklar: [], esleme: {}, satirlar: []);
    final basliklar = tablo.first;
    final e = esleme ?? sutunEslemesiTahminEt(basliklar);
    final mevcutListe = mevcut.toList();
    final dosyadaGorulen = <String, int>{};
    final satirlar = <AktarimSatiri>[];

    for (var i = 1; i < tablo.length; i++) {
      final hucreler = tablo[i];
      final s = AktarimSatiri(satirNo: i + 1, degerler: {
        for (final x in e.entries)
          if (x.value < hucreler.length) x.key: hucreler[x.value],
      });

      final ad = s.deger(KisiAlani.ad);
      if (ad.isEmpty) s.hatalar.add('Ad / unvan boş.');

      final no = s.deger(KisiAlani.kimlikNo).replaceAll(RegExp(r'\s'), '');
      final turMetni = IsimEslestirme.normallestir(s.deger(KisiAlani.tur));
      if (no.length == 11) {
        s.tur = KisiTuru.gercek;
        if (!Dogrulayicilar.tcknGecerli(no)) s.hatalar.add('TC kimlik numarası geçersiz.');
      } else if (no.length == 10) {
        s.tur = KisiTuru.tuzel;
        if (!Dogrulayicilar.vknGecerli(no)) s.hatalar.add('Vergi kimlik numarası geçersiz.');
      } else if (no.isNotEmpty) {
        s.hatalar.add('Kimlik numarası 10 (VKN) veya 11 (TCKN) haneli olmalı.');
      } else if (turMetni.contains('tuzel') || turMetni.contains('sirket') || turMetni.contains('kurum')) {
        s.tur = KisiTuru.tuzel;
      } else if (_tuzelIpucu.hasMatch(ad)) {
        s.tur = KisiTuru.tuzel;
      }

      final ep = s.deger(KisiAlani.eposta);
      if (ep.isNotEmpty && Dogrulayicilar.eposta(ep) != null) {
        s.uyarilar.add('E-posta geçersiz; boş aktarılacak.');
        s.degerler.remove(KisiAlani.eposta);
      }
      final tel = s.deger(KisiAlani.telefon);
      if (tel.isNotEmpty && Dogrulayicilar.cepTelefonu(tel) != null) {
        s.uyarilar.add('Telefon cep telefonu biçiminde değil; olduğu gibi aktarılacak.');
      }

      if (s.hatalar.isEmpty) {
        final anahtar = no.isNotEmpty ? 'no:$no' : 'ad:${IsimEslestirme.normallestir(ad)}';
        final onceki = dosyadaGorulen[anahtar];
        if (onceki != null) {
          s.mukerrerAciklama = 'Dosyada $onceki. satırla aynı kayıt.';
        } else {
          dosyadaGorulen[anahtar] = s.satirNo;
          final adaylar = MukerrerKontrol.bul(mevcutListe, ad: ad, kimlikNo: no.isEmpty ? null : no);
          final kesin = adaylar.where((a) => a.tur == MukerrerTuru.kesin || a.benzerlik >= 1).toList();
          if (kesin.isNotEmpty) {
            s.mukerrerAciklama = 'Sistemde kayıtlı: ${kesin.first.kisi.ad}';
          } else if (adaylar.isNotEmpty) {
            s.uyarilar.add('Benzer kayıt var: ${adaylar.first.kisi.ad} (%${(adaylar.first.benzerlik * 100).round()}).');
          }
        }
      }
      satirlar.add(s);
    }
    return AktarimOnizlemesi(basliklar: basliklar, esleme: e, satirlar: satirlar);
  }
}
