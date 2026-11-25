# Statik denetim araçları

Dart/Flutter kurulu olmayan ortamda da çalışan hızlı kontroller (Python + tree-sitter Dart dilbilgisi).
Derleyicinin yerini tutmaz; ilk savunma hattıdır.

```bash
pip install tree-sitter-language-pack
python araclar/dart_sozdizimi.py   # sözdizimi hataları
python araclar/dart_cakisma.py     # içe/dışa aktarmalarda isim çakışması (ambiguous import/export)
python araclar/dart_baglanti.py    # çözülmeyen import'lar ve testlerde olup ekranda olmayan Key'ler
```
