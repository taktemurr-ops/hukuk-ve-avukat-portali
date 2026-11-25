enum BildirimTuru {
  sure('Süre'),
  durusma('Duruşma'),
  tebligat('Tebligat'),
  mesaj('Müvekkil mesajı'),
  talep('Hukuk talebi'),
  sozlesme('Sözleşme'),
  icra('İcra'),
  sistem('Sistem');

  const BildirimTuru(this.ad);
  final String ad;
}

enum BildirimOnceligi { bilgi, uyari, kritik }

/// Uygulama içi bildirim. [id] kaynaktan türetilir (ör. "sure:s1:kritik"), böylece aynı olay tekrar üretilse de
/// okundu bilgisi korunur.
class Bildirim {
  const Bildirim({
    required this.id,
    required this.tur,
    required this.oncelik,
    required this.baslik,
    required this.aciklama,
    required this.zaman,
    this.hedefId,
  });

  final String id;
  final BildirimTuru tur;
  final BildirimOnceligi oncelik;
  final String baslik;
  final String aciklama;
  final DateTime zaman;

  /// Tıklanınca açılacak nesne (dosya, talep, sözleşme...).
  final String? hedefId;

  /// Telefon bildirimi metni: kişisel veri ve dosya bilgisi içermez (veri yurt dışı sunuculardan geçmez).
  static const anlikBildirimMetni = 'Hukuk ve Avukat Portalı: yeni bir bildiriminiz var.';
}

class BildirimKutusu {
  final Set<String> _okunan = {};

  bool okunduMu(Bildirim b) => _okunan.contains(b.id);

  void oku(String id) => _okunan.add(id);

  void tumunuOku(Iterable<Bildirim> l) => _okunan.addAll(l.map((b) => b.id));

  /// Okunmamışlar önce, sonra önceliğe göre (kritik önce), sonra yeni olan önce.
  List<Bildirim> sirala(Iterable<Bildirim> l) => l.toList()
    ..sort((a, b) {
      final o = (okunduMu(a) ? 1 : 0).compareTo(okunduMu(b) ? 1 : 0);
      if (o != 0) return o;
      final p = b.oncelik.index.compareTo(a.oncelik.index);
      if (p != 0) return p;
      return b.zaman.compareTo(a.zaman);
    });

  int okunmamis(Iterable<Bildirim> l) => l.where((b) => !okunduMu(b)).length;
}
