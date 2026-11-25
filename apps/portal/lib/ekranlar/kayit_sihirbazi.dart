import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/kimlik_servisi.dart';

/// 4 adımlı kayıt: hesap türü → hesap bilgileri → fatura bilgileri → onaylar.
///
/// Kayıt 14 günlük denemeyi başlatır; ödeme deneme sonunda web'den alınır.
class KayitSihirbazi extends StatefulWidget {
  const KayitSihirbazi({super.key, required this.servis});

  final KimlikServisi servis;

  @override
  State<KayitSihirbazi> createState() => _KayitSihirbaziState();
}

class _KayitSihirbaziState extends State<KayitSihirbazi> {
  static const _adimAdlari = ['Hesap türü', 'Hesap bilgileri', 'Fatura bilgileri', 'Onaylar'];

  int _adim = 0;
  HesapTuru? _tur;
  bool _bekliyor = false;
  bool _tamamlandi = false;
  String? _hata;

  final _bilgiFormu = GlobalKey<FormState>();
  final _faturaFormu = GlobalKey<FormState>();

  final _adSoyad = TextEditingController();
  final _kurumAdi = TextEditingController();
  final _eposta = TextEditingController();
  final _telefon = TextEditingController();
  final _sifre = TextEditingController();
  final _sifreTekrar = TextEditingController();
  final _faturaUnvani = TextEditingController();
  final _tcknVkn = TextEditingController();
  final _vergiDairesi = TextEditingController();
  final _adres = TextEditingController();

  bool _sozlesmeOnayi = false;
  bool _kvkkOnayi = false;
  bool _ticariIleti = false;

  @override
  void dispose() {
    for (final c in [
      _adSoyad,
      _kurumAdi,
      _eposta,
      _telefon,
      _sifre,
      _sifreTekrar,
      _faturaUnvani,
      _tcknVkn,
      _vergiDairesi,
      _adres,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _adimGecerli() {
    switch (_adim) {
      case 0:
        if (_tur == null) {
          setState(() => _hata = 'Lütfen hesap türünü seçin.');
          return false;
        }
        return true;
      case 1:
        return _bilgiFormu.currentState!.validate();
      case 2:
        return _faturaFormu.currentState!.validate();
      default:
        if (!_sozlesmeOnayi || !_kvkkOnayi) {
          setState(() => _hata = 'Devam etmek için zorunlu onayları verin.');
          return false;
        }
        return true;
    }
  }

  Future<void> _ileri() async {
    setState(() => _hata = null);
    if (!_adimGecerli()) return;
    if (_adim == 1 && _faturaUnvani.text.isEmpty) {
      _faturaUnvani.text = _kurumAdi.text;
    }
    if (_adim < _adimAdlari.length - 1) {
      setState(() => _adim++);
      return;
    }
    setState(() => _bekliyor = true);
    try {
      await widget.servis.kayitOl(KayitBilgileri(
        hesapTuru: _tur!,
        adSoyad: _adSoyad.text,
        kurumAdi: _kurumAdi.text,
        eposta: _eposta.text,
        telefon: _telefon.text,
        sifre: _sifre.text,
        faturaUnvani: _faturaUnvani.text,
        tcknVeyaVkn: _tcknVkn.text.trim(),
        vergiDairesi: _vergiDairesi.text,
        faturaAdresi: _adres.text,
        ticariIletiIzni: _ticariIleti,
        onayZamani: DateTime.now().toUtc(),
      ));
      if (!mounted) return;
      setState(() => _tamamlandi = true);
    } on KimlikHatasi catch (e) {
      if (!mounted) return;
      setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _bekliyor = false);
    }
  }

  void _geri() {
    if (_adim == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _hata = null;
        _adim--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tamamlandi) return _TamamEkrani(eposta: _eposta.text);

    final son = _adim == _adimAdlari.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text('Hesap oluştur · ${_adim + 1}/${_adimAdlari.length} ${_adimAdlari[_adim]}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              LinearProgressIndicator(value: (_adim + 1) / _adimAdlari.length),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: switch (_adim) {
                    0 => _hesapTuruAdimi(),
                    1 => _bilgiAdimi(),
                    2 => _faturaAdimi(),
                    _ => _onayAdimi(),
                  },
                ),
              ),
              if (_hata != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _hata!,
                    key: const Key('kayit-hata'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    TextButton(onPressed: _bekliyor ? null : _geri, child: Text(_adim == 0 ? 'Vazgeç' : 'Geri')),
                    const Spacer(),
                    FilledButton(
                      key: const Key('kayit-ileri'),
                      onPressed: _bekliyor ? null : _ileri,
                      child: Text(son ? 'Denemeyi başlat' : 'İleri'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hesapTuruAdimi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Kim olarak kullanacaksınız?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Seçiminiz açılacak modülleri, hazır rolleri ve fiyatı belirler. Daha sonra yükseltebilirsiniz.'),
        const SizedBox(height: 16),
        for (final tur in HesapTuru.values)
          Card(
            key: Key('tur-${tur.name}'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _tur == tur ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                width: _tur == tur ? 2 : 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(switch (tur) {
                HesapTuru.avukatlikBurosu => Icons.person_outline,
                HesapTuru.hukukBurosu => Icons.groups_outlined,
                HesapTuru.kurumsal => Icons.apartment_outlined,
              }),
              title: Text(tur.ad),
              subtitle: Text('${tur.aciklama} · ${LisansProfili.varsayilan(tur).moduller.length} modül'),
              trailing: Icon(_tur == tur ? Icons.check_circle : Icons.circle_outlined),
              selected: _tur == tur,
              onTap: () => setState(() {
                _tur = tur;
                _hata = null;
              }),
            ),
          ),
      ],
    );
  }

  Widget _bilgiAdimi() {
    final kurumEtiketi = _tur == HesapTuru.kurumsal ? 'Şirket adı' : 'Büro adı';
    return Form(
      key: _bilgiFormu,
      child: Column(
        children: [
          _alan('kayit-ad', _adSoyad, 'Ad soyad', (d) => Dogrulayicilar.zorunlu(d, alan: 'Ad soyad')),
          _alan('kayit-kurum', _kurumAdi, kurumEtiketi, (d) => Dogrulayicilar.zorunlu(d, alan: kurumEtiketi)),
          _alan('kayit-eposta', _eposta, 'E-posta (kullanıcı adınız)', Dogrulayicilar.eposta,
              klavye: TextInputType.emailAddress),
          _alan('kayit-telefon', _telefon, 'Cep telefonu', Dogrulayicilar.cepTelefonu, klavye: TextInputType.phone),
          _alan('kayit-sifre', _sifre, 'Şifre (en az 10 karakter, harf ve rakam)',
              (d) => Dogrulayicilar.sifre(d, eposta: _eposta.text),
              gizli: true),
          _alan('kayit-sifre-tekrar', _sifreTekrar, 'Şifre tekrar',
              (d) => d != _sifre.text ? 'Şifreler eşleşmiyor.' : null,
              gizli: true),
        ],
      ),
    );
  }

  Widget _faturaAdimi() {
    return Form(
      key: _faturaFormu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Deneme süresince ücret alınmaz. Bu bilgiler fatura (e-Arşiv) için kullanılır.'),
          const SizedBox(height: 16),
          _alan('kayit-unvan', _faturaUnvani, 'Fatura unvanı / ad soyad',
              (d) => Dogrulayicilar.zorunlu(d, alan: 'Fatura unvanı')),
          _alan('kayit-tckn-vkn', _tcknVkn, 'TC kimlik no (şahıs) veya vergi no (şirket)', Dogrulayicilar.tcknVeyaVkn,
              klavye: TextInputType.number),
          _alan('kayit-vergi-dairesi', _vergiDairesi, 'Vergi dairesi',
              (d) => Dogrulayicilar.zorunlu(d, alan: 'Vergi dairesi')),
          _alan('kayit-adres', _adres, 'Fatura adresi', (d) => Dogrulayicilar.zorunlu(d, alan: 'Fatura adresi'),
              satir: 3),
        ],
      ),
    );
  }

