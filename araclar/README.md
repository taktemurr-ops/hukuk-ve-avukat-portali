# Statik denetim araçları

Dart/Flutter kurulu olmayan ortamda da çalışan hızlı kontroller (Python + tree-sitter Dart dilbilgisi).
Derleyicinin yerini tutmaz; ilk savunma hattıdır.

```bash
pip install tree-sitter-language-pack
python araclar/dart_sozdizimi.py   # sözdizimi hataları
python araclar/dart_cakisma.py     # içe/dışa aktarmalarda isim çakışması (ambiguous import/export)
python araclar/dart_baglanti.py    # çözülmeyen import'lar ve testlerde olup ekranda olmayan Key'ler
python araclar/dart_parametre.py   # depodaki kurucu/yöntem çağrılarında bilinmeyen veya eksik adlandırılmış argüman
```

Sunucudaki SQL metinleri (`Sql.named(...)`, `tx.execute('...')`, gömülü `static const` parçalar dahil) migration'ları
uygulanmış geçici bir veritabanında `PREPARE` edilir; tablo/sütun adı, tür ve sözdizimi hataları derlemeden yakalanır:

```bash
pip install "psycopg[binary]" tree-sitter-language-pack
python araclar/sql_denetim.py "host=localhost port=5432 user=postgres password=test"
```
