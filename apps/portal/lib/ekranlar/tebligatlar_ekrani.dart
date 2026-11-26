import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/api_istemcisi.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';

/// Gelen tebligatlar ve eşleşmeyen evrak kuyruğu.
class TebligatlarEkrani extends StatelessWidget {
  const TebligatlarEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  Future<void> _sureOlusturSor(BuildContext context, Tebligat t) async {
    final dosyaId = t.dosyaId;
    if (dosyaId == null) return;
    final kural = await showDialog<SureKurali>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Bu tebligattan süre başlat'),
        children: [
          for (final k in KuralKatalogu.tohumKurallar)
            SimpleDialogOption(
              key: Key('kural-${k.kod}'),
              onPressed: () => Navigator.pop(context, k),
              child: Text('${k.ad} (${k.sureMetni}, ${k.dayanak})'),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('Şimdi değil')),
        ],
      ),
    );
    if (kural == null || !context.mounted) return;
    final uzak = depo.uzak;
    if (uzak != null) {
      try {
        final sonGun = await uzak.sureHesapla(dosyaId: dosyaId, kuralKodu: kural.kod, tarih: t.tebligTarihi);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Süre sunucuda hesaplandı: son gün ${sonGun.turkceBicim}. Teyit bekleniyor.')));
        }
      } on Exception catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    final sure = depo.sureOlustur(
      dosyaId: dosyaId,
      kural: kural,
      baslangic: t.tebligTarihi,
      olusturan: oturum.kullaniciId,
      tebligatId: t.id,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Süre oluşturuldu: son gün ${sure.sonGun.turkceBicim}. '
          'Başka bir hukukçunun teyidi bekleniyor.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('yeni-tebligat'),
        icon: const Icon(Icons.add),
        label: const Text('Tebligat kaydet'),
        onPressed: () async {
          final t = await Navigator.of(context).push<Tebligat>(
            MaterialPageRoute(builder: (_) => TebligatFormu(depo: depo)),
          );
          if (t == null || !context.mounted) return;
          final uzak = depo.uzak;
          final ({Tebligat tebligat, bool mukerrer}) sonuc;
          if (uzak != null) {
            // Eşleştirme önerisi yerelde (görünür dosyalar ve taraflarla) yapılır; kesin eşleşme varsa dosyayla gönderilir.
            final otomatik = TebligatEslestirici.otomatikEslesme(
                TebligatEslestirici.oner(t, depo.tumDosyalar, dosyaTaraflari: depo.dosyaTaraflari));
            try {
              final kayit = await uzak.tebligatEkle(otomatik == null ? t : t.dosyayaBagla(otomatik.id));
              sonuc = (tebligat: kayit, mukerrer: false);
            } on SunucuHatasi catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(e.kod == 'mukerrer' ? 'Bu evrak daha önce kaydedilmiş; yeni kayıt açılmadı.' : e.mesaj)));
              return;
            }
            if (!context.mounted) return;
          } else {
            sonuc = depo.tebligatEkle(t);
          }
          final kayit = sonuc.tebligat;
          final mesaj = sonuc.mukerrer
              ? 'Bu evrak daha önce kaydedilmiş; yeni kayıt açılmadı.'
              : kayit.dosyaId != null
                  ? 'Tebligat "${depo.dosya(kayit.dosyaId!)?.baslik}" dosyasıyla eşleşti.'
                  : 'Dosya bulunamadı; tebligat eşleşmeyen kuyruğuna düştü.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
          if (!sonuc.mukerrer && kayit.dosyaId != null) await _sureOlusturSor(context, kayit);
        },
      ),
      body: ListenableBuilder(
        listenable: depo,
        builder: (context, _) {
          final metin = Theme.of(context).textTheme;
          final kuyruk = depo.eslesmeyenTebligatlar;
          final eslesen = depo.tebligatlar.where((t) => t.dosyaId != null).toList().reversed;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Eşleşmeyen evrak (${kuyruk.length})', style: metin.titleMedium),
              const Text('Dosyası kesin belirlenemeyen evrak burada bekler; bir ekip üyesi doğru dosyaya bağlar.'),
              if (kuyruk.isEmpty) const ListTile(title: Text('Kuyruk boş.')),
              for (final t in kuyruk) _kuyrukKarti(context, t),
              const Divider(height: 32),
              Text('Dosyaya bağlı tebligatlar', style: metin.titleMedium),
              for (final t in eslesen)
                ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: Text('${t.konu} · ${t.gonderen}'),
                  subtitle: Text(
                    '${depo.dosya(t.dosyaId!)?.baslik ?? ''} · ${t.kanal.ad} · '
                    'ulaşma ${t.ulasmaTarihi.turkceBicim} · tebliğ ${t.tebligTarihi.turkceBicim}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _kuyrukKarti(BuildContext context, Tebligat t) {
    final oneriler = depo.tebligatOnerileri(t);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.konu} · ${t.gonderen}', style: Theme.of(context).textTheme.titleSmall),
            Text(
              '${t.kanal.ad} · ulaşma ${t.ulasmaTarihi.turkceBicim} · tebliğ ${t.tebligTarihi.turkceBicim}'
              '${t.esasNo != null ? ' · ${t.esasNo}' : ''}'
              '${t.taraflar.isNotEmpty ? ' · taraflar: ${t.taraflar.join(', ')}' : ''}',
            ),
            const SizedBox(height: 8),
            if (oneriler.isEmpty) const Text('Öneri yok; dosyayı elle seçin.'),
            for (final o in oneriler)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(o.dosya.baslik),
                subtitle: Text('${o.gerekce} · güven %${(o.puan * 100).round()}'),
                trailing: OutlinedButton(
                  key: Key('bagla-${t.id}-${o.dosya.id}'),
                  onPressed: () async {
                    final hata = await depo.sunucudaVeyaYerelde(
                      sunucuda: (u) => u.tebligatBagla(t.id, o.dosya.id),
                      yerelde: () {
                        depo.tebligatBagla(t.id, o.dosya.id);
                        return null;
                      },
                    );
                    if (!context.mounted) return;
                    if (hata != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
                      return;
                    }
                    final bagli = depo.tebligatlar.firstWhere((x) => x.id == t.id);
                    await _sureOlusturSor(context, bagli);
                  },
                  child: const Text('Bağla'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Yeni tebligat kaydı.
class TebligatFormu extends StatefulWidget {
  const TebligatFormu({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<TebligatFormu> createState() => _TebligatFormuState();
}

class _TebligatFormuState extends State<TebligatFormu> {
  final _form = GlobalKey<FormState>();
  final _gonderen = TextEditingController();
  final _konu = TextEditingController();
  final _esasNo = TextEditingController();
  final _taraflar = TextEditingController();
  TebligatKanali _kanal = TebligatKanali.uets;
  Tarih _ulasma = Tarih.from(DateTime.now());

  @override
  void dispose() {
    _gonderen.dispose();
    _konu.dispose();
    _esasNo.dispose();
    _taraflar.dispose();
    super.dispose();
  }

  void _kaydet() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(Tebligat(
      id: widget.depo.yeniId('t'),
      kiraciId: widget.depo.kiraciId,
      kanal: _kanal,
      ulasmaTarihi: _ulasma,
      gonderen: _gonderen.text.trim(),
      konu: _konu.text.trim(),
      esasNo: _esasNo.text.trim().isEmpty ? null : _esasNo.text.trim(),
      taraflar: _taraflar.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final teblig = _kanal.elektronikMi ? ElektronikTebligat.tebligTarihi(_ulasma) : _ulasma;
    return Scaffold(
      appBar: AppBar(title: const Text('Tebligat kaydet')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownMenu<TebligatKanali>(
              label: const Text('Kanal'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _kanal,
              onSelected: (k) => setState(() => _kanal = k ?? _kanal),
              dropdownMenuEntries: [
                for (final k in TebligatKanali.values) DropdownMenuEntry(value: k, label: k.ad),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month),
              title: Text('Ulaşma tarihi: ${_ulasma.turkceBicim}'),
              subtitle: Text('Tebliğ sayılan tarih: ${teblig.turkceBicim}'
                  '${_kanal.elektronikMi ? ' (ulaşmayı izleyen 5. gün)' : ''}'),
              onTap: () async {
                final secilen = await showDatePicker(
                  context: context,
                  initialDate: DateTime(_ulasma.yil, _ulasma.ay, _ulasma.gun),
                  firstDate: DateTime(2010),
                  lastDate: DateTime(2035),
                );
                if (secilen != null) setState(() => _ulasma = Tarih.from(secilen));
              },
            ),
            TextFormField(
              key: const Key('tebligat-gonderen'),
              controller: _gonderen,
              decoration: const InputDecoration(labelText: 'Gönderen (mahkeme, icra dairesi, kurum)'),
              validator: (d) => Dogrulayicilar.zorunlu(d, alan: 'Gönderen'),
            ),
            TextFormField(
              key: const Key('tebligat-konu'),
              controller: _konu,
              decoration: const InputDecoration(labelText: 'Konu (ör. gerekçeli karar, bilirkişi raporu)'),
              validator: (d) => Dogrulayicilar.zorunlu(d, alan: 'Konu'),
            ),
            TextFormField(
              key: const Key('tebligat-esas'),
              controller: _esasNo,
              decoration: const InputDecoration(labelText: 'Esas no (varsa)'),
            ),
            TextFormField(
              controller: _taraflar,
              decoration: const InputDecoration(labelText: 'Taraflar (virgülle ayırın)'),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const Key('tebligat-kaydet'), onPressed: _kaydet, child: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }
}