  Widget _onayAdimi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${_tur?.ad ?? ''} · 14 gün ücretsiz deneme'),
            subtitle: Text('${_kurumAdi.text} · ${_eposta.text}'),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('onay-sozlesme'),
          value: _sozlesmeOnayi,
          onChanged: (v) => setState(() => _sozlesmeOnayi = v ?? false),
          title: const Text('Kullanım koşullarını ve abonelik sözleşmesini okudum, kabul ediyorum. (zorunlu)'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          key: const Key('onay-kvkk'),
          value: _kvkkOnayi,
          onChanged: (v) => setState(() => _kvkkOnayi = v ?? false),
          title: const Text('KVKK aydınlatma metnini ve veri işleme sözleşmesini okudum. (zorunlu)'),
          subtitle: const Text('Tüm verileriniz yalnızca Türkiye\'deki sunucularda tutulur.'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: _ticariIleti,
          onChanged: (v) => setState(() => _ticariIleti = v ?? false),
          title: const Text('Ürün duyuruları ve kampanyalar için ticari ileti almak istiyorum. (isteğe bağlı)'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _alan(
    String anahtar,
    TextEditingController denetleyici,
    String etiket,
    FormFieldValidator<String> dogrula, {
    TextInputType? klavye,
    bool gizli = false,
    int satir = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: Key(anahtar),
        controller: denetleyici,
        decoration: InputDecoration(labelText: etiket),
        keyboardType: klavye,
        obscureText: gizli,
        maxLines: gizli ? 1 : satir,
        validator: dogrula,
      ),
    );
  }
}

class _TamamEkrani extends StatelessWidget {
  const _TamamEkrani({required this.eposta});

  final String eposta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_read_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Hesabınız oluşturuldu', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '$eposta adresine bir aktivasyon bağlantısı gönderdik. '
                'Bağlantıya tıkladıktan sonra giriş yapabilirsiniz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('girise-don'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Giriş ekranına dön'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
