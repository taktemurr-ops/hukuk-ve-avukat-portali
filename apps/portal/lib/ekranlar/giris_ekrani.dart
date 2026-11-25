import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/sunucu_kimlik_servisi.dart';
import '../tema/tema.dart';
import 'kayit_sihirbazi.dart';

/// Kullanıcı adı (e-posta) ve şifre ile giriş.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({
    super.key,
    required this.servis,
    required this.girisYapildi,
    this.davetBaglantisi,
    this.sifirlamaBaglantisi,
    this.dogrulamaBaglantisi,
  });

  final KimlikServisi servis;
  final ValueChanged<Oturum> girisYapildi;

  /// Davet e-postasındaki bağlantıyla açıldıysa (…/davet?kod=…&eposta=…) davet sayfası doğrudan açılır.
  final Uri? davetBaglantisi;

  /// Şifre sıfırlama e-postasındaki bağlantı (…/sifre-sifirla?kod=…).
  final Uri? sifirlamaBaglantisi;

  /// Kayıt e-postasındaki doğrulama bağlantısı (…/eposta-dogrula?kod=…).
  final Uri? dogrulamaBaglantisi;

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _form = GlobalKey<FormState>();
  final _eposta = TextEditingController();
  final _sifre = TextEditingController();
  bool _sifreGizli = true;
  bool _bekliyor = false;
  bool _dogrulamaBekliyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    final b = widget.davetBaglantisi;
    final kod = b?.queryParameters['kod'];
    if (b != null && kod != null && kod.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => DavetKabulEkrani(servis: widget.servis, kod: kod, eposta: b.queryParameters['eposta'])));
      });
    }
    final dk = widget.dogrulamaBaglantisi?.queryParameters['kod'];
    if (dk != null && dk.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dogrula(dk));
    }
    final sk = widget.sifirlamaBaglantisi?.queryParameters['kod'];
    if (sk != null && sk.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => SifreSifirlaEkrani(servis: widget.servis, kod: sk)));
      });
    }
  }

  @override
  void dispose() {
    _eposta.dispose();
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _girisYap() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _bekliyor = true;
      _hata = null;
    });
    try {
      await _dene();
    } finally {
      if (mounted) setState(() => _bekliyor = false);
    }
  }

  /// Girişi dener; kurum seçimi ve iki adımlı kod istenirse kullanıcıya sorup yeniden dener.
  Future<void> _dene({String? kiraciId, String? kod}) async {
    try {
      final oturum =
          await widget.servis.girisYap(eposta: _eposta.text, sifre: _sifre.text, kiraciId: kiraciId, ikiAdimliKod: kod);
      if (mounted) widget.girisYapildi(oturum);
    } on IkiAdimliGerekli {
      if (!mounted) return;
      final girilen = await MetinGirisDiyalogu.goster(
        context,
        const MetinGirisDiyalogu(
          baslik: 'İki adımlı doğrulama',
          etiket: 'Doğrulayıcı uygulamadaki 6 haneli kod',
          onayMetni: 'Doğrula',
          alanAnahtari: Key('giris-iki-adimli-kod'),
          onayAnahtari: Key('giris-iki-adimli-onay'),
        ),
      );
      if (girilen == null || girilen.trim().isEmpty || !mounted) return;
      await _dene(kiraciId: kiraciId, kod: girilen.trim());
    } on KurumSecimiGerekli catch (e) {
      if (!mounted) return;
      final kiraci = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Hangi kurumla giriş yapılsın?'),
          children: [
            for (final k in e.kurumlar.entries)
              SimpleDialogOption(
                key: Key('kurum-${k.key}'),
                onPressed: () => Navigator.pop(c, k.key),
                child: Text(k.value),
              ),
          ],
        ),
      );
      if (kiraci == null || !mounted) return;
      await _dene(kiraciId: kiraci, kod: kod);
    } on EpostaDogrulanmadi catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.mesaj;
          _dogrulamaBekliyor = true;
        });
      }
    } on KimlikHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    }
  }

  /// Bağlantıyla açıldıysa adresi doğrular ve sonucu gösterir.
  Future<void> _dogrula(String kod) async {
    String mesaj;
    try {
      await widget.servis.epostaDogrula(kod);
      mesaj = 'E-posta adresiniz doğrulandı. Şimdi giriş yapabilirsiniz.';
    } on KimlikHatasi catch (e) {
      mesaj = e.mesaj;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj, key: const Key('dogrulama-sonuc'))));
  }

  Future<void> _dogrulamaYeniden() async {
    try {
      await widget.servis.dogrulamaYeniden(_eposta.text);
    } on KimlikHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doğrulanmamış bir hesap varsa yeni bağlantı gönderildi (48 saat geçerli).')));
  }

  Future<void> _sifremiUnuttum() async {
    final adres = await MetinGirisDiyalogu.goster(
      context,
      MetinGirisDiyalogu(
        baslik: 'Şifre sıfırlama',
        etiket: 'E-posta',
        ilkDeger: _eposta.text,
        onayMetni: 'Gönder',
        klavye: TextInputType.emailAddress,
      ),
    );
    if (adres == null) return;
    try {
      await widget.servis.sifreSifirlamaIste(adres);
    } on KimlikHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bu adres kayıtlıysa sıfırlama bağlantısı gönderildi (1 saat geçerli).'),
        action: SnackBarAction(
          label: 'Kodum var',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => SifreSifirlaEkrani(servis: widget.servis))),
        ),
      ),
    );
  }

  Future<void> _demo() async {
    final secim = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Demo hesabı', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Örnek verilerle deneyin. Girdiğiniz bilgiler kaydedilmez.'),
            ),
            for (final t in HesapTuru.values)
              ListTile(
                key: Key('demo-${t.name}'),
                leading: const Icon(Icons.play_circle_outline),
                title: Text(t.ad),
                subtitle: Text(t.aciklama),
                onTap: () => Navigator.pop(context, t.name),
              ),
            ListTile(
              key: const Key('demo-muvekkil'),
              leading: const Icon(Icons.person_outline),
              title: const Text('Müvekkil portalı'),
              subtitle: const Text('Büronuzun müvekkillerine sunduğu ekranı müvekkil gözüyle görün'),
              onTap: () => Navigator.pop(context, 'muvekkil'),
            ),
          ],
        ),
      ),
    );
    if (secim == null) return;
    final oturum = secim == 'muvekkil'
        ? await widget.servis.demoMuvekkilGiris()
        : await widget.servis.demoGiris(HesapTuru.values.byName(secim));
    if (!mounted) return;
    widget.girisYapildi(oturum);
  }

  void _davetKabul() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DavetKabulEkrani(servis: widget.servis)),
    );
  }

  void _kayitOl() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => KayitSihirbazi(servis: widget.servis)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    final genis = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: Row(
        children: [
          if (genis) const Expanded(flex: 5, child: _TanitimPaneli()),
          Expanded(flex: 4, child: _form0(metin)),
        ],
      ),
    );
  }

  Widget _form0(TextTheme metin) {
    return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Logo(acikZemin: true)),
                  const SizedBox(height: 32),
                  Text('Giriş yap', style: metin.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Hesabınıza e-posta ve şifrenizle girin.', style: metin.bodyMedium),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('giris-eposta'),
                    controller: _eposta,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: Dogrulayicilar.eposta,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('giris-sifre'),
                    controller: _sifre,
                    obscureText: _sifreGizli,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _sifreGizli ? 'Şifreyi göster' : 'Şifreyi gizle',
                        icon: Icon(_sifreGizli ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _sifreGizli = !_sifreGizli),
                      ),
                    ),
                    validator: (d) => Dogrulayicilar.zorunlu(d, alan: 'Şifre'),
                    onFieldSubmitted: (_) => _girisYap(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _sifremiUnuttum, child: const Text('Şifremi unuttum')),
                  ),
                  if (_hata != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _hata!,
                        key: const Key('giris-hata'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (_dogrulamaBekliyor)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('dogrulama-yeniden'),
                        onPressed: _dogrulamaYeniden,
                        child: const Text('Doğrulama bağlantısını yeniden gönder'),
                      ),
                    ),
                  FilledButton(
                    key: const Key('giris-yap'),
                    onPressed: _bekliyor ? null : _girisYap,
                    child: _bekliyor
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Giriş yap'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Hesabınız yok mu? 14 gün ücretsiz deneyin.', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('kayit-ol'),
                    onPressed: _kayitOl,
                    child: const Text('Hesap oluştur'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('davet-kabul'),
                    onPressed: _davetKabul,
                    child: const Text('Davet kodum var'),
                  ),
                  TextButton.icon(
                    key: const Key('demo-giris'),
                    onPressed: _demo,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Kayıt olmadan demo hesabıyla dene'),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

/// Geniş ekranda giriş formunun solunda duran lacivert tanıtım paneli.
class _TanitimPaneli extends StatelessWidget {
  const _TanitimPaneli();

  @override
  Widget build(BuildContext context) {
    const acik = TextStyle(color: Color(0xFFE3E8EF), fontSize: 16, height: 1.5);
    return Container(
      color: Renkler.lacivert,
      padding: const EdgeInsets.all(56),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Logo(),
          Spacer(),
          Text(
            'Hiçbir süreyi kaçırmayın.\nHer işi kayıt altında, kanıtla kapatın.',
            style: TextStyle(fontFamily: 'SourceSerif4', fontWeight: FontWeight.w700, fontSize: 34, color: Colors.white, height: 1.2),
          ),
          SizedBox(height: 24),
          Text('• Kritik süreler için asıl ve yedek sorumlu, teyit ve eskalasyon', style: acik),
          Text('• Tebligattan süreye, süreden göreve otomatik akış', style: acik),
          Text('• Çıkar çatışması ve vekâlet kontrolü işlemden önce', style: acik),
          Text('• Tüm veriler yalnızca Türkiye\'deki sunucularda', style: acik),
          Spacer(),
          Text('Avukatlık büroları, hukuk büroları ve şirket hukuk birimleri için', style: TextStyle(color: Renkler.altin)),
        ],
      ),
    );
  }
}

