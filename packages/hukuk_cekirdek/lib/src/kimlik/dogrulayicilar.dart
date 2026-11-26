/// Kayıt, fatura ve kişi kartı formlarında kullanılan doğrulama kuralları.
///
/// Her fonksiyon hata yoksa `null`, varsa kullanıcıya gösterilecek Türkçe mesajı döner.
/// Böylece Flutter `TextFormField.validator` ile doğrudan kullanılabilir.
class Dogrulayicilar {
  Dogrulayicilar._();

  static final _epostaDeseni = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? zorunlu(String? deger, {String alan = 'Bu alan'}) {
    if (deger == null || deger.trim().isEmpty) return '$alan zorunludur.';
    return null;
  }

  static String? eposta(String? deger) {
    final bos = zorunlu(deger, alan: 'E-posta');
    if (bos != null) return bos;
    if (!_epostaDeseni.hasMatch(deger!.trim())) return 'Geçerli bir e-posta adresi girin.';
    return null;
  }

  /// En az 10 karakter, en az bir harf ve bir rakam; e-postanın kullanıcı adını içeremez.
  static String? sifre(String? deger, {String? eposta}) {
    if (deger == null || deger.isEmpty) return 'Şifre zorunludur.';
    if (deger.length < 10) return 'Şifre en az 10 karakter olmalıdır.';
    if (deger.length > 256) return 'Şifre en fazla 256 karakter olabilir.';
    if (!RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(deger)) return 'Şifre en az bir harf içermelidir.';
    if (!RegExp(r'[0-9]').hasMatch(deger)) return 'Şifre en az bir rakam içermelidir.';
    if (eposta != null && eposta.contains('@')) {
      final kullaniciAdi = eposta.split('@').first.toLowerCase();
      if (kullaniciAdi.length >= 3 && deger.toLowerCase().contains(kullaniciAdi)) {
        return 'Şifre e-posta adresinizi içermemelidir.';
      }
    }
    return null;
  }

  /// Türkiye cep telefonu: 05XXXXXXXXX, 5XXXXXXXXX veya +905XXXXXXXXX.
  static String? cepTelefonu(String? deger) {
    final bos = zorunlu(deger, alan: 'Telefon');
    if (bos != null) return bos;
    final rakamlar = deger!.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^(\+90|0)?5\d{9}$').hasMatch(rakamlar)) {
      return 'Geçerli bir cep telefonu girin (5XX XXX XX XX).';
    }
    return null;
  }

  /// T.C. kimlik numarası kontrol algoritması.
  static bool tcknGecerli(String deger) {
    if (!RegExp(r'^[1-9]\d{10}$').hasMatch(deger)) return false;
    final d = deger.split('').map(int.parse).toList();
    final tek = d[0] + d[2] + d[4] + d[6] + d[8];
    final cift = d[1] + d[3] + d[5] + d[7];
    final onuncu = (tek * 7 - cift) % 10;
    if (onuncu != d[9]) return false;
    final toplam = d.sublist(0, 10).fold<int>(0, (a, b) => a + b);
    return toplam % 10 == d[10];
  }

  /// Vergi kimlik numarası (10 hane) kontrol algoritması.
  static bool vknGecerli(String deger) {
    if (!RegExp(r'^\d{10}$').hasMatch(deger)) return false;
    var toplam = 0;
    for (var i = 0; i < 9; i++) {
      final basamak = int.parse(deger[i]);
      final tmp = (basamak + (9 - i)) % 10;
      var v = (tmp * (1 << (9 - i))) % 9;
      if (tmp != 0 && v == 0) v = 9;
      toplam += v;
    }
    final kontrol = (10 - toplam % 10) % 10;
    return kontrol == int.parse(deger[9]);
  }

  /// Fatura için TCKN (11 hane, şahıs) veya VKN (10 hane, şirket).
  static String? tcknVeyaVkn(String? deger) {
    final bos = zorunlu(deger, alan: 'TC kimlik / vergi numarası');
    if (bos != null) return bos;
    final temiz = deger!.trim();
    if (temiz.length == 11) return tcknGecerli(temiz) ? null : 'TC kimlik numarası geçersiz.';
    if (temiz.length == 10) return vknGecerli(temiz) ? null : 'Vergi kimlik numarası geçersiz.';
    return 'TC kimlik numarası 11, vergi numarası 10 haneli olmalıdır.';
  }
}
