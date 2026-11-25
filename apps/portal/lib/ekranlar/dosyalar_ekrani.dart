import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/dosya_secici.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/sunucu_senkronu.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'etik_duvar_bolumu.dart';
import 'formlar.dart';
import 'muvekkil_portali_ekrani.dart';

Aktor oturumAktoru(Oturum o) => Aktor(kullaniciId: o.kullaniciId, kiraciId: o.kiraciId, roller: o.roller);

/// Kullanıcının görebildiği dosyalar (tek kapı yetki denetçisiyle süzülür).
class DosyalarEkrani extends StatelessWidget {
  const DosyalarEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('yeni-dosya'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<bool>(builder: (_) => DosyaFormu(depo: depo, oturum: oturum)),
        ),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Yeni dosya'),
      ),
      body: ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final bugun = Tarih.from(DateTime.now());
        final dosyalar = depo.gorunurDosyalar(oturumAktoru(oturum));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(child: Text('${dosyalar.length} dosya', style: Theme.of(context).textTheme.labelMedium)),
              TextButton.icon(
                key: const Key('belge-ara'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => BelgeAramaEkrani(depo: depo, oturum: oturum))),
                icon: const Icon(Icons.manage_search),
                label: const Text('Belgelerin içinde ara'),
              ),
            ]),
            for (final d in dosyalar)
              Card(
                child: ListTile(
                  key: Key('dosya-${d.id}'),
                  leading: Icon(d.gizli ? Icons.lock_outline : Icons.folder_outlined),
                  title: Text('${d.icNo} · ${d.baslik}'),
                  subtitle: Text(_altBilgi(d, bugun)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => DosyaDetayEkrani(depo: depo, oturum: oturum, dosyaId: d.id)),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    );
  }

  String _altBilgi(Dosya d, Tarih bugun) {
    final acikSureler = depo.dosyaSureleri(d.id).where((s) => s.acik).toList();
    return [
      d.tur.ad,
      d.asama.ad,
      if (d.mahkeme != null) d.mahkeme!,
      if (d.esasNo != null) d.esasNo!,
      'sorumlu: ${depo.kullaniciAdi(d.sorumlu)}',
      if (acikSureler.isNotEmpty) 'en yakın süre: ${kalanMetni(acikSureler.first.kalanGun(bugun))}',
    ].join(' · ');
  }
}

/// Belgelerin içinde arama: sunucuda Türkçe tam metin (taranmış belgelerde OCR ile okunan metin dahil).
/// Yalnızca görme yetkiniz olan dosyaların belgeleri listelenir.
class BelgeAramaEkrani extends StatefulWidget {
  const BelgeAramaEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<BelgeAramaEkrani> createState() => _BelgeAramaEkraniState();
}

class _BelgeAramaEkraniState extends State<BelgeAramaEkrani> {
  final _sorgu = TextEditingController();
  List<BelgeAramaSonucu>? _sonuclar;
  int _bekleyen = 0;
  String? _hata;
  bool _bekliyor = false;

  @override
  void dispose() {
    _sorgu.dispose();
    super.dispose();
  }

