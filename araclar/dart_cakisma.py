"""Kütüphaneler arası isim çakışması: aynı dosyaya içe aktarılan iki kütüphane aynı üst düzey adı tanımlıyor ve
dosya o adı kullanıyorsa Dart 'ambiguous import' hatası verir. Ayrıca tek kütüphanenin dışa aktardıkları çakışırsa hata."""
import glob, os, re
from tree_sitter_language_pack import get_parser

KOK = str(__import__('pathlib').Path(__file__).resolve().parents[1])
paketler = {'hukuk_cekirdek': 'packages/hukuk_cekirdek/lib', 'portal': 'apps/portal/lib', 'hukuk_sunucu': 'backend/sunucu/lib'}
p = get_parser('dart')
_ust = {}

def cozumle(yol, hedef):
    if hedef.startswith('package:'):
        ad, _, ic = hedef[8:].partition('/')
        return os.path.join(KOK, paketler[ad], ic) if ad in paketler else None
    if hedef.startswith('dart:'):
        return None
    return os.path.normpath(os.path.join(os.path.dirname(yol), hedef))

def ust_duzey(yol):
    """Dosyanın kendisinin tanımladığı açık (alt çizgisiz) üst düzey adlar."""
    if yol in _ust:
        return _ust[yol]
    kaynak = open(yol, 'rb').read()
    adlar = set()
    for n in p.parse(kaynak).root_node.children:
        t = n.type
        if t in ('class_definition', 'enum_declaration', 'mixin_declaration', 'extension_declaration', 'type_alias'):
            for c in n.children:
                if c.type == 'identifier':
                    adlar.add(c.text.decode()); break
        elif t in ('function_signature', 'getter_signature'):
            for c in n.children:
                if c.type == 'identifier':
                    adlar.add(c.text.decode()); break
        elif t in ('top_level_variable_declaration', 'initialized_identifier_list', 'static_final_declaration_list'):
            for m in re.finditer(rb'\b([A-Za-z]\w*)\s*=', n.text):
                adlar.add(m.group(1).decode())
    adlar = {a for a in adlar if not a.startswith('_')}
    _ust[yol] = adlar
    return adlar

def disa_aktarilan(yol, ziyaret=None):
    """Kütüphanenin dışa sunduğu adlar -> tanımlandığı dosya (export zinciri dahil, show/hide basitçe)."""
    ziyaret = ziyaret or set()
    if yol in ziyaret or not os.path.exists(yol):
        return {}
    ziyaret.add(yol)
    sonuc = {a: yol for a in ust_duzey(yol)}
    metin = open(yol).read()
    for m in re.finditer(r"^export '([^']+)'(?:\s+(show|hide)\s+([^;]+))?;", metin, re.M):
        h = cozumle(yol, m.group(1))
        if not h:
            continue
        alt = disa_aktarilan(h, ziyaret)
        if m.group(2) == 'show':
            izin = {x.strip() for x in m.group(3).split(',')}
            alt = {k: v for k, v in alt.items() if k in izin}
        elif m.group(2) == 'hide':
            gizli = {x.strip() for x in m.group(3).split(',')}
            alt = {k: v for k, v in alt.items() if k not in gizli}
        for k, v in alt.items():
            if k in sonuc and sonuc[k] != v:
                print(f'DIŞA AKTARMA ÇAKIŞMASI {yol.replace(KOK+"/","")}: {k} ({sonuc[k].split("/")[-1]} / {v.split("/")[-1]})')
            sonuc.setdefault(k, v)
    return sonuc

sorun = 0
for yol in glob.glob(KOK + '/**/*.dart', recursive=True):
    metin = open(yol).read()
    kendi = ust_duzey(yol)
    kimden = {}
    for m in re.finditer(r"^import '([^']+)'(?:\s+as\s+\w+)?(?:\s+(show|hide)\s+([^;]+))?;", metin, re.M):
        if ' as ' in m.group(0):
            continue
        h = cozumle(yol, m.group(1))
        if not h:
            continue
        adlar = disa_aktarilan(h)
        if m.group(2) == 'show':
            izin = {x.strip() for x in m.group(3).split(',')}
            adlar = {k: v for k, v in adlar.items() if k in izin}
        elif m.group(2) == 'hide':
            gizli = {x.strip() for x in m.group(3).split(',')}
            adlar = {k: v for k, v in adlar.items() if k not in gizli}
        for k, v in adlar.items():
            kimden.setdefault(k, set()).add(v)
    govde = re.sub(r"^(import|export) .*$", '', metin, flags=re.M)
    for k, kaynaklar in kimden.items():
        if len(kaynaklar) > 1 and k not in kendi and re.search(r'\b' + re.escape(k) + r'\b', govde):
            print('BELİRSİZ', yol.replace(KOK + '/', ''), k, sorted(x.split('/')[-1] for x in kaynaklar)); sorun += 1
print('sorun:', sorun)
