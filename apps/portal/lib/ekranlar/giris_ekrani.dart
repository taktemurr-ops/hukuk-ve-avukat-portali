import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/kimlik_servisi.dart';
import 'kayit_sihirbazi.dart';

/// Kullanıcı adı (e-posta) ve şifre ile giriş.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key, required this.servis, required this.girisYapildi});

  final KimlikServisi servis;
  final ValueChanged<Oturum> girisYapildi;

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _form = GlobalKey<FormState>();
  final _eposta = TextEditingController();
  final _sifre = TextEditingController();
  bool _sifreGizli = true;
  bool _bekliyor = false;
  String? _hata;

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
      final oturum = await widget.servis.girisYap(eposta: _eposta.text, sifre: _sifre.text);
      if (!mounted) return;
      widget.girisYapildi(oturum);
    } on KimlikHatasi catch (e) {
      if (!mounted) return;
      setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _bekliyor = false);
    }
  }

  Future<void> _sifremiUnuttum() async {
    final eposta = TextEditingController(text: _eposta.text);
    final gonder = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şifre sıfırlama'),
        content: TextField(
          controller: eposta,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-posta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gönder')),
        ],
      ),
    );
    final adres = eposta.text;
    eposta.dispose();
    if (gonder != true) return;
    await widget.servis.sifreSifirlamaIste(adres);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu adres kayıtlıysa sıfırlama bağlantısı gönderildi.')),
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.balance, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Hukuk ve Avukat Portalı', textAlign: TextAlign.center, style: metin.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Hesabınıza giriş yapın', textAlign: TextAlign.center, style: metin.bodyMedium),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