/// Davet bağlantısıyla gelen kişi: kod, e-posta, ad ve şifre belirleyerek hesabını açar.
class DavetKabulEkrani extends StatefulWidget {
  const DavetKabulEkrani({super.key, required this.servis, this.kod, this.eposta});

  final KimlikServisi servis;

  /// Bağlantıdan gelen kod ve e-posta (varsa alanlar dolu gelir).
  final String? kod;
  final String? eposta;

  @override
  State<DavetKabulEkrani> createState() => _DavetKabulEkraniState();
}

class _DavetKabulEkraniState extends State<DavetKabulEkrani> {
  late final _kod = TextEditingController(text: widget.kod ?? '');
  late final _eposta = TextEditingController(text: widget.eposta ?? '');
  final _ad = TextEditingController();
  final _sifre = TextEditingController();
  final _sifre2 = TextEditingController();
  String? _hata;
  bool _gonderiliyor = false;
  bool _tamam = false;

  @override
  void dispose() {
    for (final c in [_kod, _eposta, _ad, _sifre, _sifre2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gonder() async {
    final eposta = _eposta.text.trim();
    final hata = _kod.text.trim().isEmpty
        ? 'Davet kodunu girin.'
        : Dogrulayicilar.eposta(eposta) ??
            (_ad.text.trim().length < 3 ? 'Adınızı ve soyadınızı yazın.' : null) ??
            Dogrulayicilar.sifre(_sifre.text, eposta: eposta) ??
            (_sifre.text != _sifre2.text ? 'Şifreler aynı değil.' : null);
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    setState(() {
      _hata = null;
      _gonderiliyor = true;
    });
    try {
      await widget.servis.davetKabul(kod: _kod.text, eposta: eposta, adSoyad: _ad.text, sifre: _sifre.text);
      if (mounted) setState(() => _tamam = true);
    } on KimlikHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daveti kabul et')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
            if (_tamam) ...[
              const Text('Hesabınız açıldı. Şimdi e-posta adresiniz ve belirlediğiniz şifreyle giriş yapabilirsiniz.',
                  key: Key('davet-tamam')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Girişe dön')),
            ] else ...[
              TextField(key: const Key('davet-kod'), controller: _kod, decoration: const InputDecoration(labelText: 'Davet kodu')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('davet-kabul-eposta'),
                  controller: _eposta,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Davet edilen e-posta')),
              const SizedBox(height: 12),
              TextField(key: const Key('davet-ad'), controller: _ad, decoration: const InputDecoration(labelText: 'Ad soyad')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('davet-sifre'),
                  controller: _sifre,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Şifre', helperText: 'En az 10 karakter; harf ve rakam içermeli')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('davet-sifre2'),
                  controller: _sifre2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Şifre (tekrar)')),
              if (_hata != null) ...[
                const SizedBox(height: 12),
                Text(_hata!, key: const Key('davet-kabul-hata'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('davet-kabul-gonder'),
                onPressed: _gonderiliyor ? null : _gonder,
                child: const Text('Hesabımı aç'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// E-postadaki bağlantı ya da kodla yeni şifre belirleme. Başarıda tüm oturumlar kapanır.
class SifreSifirlaEkrani extends StatefulWidget {
  const SifreSifirlaEkrani({super.key, required this.servis, this.kod});

  final KimlikServisi servis;
  final String? kod;

  @override
  State<SifreSifirlaEkrani> createState() => _SifreSifirlaEkraniState();
}

class _SifreSifirlaEkraniState extends State<SifreSifirlaEkrani> {
  late final _kod = TextEditingController(text: widget.kod ?? '');
  final _sifre = TextEditingController();
  final _sifre2 = TextEditingController();
  String? _hata;
  bool _gonderiliyor = false;
  bool _tamam = false;

  @override
  void dispose() {
    for (final c in [_kod, _sifre, _sifre2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gonder() async {
    final hata = _kod.text.trim().isEmpty
        ? 'E-postadaki kodu girin.'
        : Dogrulayicilar.sifre(_sifre.text) ?? (_sifre.text != _sifre2.text ? 'Şifreler aynı değil.' : null);
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    setState(() {
      _hata = null;
      _gonderiliyor = true;
    });
    try {
      await widget.servis.sifreSifirla(kod: _kod.text, yeniSifre: _sifre.text);
      if (mounted) setState(() => _tamam = true);
    } on KimlikHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _gonderiliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni şifre belirle')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
            if (_tamam) ...[
              const Text('Şifreniz değişti ve tüm cihazlardaki oturumlarınız kapatıldı. Yeni şifrenizle giriş yapabilirsiniz.',
                  key: Key('sifirla-tamam')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Girişe dön')),
            ] else ...[
              if (widget.kod == null) ...[
                TextField(
                    key: const Key('sifirla-kod'),
                    controller: _kod,
                    decoration: const InputDecoration(labelText: 'E-postadaki kod')),
                const SizedBox(height: 12),
              ],
              TextField(
                  key: const Key('sifirla-sifre'),
                  controller: _sifre,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Yeni şifre', helperText: 'En az 10 karakter; harf ve rakam içermeli')),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('sifirla-sifre2'),
                  controller: _sifre2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Yeni şifre (tekrar)')),
              if (_hata != null) ...[
                const SizedBox(height: 12),
                Text(_hata!, key: const Key('sifirla-hata'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('sifirla-gonder'),
                onPressed: _gonderiliyor ? null : _gonder,
                child: const Text('Şifremi değiştir'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
