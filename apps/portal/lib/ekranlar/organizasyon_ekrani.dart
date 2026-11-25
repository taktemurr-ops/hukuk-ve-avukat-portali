import 'package:material_ui/material_ui.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/kurumsal_depo.dart';
import '../tema/tema.dart';

class OrganizasyonEkrani extends StatelessWidget {
  const OrganizasyonEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  Widget build(BuildContext context) {
    final k = kurumsal;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sirket-yeni'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => _SirketDiyalogu(kurumsal: k)),
        icon: const Icon(Icons.add_business),
        label: const Text('Şirket ekle'),
      ),
      body: ListenableBuilder(
        listenable: k,
        builder: (context, _) {
          int sozlesme(String id) => k.sozlesmeler.where((s) => k.grup.kapsam(id).contains(s.sirketId)).length;
          int talep(String id) =>
              k.defter.talepler.where((t) => !t.durum.kapali && k.grup.kapsam(id).contains(t.sirketId)).length;
          return ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
            Text('Grup şirketleri', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Üst bardan bir şirket seçildiğinde sözleşme, talep ve raporlar o şirket ve alt şirketleriyle süzülür.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Panel(
              child: Column(children: [
                for (final (s, d) in k.grup.agacSirasi())
                  ListTile(
                    key: Key('org-${s.id}'),
                    contentPadding: EdgeInsets.only(left: 24.0 * d),
                    leading: Icon(d == 0 ? Icons.account_balance : Icons.subdirectory_arrow_right,
                        color: k.aktifSirketId == s.id ? Renkler.yesil : Renkler.metinIkincil),
                    title: Text(s.unvan, style: TextStyle(fontWeight: k.aktifSirketId == s.id ? FontWeight.w700 : null)),
                    subtitle: Text('${s.vkn == null ? 'VKN girilmedi' : 'VKN ${s.vkn}'} · '
                        '${sozlesme(s.id)} sözleşme · ${talep(s.id)} açık talep (alt şirketler dahil)'),
                    trailing: TextButton(
                      key: Key('org-sec-${s.id}'),
                      onPressed: () => k.sirketSec(s.id),
                      child: const Text('Seç'),
                    ),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _SirketDiyalogu extends StatefulWidget {
  const _SirketDiyalogu({required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  State<_SirketDiyalogu> createState() => _SirketDiyaloguState();
}

class _SirketDiyaloguState extends State<_SirketDiyalogu> {
  final _unvan = TextEditingController();
  final _kisa = TextEditingController();
  final _vkn = TextEditingController();
  String? _ana;
  String? _hata;

  @override
  void dispose() {
    _unvan.dispose();
    _kisa.dispose();
    _vkn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kurumsal;
    return AlertDialog(
      title: const Text('Grup şirketi ekle'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('sirket-unvan'), controller: _unvan, decoration: const InputDecoration(labelText: 'Unvan')),
          TextField(key: const Key('sirket-kisa'), controller: _kisa, decoration: const InputDecoration(labelText: 'Kısa ad')),
          TextField(key: const Key('sirket-vkn'), controller: _vkn, decoration: const InputDecoration(labelText: 'VKN')),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            key: const Key('sirket-ana'),
            label: const Text('Bağlı olduğu şirket'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _ana = v),
            dropdownMenuEntries: [
              for (final s in k.grup.tumu) DropdownMenuEntry(value: s.id, label: s.gorunenAd),
            ],
          ),
          if (_hata != null) ...[
            const SizedBox(height: 8),
            Text(_hata!, key: const Key('sirket-hata'), style: const TextStyle(color: Renkler.kritik)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('sirket-kaydet'),
          onPressed: () async {
            final vkn = _vkn.text.trim();
            if (_unvan.text.trim().length < 3) {
              setState(() => _hata = 'Unvan zorunludur.');
              return;
            }
            if (vkn.isNotEmpty && !Dogrulayicilar.vknGecerli(vkn)) {
              setState(() => _hata = 'Vergi kimlik numarası geçersiz.');
              return;
            }
            final unvan = _unvan.text;
            final kisa = _kisa.text;
            final h = await k.sunucudaVeyaYerelde(
              sunucuda: (u) => u.sirketEkle(unvan: unvan, vkn: vkn, anaSirketId: _ana, kisaAd: kisa),
              yerelde: () => k.sirketEkle(unvan: unvan, vkn: vkn, anaSirketId: _ana, kisaAd: kisa),
            );
            if (!mounted || !context.mounted) return;
            if (h == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = h);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
