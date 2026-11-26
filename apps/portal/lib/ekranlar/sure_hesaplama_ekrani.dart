import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

/// Kural bazlı süre hesaplama aracı.
///
/// Kurallar avukat onayı beklediğinden ekran taslak modda çalışır ve
/// bunu kullanıcıya açıkça gösterir.
class SureHesaplamaEkrani extends StatefulWidget {
  const SureHesaplamaEkrani({super.key});

  @override
  State<SureHesaplamaEkrani> createState() => _SureHesaplamaEkraniState();
}

class _SureHesaplamaEkraniState extends State<SureHesaplamaEkrani> {
  final _hesaplayici = SureHesaplayici(
    TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar),
    ayarlar: const HesapAyarlari(taslakKuralaIzinVer: true),
  );

  SureKurali _kural = KuralKatalogu.tohumKurallar.first;
  Tarih _tarih = Tarih.from(DateTime.now());
  bool _elektronikTebligat = false;
  SureSonucu? _sonuc;
  String? _hata;

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: DateTime(_tarih.yil, _tarih.ay, _tarih.gun),
      firstDate: DateTime(2010),
      lastDate: DateTime(2035),
      helpText: _elektronikTebligat ? 'Elektronik adrese ulaşma tarihi' : 'Tebliğ tarihi',
    );
    if (secilen != null) {
      setState(() {
        _tarih = Tarih.from(secilen);
        _sonuc = null;
      });
    }
  }

  void _hesapla() {
    setState(() {
      _hata = null;
      try {
        final baslangic = _elektronikTebligat ? ElektronikTebligat.tebligTarihi(_tarih) : _tarih;
        _sonuc = _hesaplayici.hesapla(kural: _kural, baslangic: baslangic);
      } on StateError catch (e) {
        _sonuc = null;
        _hata = e.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    final sonuc = _sonuc;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: renkler.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: renkler.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Deneme sürümü: süre kuralları ve tatil verisi avukat onayı bekliyor. '
                    'Sonuçları gerçek dosyalarda kullanmayın.',
                    style: TextStyle(color: renkler.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownMenu<SureKurali>(
          key: const Key('kural-secimi'),
          label: const Text('Süre kuralı'),
          expandedInsets: EdgeInsets.zero,
          initialSelection: _kural,
          onSelected: (k) {
            if (k != null) {
              setState(() {
                _kural = k;
                _sonuc = null;
              });
            }
          },
          dropdownMenuEntries: [
            for (final k in KuralKatalogu.tohumKurallar)
              DropdownMenuEntry(value: k, label: '${k.ad} (${k.sureMetni}, ${k.dayanak})'),
          ],
        ),
        if (_kural.aciklama != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_kural.aciklama!, style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Elektronik tebligat'),
          subtitle: const Text('Ulaşma tarihini girin; tebliğ, izleyen 5. günün sonunda sayılır.'),
          value: _elektronikTebligat,
          onChanged: (v) => setState(() {
            _elektronikTebligat = v;
            _sonuc = null;
          }),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month),
          title: Text(_elektronikTebligat ? 'Ulaşma tarihi' : 'Tebliğ tarihi'),
          subtitle: Text('${_tarih.turkceBicim} ${_tarih.gunAdi}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: _tarihSec,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('hesapla'),
          onPressed: _hesapla,
          icon: const Icon(Icons.calculate),
          label: const Text('Süreyi hesapla'),
        ),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_hata!, style: TextStyle(color: renkler.error)),
          ),
        if (sonuc != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Son gün', style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    '${sonuc.sonGun.turkceBicim} ${sonuc.sonGun.gunAdi}',
                    key: const Key('son-gun'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('Bu sonuç bir hukukçu tarafından teyit edilmelidir.'),
                  const Divider(height: 24),
                  Text('Hesap adımları', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final adim in sonuc.adimlar)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${adim.tarih.turkceBicim}: ${adim.aciklama}'),
                    ),
                  if (sonuc.uyarilar.isNotEmpty) ...[
                    const Divider(height: 24),
                    for (final uyari in sonuc.uyarilar)
                      Text('⚠ $uyari', style: TextStyle(color: renkler.error)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
