import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../tema/tema.dart';
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
    await widget.servis.sifreSifirlamaIste(adres);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu adres kayıtlıysa sıfırlama bağlantısı gönderildi.')),
    );
  }

  Future<void> _demo() async {
    final tur = await showModalBottomSheet<HesapTuru>(
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
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (tur == null) return;
    final oturum = await widget.servis.demoGiris(tur);
    if (!mounted) return;
    widget.girisYapildi(oturum);
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
