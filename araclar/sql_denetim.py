"""Sunucudaki SQL metinlerini gerçek şemaya karşı denetler.

backend/sunucu/lib altındaki `Sql.named(...)` ve `tx.execute('...')` çağrılarındaki dize sabitlerini (yan yana
yazılmış parçalar ve `$sabit` ile gömülen `static const` dizeler dahil) çıkarır, `@ad` parametrelerini `$n` ile
değiştirir ve migration'ları uygulanmış bir test veritabanında `PREPARE` eder. Böylece tablo/sütun adı, tür ve
sözdizimi hataları Dart derleyicisi olmadan yakalanır.

Kullanım:  python3 araclar/sql_denetim.py "host=/tmp/pgdeneme port=54329 user=postgres"
"""
import glob
import pathlib
import re
import sys
import uuid

import psycopg
from tree_sitter_language_pack import get_parser

KOK = pathlib.Path(__file__).resolve().parents[1]
p = get_parser('dart')


def dize_degeri(n, sabitler):
    """Dart dize sabitinin içeriği; çözülemeyen interpolasyon varsa None."""
    t = n.text.decode()
    parcalar = re.findall(r"r?'(?:[^'\\]|\\.)*'|r?\"(?:[^\"\\]|\\.)*\"", t)
    icerik = ''.join(x[2:-1] if x.startswith('r') else x[1:-1] for x in parcalar)

    def coz(m):
        ad = m.group(1) or m.group(2)
        if ad not in sabitler:
            raise KeyError(ad)
        return sabitler[ad]

    try:
        icerik = re.sub(r'\$\{(\w+)\}|\$(\w+)', coz, icerik)
    except KeyError:
        return None
    if '${' in icerik:  # ifade gömülü (ör. koşullu parça): statik olarak çözülemez, atlanır
        return None
    return icerik.replace("\\'", "'").replace('\\"', '"').replace('\\$', '$')


def dizeler(n):
    """Bir ifadedeki yan yana dize parçaları (adjacent string literals)."""
    if n.type == 'string_literal':
        return [n]
    return None


def gez(n):
    yield n
    for c in n.children:
        yield from gez(c)


def sql_metinleri(dosya):
    kaynak = pathlib.Path(dosya).read_bytes()
    agac = p.parse(kaynak)
    sabitler = {}
    # static const ad = '...' 'devam';
    for n in gez(agac.root_node):
        if n.type in ('static_final_declaration', 'initialized_identifier'):
            ad = n.children[0] if n.children else None
            deger = n.children[-1] if n.children else None
            if ad is None or deger is None:
                continue
            parcalar = dizeler(deger)
            if parcalar:
                metinler = [dize_degeri(x, sabitler) for x in parcalar]
                if None not in metinler:
                    sabitler[ad.text.decode()] = ''.join(metinler)
    sonuc = []
    for n in gez(agac.root_node):
        if n.type != 'arguments':
            continue
        ust = n.parent.parent if n.parent is not None else None
        onceki = ust.prev_sibling if ust is not None else None
        cagri = (onceki.text.decode() if onceki is not None else '')
        if not (cagri.endswith('Sql.named') or cagri.endswith('.named') or cagri.endswith('.execute')):
            continue
        argumanlar = [c for c in n.children if c.type == 'argument']
        if not argumanlar:
            continue
        ilk = argumanlar[0].children[0] if len(argumanlar[0].children) == 1 else None
        if ilk is None:
            continue
        parcalar = dizeler(ilk)
        if not parcalar:
            continue
        metinler = [dize_degeri(x, sabitler) for x in parcalar]
        if None in metinler:
            continue
        satir = ilk.start_point[0] + 1
        sonuc.append((f'{pathlib.Path(dosya).relative_to(KOK)}:{satir}', ''.join(metinler)))
    return sonuc


def yer_tutucular(sql):
    adlar = []

    def degistir(m):
        ad = m.group(1)
        if ad not in adlar:
            adlar.append(ad)
        return f'${adlar.index(ad) + 1}'

    # @ad (ama ::tür ve e-posta benzeri değil)
    return re.sub(r'(?<![\w@])@(\w+)', degistir, sql), adlar


def main():
    dsn = sys.argv[1] if len(sys.argv) > 1 else 'host=/tmp/pgdeneme port=54329 user=postgres'
    metinler = []
    for d in sorted(glob.glob(str(KOK / 'backend/sunucu/lib/**/*.dart'), recursive=True)):
        metinler += sql_metinleri(d)
    vt = 'sql_denetim_' + uuid.uuid4().hex[:8]
    with psycopg.connect(dsn, autocommit=True) as c:
        c.execute(f'CREATE DATABASE {vt}')
    hata = 0
    try:
        with psycopg.connect(dsn + f' dbname={vt}', autocommit=True) as c:
            for m in sorted(glob.glob(str(KOK / 'backend/veritabani/migrations/*.sql'))):
                c.execute(pathlib.Path(m).read_text())
            for i, (yer, sql) in enumerate(metinler):
                donusmus, _ = yer_tutucular(sql)
                try:
                    c.execute(f'PREPARE d{i} AS {donusmus}')
                    c.execute(f'DEALLOCATE d{i}')
                except psycopg.Error as e:
                    hata += 1
                    print(f'{yer}: {str(e).splitlines()[0]}\n    {sql}')
    finally:
        with psycopg.connect(dsn, autocommit=True) as c:
            c.execute(f'DROP DATABASE {vt}')
    print(f'sql: {len(metinler)} hata: {hata}')
    sys.exit(1 if hata else 0)


if __name__ == '__main__':
    main()