  Future<void> _ara() async {
    setState(() => _bekliyor = true);
    final (s, b, h) = await widget.depo.belgeAra(_sorgu.text);
    if (!mounted) return;
    // Yerel modda da yalnızca görülebilen dosyalar (sunucuda bu kural veritabanında).
    final gorunur = widget.depo.gorunurDosyalar(oturumAktoru(widget.oturum)).map((d) => d.id).toSet();
    setState(() {
      _bekliyor = false;
      _hata = h;
      _bekleyen = b;
      _sonuclar = [for (final x in s) if (x.dosyaId == null || gorunur.contains(x.dosyaId)) x];
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _sonuclar;
    return Scaffold(
      appBar: AppBar(title: const Text('Belgelerde ara')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          key: const Key('belge-ara-metin'),
          controller: _sorgu,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _ara(),
          decoration: InputDecoration(
            labelText: 'Sözcük ya da "tam ifade" (ör. kıdem tazminatı)',
            suffixIcon: IconButton(
                key: const Key('belge-ara-dugme'), onPressed: _bekliyor ? null : _ara, icon: const Icon(Icons.search)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.depo.uzak == null
              ? 'Demo modunda yalnızca şablondan üretilen belgelerin metni aranır.'
              : 'Ekler de bulunur: "tazminat" araması "tazminatı" ve "tazminatın" geçen belgeleri getirir. '
                  'Taranmış belgelerin metni OCR ile okunur ve yanlış karakterler içerebilir.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_hata != null) ...[
          const SizedBox(height: 12),
          Text(_hata!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (s != null) ...[
          const SizedBox(height: 12),
          Text('${s.length} belge${_bekleyen > 0 ? ' · $_bekleyen belgenin metni henüz okunuyor' : ''}',
              key: const Key('belge-ara-sayi'), style: Theme.of(context).textTheme.labelMedium),
          for (final x in s)
            Card(
              child: ListTile(
                key: Key('belge-sonuc-${x.belgeId}'),
                leading: Icon(x.ocr ? Icons.document_scanner_outlined : Icons.description_outlined),
                title: Text('${x.ad}${x.dosyaNo == null ? '' : ' · ${x.dosyaNo}'}'),
                subtitle: Text(x.ozet),
                onTap: x.dosyaId == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => DosyaDetayEkrani(depo: widget.depo, oturum: widget.oturum, dosyaId: x.dosyaId!))),
              ),
            ),
        ],
      ]),
    );
  }
}

class DosyaDetayEkrani extends StatelessWidget {
  const DosyaDetayEkrani({super.key, required this.depo, required this.oturum, required this.dosyaId});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final String dosyaId;

  Future<String?> _kanitIste(BuildContext context, String baslik) => MetinGirisDiyalogu.goster(
        context,
        MetinGirisDiyalogu(
          baslik: baslik,
          etiket: 'İşlem no, makbuz no veya belge adı',
          alanAnahtari: const Key('kanit-alani'),
          onayAnahtari: const Key('kanit-onayla'),
        ),
      );

  void _mesaj(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final d = depo.dosya(dosyaId)!;
        final bugun = Tarih.from(DateTime.now());
        final metin = Theme.of(context).textTheme;
        final sureler = depo.dosyaSureleri(d.id);
        final gorevler = depo.dosyaGorevleri(d.id);
        final tebligatlar = depo.dosyaTebligatlari(d.id);
        return Scaffold(
          appBar: AppBar(title: Text('${d.icNo} · ${d.baslik}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(d.tur.ad)),
                  Chip(label: Text(d.asama.ad)),
                  if (d.gizli) const Chip(avatar: Icon(Icons.lock_outline, size: 16), label: Text('Gizli')),
                  if (d.mahkeme != null) Chip(label: Text(d.mahkeme!)),
                  if (d.esasNo != null) Chip(label: Text(d.esasNo!)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Asıl sorumlu: ${depo.kullaniciAdi(d.sorumlu)} · '
                'Yedek: ${d.yedekSorumlu == null ? 'atanmamış' : depo.kullaniciAdi(d.yedekSorumlu!)}',
              ),
              const Divider(height: 32),
              Text('Süreler', style: metin.titleMedium),
              if (sureler.isEmpty) const ListTile(title: Text('Kayıtlı süre yok.')),
              for (final s in sureler)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.aciklama, style: metin.titleSmall),
                        Text(
                          'Son gün ${s.sonGun.turkceBicim} ${s.sonGun.gunAdi} (${kalanMetni(s.kalanGun(bugun))}) · '
                          '${s.durum.ad}${s.teyitEden != null ? ' · teyit: ${depo.kullaniciAdi(s.teyitEden!)}' : ''}'
                          '${s.tamamlanmaKaniti != null ? ' · kanıt: ${s.tamamlanmaKaniti}' : ''}',
                        ),
                        Text('Dayanak: ${s.sonuc.kural.dayanak} · hesaplayan: ${depo.kullaniciAdi(s.olusturan)}',
                            style: metin.bodySmall),
                        if (s.oncekiHesaplar.isNotEmpty)
                          Text('${s.oncekiHesaplar.length} önceki hesap saklanıyor', style: metin.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (s.durum == SureDurumu.teyitBekliyor)
                              FilledButton.tonal(
                                key: Key('teyit-${s.id}'),
                                onPressed: () async {
                                  final uzak = depo.uzak;
                                  try {
                                    if (uzak != null) {
                                      await uzak.sureTeyit(s.id);
                                    } else {
                                      depo.sureGuncelle(s.teyitEt(kullanici: oturum.kullaniciId, tarih: bugun));
                                    }
                                    if (context.mounted) _mesaj(context, 'Süre teyit edildi.');
                                  } on StateError catch (e) {
                                    _mesaj(context, e.message);
                                  } on Exception catch (e) {
                                    if (context.mounted) _mesaj(context, '$e');
                                  }
                                },
                                child: const Text('Hesabı teyit et'),
                              ),
                            if (s.durum == SureDurumu.teyitli)
                              FilledButton.tonal(
                                key: Key('tamamla-${s.id}'),
                                onPressed: () async {
                                  final kanit = await _kanitIste(context, 'Süreyi tamamla');
                                  if (kanit == null || !context.mounted) return;
                                  final uzak = depo.uzak;
                                  try {
                                    if (uzak != null) {
                                      await uzak.sureTamamla(s.id, kanit);
                                    } else {
                                      depo.sureGuncelle(s.tamamla(kanit: kanit));
                                    }
                                    if (context.mounted) _mesaj(context, 'Süre tamamlandı.');
                                  } on ArgumentError catch (e) {
                                    _mesaj(context, '${e.message}');
                                  } on Exception catch (e) {
                                    if (context.mounted) _mesaj(context, '$e');
                                  }
                                },
                                child: const Text('İşlem yapıldı'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 32),
              Text('Görevler', style: metin.titleMedium),
              if (gorevler.isEmpty) const ListTile(title: Text('Görev yok.')),
              for (final g in gorevler)
                CheckboxListTile(
                  key: Key('gorev-${g.id}'),
                  value: g.durum == GorevDurumu.tamamlandi,
                  onChanged: g.durum != GorevDurumu.acik
                      ? null
                      : (_) async {
                          final kanitGerekir = g.kanitGerekir || g.kaynakSureId != null;
                          String? kanit;
                          if (kanitGerekir) {
                            kanit = await _kanitIste(context, 'Görevi kapat');
                            if (kanit == null || !context.mounted) return;
                          }
                          final hata = await depo.sunucudaVeyaYerelde(
                            sunucuda: (u) => u.gorevKapat(g.id, kanit: kanit),
                            yerelde: () {
                              try {
                                depo.gorevGuncelle(g.kapat(kanit: kanit));
                                return null;
                              } on ArgumentError catch (e) {
                                return '${e.message}';
                              }
                            },
                          );
                          if (hata != null && context.mounted) _mesaj(context, hata);
                        },
                  title: Text(g.baslik),
                  subtitle: Text(
                    '${depo.kullaniciAdi(g.atanan)}'
                    '${g.sonTarih != null ? ' · ${g.sonTarih!.turkceBicim}' : ''}'
                    '${g.gecikti(bugun) ? ' · gecikti' : ''}'
                    '${g.kapanisKaniti != null ? ' · kanıt: ${g.kapanisKaniti}' : ''}',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(child: Text('Duruşmalar ve etkinlikler', style: metin.titleMedium)),
                  OutlinedButton.icon(
                    key: const Key('durusma-ekle'),
                    onPressed: () async {
                      final r = await showDialog<(DateTime, String, String)>(
                        context: context,
                        builder: (_) => const DurusmaDiyalogu(),
                      );
                      if (r == null || !context.mounted) return;
                      final (zaman, yer, tur) = r;
                      final uzak = depo.uzak;
                      final List<String> cakismalar;
                      if (uzak != null) {
                        try {
                          cakismalar = await uzak.durusmaEkle(
                              dosyaId: d.id, baslangic: zaman, yer: yer, katilan: oturum.kullaniciId, tur: tur);
                        } on Exception catch (e) {
                          if (context.mounted) _mesaj(context, '$e');
                          return;
                        }
                      } else {
                        cakismalar = [
                          for (final c in depo.durusmaEkle(
                              dosyaId: d.id, baslangic: zaman, yer: yer, katilan: oturum.kullaniciId, tur: tur))
                            c.neden,
                        ];
                      }
                      if (!context.mounted) return;
                      _mesaj(
                        context,
                        cakismalar.isEmpty
                            ? '$tur eklendi.'
                            : 'Eklendi, ancak çakışma var: ${cakismalar.first}. Mazeret dilekçesi veya tevkil gerekebilir.',
                      );
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              for (final du in depo.durusmalar.where((x) => x.dosyaId == d.id).toList()
                ..sort((a, b) => a.baslangic.compareTo(b.baslangic)))
                ListTile(
                  leading: const Icon(Icons.gavel),
                  title: Text('${du.tur} · ${tarihSaat(du.baslangic)}'),
                  subtitle: Text('${du.yer} · ${depo.kullaniciAdi(du.katilan)}'),
                ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(child: Text('Belgeler', style: metin.titleMedium)),
                  OutlinedButton.icon(
                    key: const Key('belge-dosyadan'),
                    onPressed: () async {
                      final f = await dosyaSecici(const ['pdf', 'docx', 'doc', 'udf', 'jpg', 'jpeg', 'png', 'tif', 'tiff', 'txt', 'xlsx']);
                      if (f == null || !context.mounted) return;
                      final h = await depo.dosyadanBelgeYukle(
                          dosyaId: d.id, dosyaAdi: f.ad, icerik: f.icerik, tur: BelgeTuru.diger);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(h ?? '${f.ad} yüklendi (zararlı yazılım taraması ve SHA-256 özetiyle).')));
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Dosyadan yükle'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('sablondan-belge'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => SablondanBelgeEkrani(depo: depo, oturum: oturum, dosyaId: d.id),
                    )),
                    icon: const Icon(Icons.edit_document),
                    label: const Text('Şablondan belge'),
                  ),
                ],
              ),
              if (depo.dosyaBelgeleri(d.id).isEmpty) const ListTile(title: Text('Belge yok.')),
              for (final b in depo.dosyaBelgeleri(d.id))
                ListTile(
                  key: Key('belge-${b.id}'),
                  leading: Icon(b.gizli ? Icons.lock_outline : Icons.description_outlined),
                  title: Text(b.ad),
                  subtitle: Text(
                    'Sürüm ${b.guncel.no} · ${b.guncel.tarih.turkceBicim} · ${depo.kullaniciAdi(b.guncel.yukleyen)} · '
                    'SHA-256 ${b.guncel.ozet.substring(0, 12)}…'
                    '${b.surumler.length > 1 ? ' · orijinal sürüm 1 korunuyor' : ''}',
                  ),
                  // Sunucu bağlıyken dokununca güncel sürüm indirilir (bütünlüğü sunucuda doğrulanır, denetime yazılır).
                  onTap: depo.uzak == null
                      ? null
                      : () async {
                          final mesaj = ScaffoldMessenger.of(context);
                          try {
                            final icerik = await depo.uzak!.belgeIndir(b.id, b.guncel.no);
                            await dosyaKaydet(b.guncel.dosyaAdi, icerik);
                          } on Exception catch (e) {
                            mesaj.showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                  trailing: !depo.portaldaMi(d.id) || b.gizli
                      ? null
                      : IconButton(
                          key: Key('belge-paylas-${b.id}'),
                          tooltip: depo.belgePaylasildiMi(b.id) ? 'Müvekkil paylaşımını kaldır' : 'Müvekkille paylaş',
                          onPressed: () async {
                            final paylas = !depo.belgePaylasildiMi(b.id);
                            final h = await depo.sunucudaVeyaYerelde(
                              sunucuda: (u) => u.belgePaylas(b.id, paylas),
                              yerelde: () {
                                depo.belgePaylas(b.id, paylas);
                                return null;
                              },
                            );
                            if (h != null && context.mounted) _mesaj(context, h);
                          },
                          icon: Icon(
                            depo.belgePaylasildiMi(b.id) ? Icons.visibility : Icons.visibility_off_outlined,
                            color: depo.belgePaylasildiMi(b.id) ? Renkler.yesil : Renkler.metinIkincil,
                          ),
                        ),
                ),
              const Divider(height: 32),
              Text('Tebligatlar', style: metin.titleMedium),
              if (tebligatlar.isEmpty) const ListTile(title: Text('Tebligat yok.')),
              for (final t in tebligatlar)
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text('${t.konu} · ${t.gonderen}'),
                  subtitle: Text(
                    '${t.kanal.ad} · ulaşma ${t.ulasmaTarihi.turkceBicim} · tebliğ ${t.tebligTarihi.turkceBicim}',
                  ),
                ),
              const Divider(height: 32),
              PortalYonetimBolumu(depo: depo, dosyaId: d.id),
              if (oturum.lisans.modulAcik(Modul.etikDuvar) &&
                  oturum.roller.any((r) => r == Rol.buroSahibi || r == Rol.yoneticiOrtak)) ...[
                const Divider(height: 32),
                EtikDuvarBolumu(depo: depo, dosya: d),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Şablon seç → dosya verileriyle doldur → eksik alanları gör → belge olarak kaydet.
class SablondanBelgeEkrani extends StatefulWidget {
  const SablondanBelgeEkrani({super.key, required this.depo, required this.oturum, required this.dosyaId});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final String dosyaId;

  @override
  State<SablondanBelgeEkrani> createState() => _SablondanBelgeEkraniState();
}

class _SablondanBelgeEkraniState extends State<SablondanBelgeEkrani> {
  BelgeSablonu? _sablon;
  late final TextEditingController _metin = TextEditingController();
  SablonCiktisi? _cikti;
  bool _pdf = false;

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _sec(BelgeSablonu s) {
    final cikti = s.uygula(widget.depo.sablonVerisi(
      dosyaId: widget.dosyaId,
      avukatAdi: widget.oturum.adSoyad,
      buroAdi: widget.oturum.kurumAdi,
    ));
    setState(() {
      _sablon = s;
      _cikti = cikti;
      _metin.text = cikti.metin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cikti = _cikti;
    final kalanEksik = RegExp(r'\[EKSİK: [^\]]+\]').allMatches(_metin.text).length;
    return Scaffold(
      appBar: AppBar(title: Text('Şablondan belge · ${widget.depo.dosya(widget.dosyaId)?.baslik ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in BelgeSablonu.hazir)
                ChoiceChip(
                  key: Key('sablon-${s.kod}'),
                  label: Text(s.ad),
                  selected: _sablon == s,
                  onSelected: (_) => _sec(s),
                ),
            ],
          ),
          if (cikti != null) ...[
            const SizedBox(height: 16),
            if (cikti.sablon.onayDurumu != OnayDurumu.onayli)
              const DurumRozeti('Şablon metni avukat onayı bekliyor', RozetTuru.uyari),
            if (cikti.sablon.dayanak != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Dayanak: ${cikti.sablon.dayanak}'),
              ),
            if (cikti.eksikAlanlar.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Dosyada bulunamayan alanlar (metinde [EKSİK] olarak işaretli):',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final a in cikti.eksikAlanlar) DurumRozeti(a, RozetTuru.kritik)],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('belge-metni'),
              controller: _metin,
              maxLines: null,
              minLines: 16,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (widget.depo.uzak != null) ...[
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const Key('belge-bicim'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Word (düzenlenebilir)')),
                  ButtonSegment(value: true, label: Text('PDF (gönderime hazır)')),
                ],
                selected: {_pdf},
                onSelectionChanged: (s) => setState(() => _pdf = s.first),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(kalanEksik > 0
                      ? '$kalanEksik eksik alan doldurulmadan belge kaydedilemez.'
                      : 'Belge kaydedilince SHA-256 özetiyle sürüm 1 olarak saklanır.'),
                ),
                FilledButton(
                  key: const Key('belge-kaydet'),
                  onPressed: kalanEksik > 0
                      ? null
                      : () async {
                          final ad = _sablon!.ad;
                          final metin = _metin.text;
                          final hata = await widget.depo.sunucudaVeyaYerelde(
                            // Sunucuda Word'e çevrilip kaydedilir (belge servisi); eksik alan varsa sunucu da reddeder.
                            sunucuda: (u) => u.wordBelgeKaydet(
                              dosyaId: widget.dosyaId,
                              ad: ad,
                              metin: metin,
                              tur: BelgeTuru.dilekce,
                              pdf: _pdf,
                            ),
                            yerelde: () {
                              widget.depo.belgeOlustur(
                                  dosyaId: widget.dosyaId, ad: ad, metin: metin, yukleyen: widget.oturum.kullaniciId);
                              return null;
                            },
                          );
                          if (!mounted) return;
                          if (hata != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hata)));
                            return;
                          }
                          Navigator.of(context).pop();
                        },
                  child: const Text('Belge olarak kaydet'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
