"""Depodaki sınıfların kurucuları ve yöntemleri için çağrı yerlerinde adlandırılmış argüman denetimi:
var olmayan argüman adı ve verilmemiş `required` argüman. Alıcı türü çözülemeyen yöntem çağrılarında yalnızca
depoda tek tanımı olan yöntem adları denetlenir."""
import collections
import glob
import pathlib
import re

from tree_sitter_language_pack import get_parser

KOK = str(pathlib.Path(__file__).resolve().parents[1])
p = get_parser('dart')
dosyalar = [f for f in glob.glob(KOK + '/**/*.dart', recursive=True)]


def metin(n):
    return n.text.decode()


def parametreler(imza):
    """(adlandırılmış adlar, zorunlu adlandırılmış adlar, konumsal sayısı (en az, en çok))."""
    adli, zorunlu = set(), set()
    en_az = en_cok = 0
    liste = None
    for c in imza.children:
        if c.type == 'formal_parameter_list':
            liste = c
    if liste is None:
        return None
    for c in liste.children:
        if c.type == 'formal_parameter':
            en_az += 1
            en_cok += 1
        elif c.type == 'optional_formal_parameters':
            adli_blok = metin(c).startswith('{')
            onceki_required = False
            for d in c.children:
                if metin(d) == 'required':
                    onceki_required = True
                    continue
                if d.type not in ('formal_parameter', 'default_formal_parameter', 'named_parameter'):
                    continue
                t = metin(d)
                if adli_blok:
                    ad = re.sub(r'.*?([A-Za-z_]\w*)\s*$', r'\1', re.split(r'=|:(?!:)', t)[0].strip())
                    adli.add(ad)
                    if onceki_required or t.strip().startswith('required'):
                        zorunlu.add(ad)
                else:
                    en_cok += 1
                onceki_required = False
    return adli, zorunlu, (en_az, en_cok)


kurucular = {}  # 'Sinif' veya 'Sinif.ad' -> imza
yontemler = collections.defaultdict(list)  # yöntem adı -> [imza]
siniflar = set()


def gez_sinif(n, sinif):
    for c in n.children:
        if c.type in ('class_body', 'enum_body'):
            for uye in c.children:
                gez_uye(uye, sinif)


def gez_uye(n, sinif):
    for c in n.children if n.type in ('class_member_definition', 'declaration', 'method_signature') else [n]:
        if c.type in ('constructor_signature', 'constant_constructor_signature', 'factory_constructor_signature',
                      'redirecting_factory_constructor_signature'):
            kimlikler = [metin(x) for x in c.children if x.type == 'identifier']
            ad = sinif if len(kimlikler) < 2 else f'{sinif}.{kimlikler[1]}'
            pr = parametreler(c)
            if pr:
                kurucular[ad] = pr
        elif c.type in ('function_signature',):
            kimlik = next((metin(x) for x in c.children if x.type == 'identifier'), None)
            pr = parametreler(c)
            if kimlik and pr:
                yontemler[kimlik].append((sinif, pr))
        elif c.type in ('declaration', 'method_signature', 'class_member_definition'):
            gez_uye(c, sinif)


for f in dosyalar:
    kok = p.parse(open(f, 'rb').read()).root_node
    for n in kok.children:
        if n.type in ('class_definition', 'enum_declaration'):
            ad = next((metin(x) for x in n.children if x.type == 'identifier'), None)
            if ad:
                siniflar.add(ad)
                gez_sinif(n, ad)
                if f'{ad}' not in kurucular and n.type == 'class_definition':
                    kurucular.setdefault(ad, (set(), set(), (0, 0)))  # örtük kurucu
        elif n.type == 'function_signature':
            kimlik = next((metin(x) for x in n.children if x.type == 'identifier'), None)
            pr = parametreler(n)
            if kimlik and pr:
                yontemler[kimlik].append((None, pr))


def argumanlar(kaynak, i):
    """kaynak[i] == '(' ; eşleşen ')' konumu ve üst düzey argüman metinleri."""
    derin, j, bas, args = 0, i, i + 1, []
    tirnak = None
    while j < len(kaynak):
        ch = kaynak[j]
        if tirnak:
            if ch == '\\':
                j += 2
                continue
            if kaynak.startswith(tirnak, j):
                j += len(tirnak)
                tirnak = None
                continue
        elif kaynak.startswith("'''", j) or kaynak.startswith('"""', j):
            tirnak = kaynak[j:j + 3]
            j += 3
            continue
        elif ch in '\'"':
            tirnak = ch
        elif ch in '([{':
            derin += 1
        elif ch in ')]}':
            derin -= 1
            if derin == 0:
                args.append(kaynak[bas:j])
                # Argümanın önündeki satır yorumları (// …) ad tespitini bozmasın.
                temiz = [re.sub(r'^(\s*//[^\n]*\n)+', '', a) for a in args]
                return j, [a.strip() for a in temiz if a.strip()]
        elif ch == ',' and derin == 1:
            args.append(kaynak[bas:j])
            bas = j + 1
        j += 1
    return None, []


sorun = 0
tek_yontemler = {ad: liste[0][1] for ad, liste in yontemler.items() if len(liste) == 1}
for f in dosyalar:
    kaynak = open(f).read()
    goreli = f.replace(KOK + '/', '')
    for m in re.finditer(r'(?<![\w.])([A-Z]\w*)(?:\.([a-z]\w*))?(?:<[^()]*?>)?\(', kaynak):
        sinif, alt = m.group(1), m.group(2)
        if sinif not in siniflar:
            continue
        anahtar = f'{sinif}.{alt}' if alt else sinif
        pr = kurucular.get(anahtar)
        if pr is None and alt:
            aday = [x for s, x in yontemler.get(alt, []) if s == sinif]
            pr = aday[0] if aday else None
        if pr is None:
            continue
        satir_basi = kaynak.rfind('\n', 0, m.start()) + 1
        if re.match(r'\s*(const\s+|factory\s+)?' + re.escape(sinif) + r'(\.\w+)?\(\{?\s*(this|super|required|[A-Z]\w*\s|[a-z]\w*\??\s)', kaynak[satir_basi:]) \
                and ('{' in kaynak[m.end():m.end() + 2] or kaynak[satir_basi:m.start()].strip() in ('', 'const', 'factory')):
            # Tanım satırı (kurucu bildirimi) olabilir; çağrı değil.
            if re.search(r'\)\s*(:|\{|=>|;)', kaynak[m.end():m.end() + 2000].split('\n\n')[0]) and kaynak[satir_basi:m.start()].strip() in ('', 'const', 'factory'):
                govde = kaynak[m.end():m.end() + 400]
                if re.match(r'\s*\{?\s*(required\s+)?(this\.|super\.|[A-Z])', govde):
                    continue
        _, args = argumanlar(kaynak, m.end() - 1)
        adlar = {re.match(r'([A-Za-z_]\w*)\s*:', a).group(1) for a in args if re.match(r'[A-Za-z_]\w*\s*:(?!:)', a)}
        adli, zorunlu, _ = pr
        satir = kaynak.count('\n', 0, m.start()) + 1
        for a in sorted(adlar - adli):
            print(f'{goreli}:{satir}: {anahtar}() bilinmeyen argüman "{a}"'); sorun += 1
        for z in sorted(zorunlu - adlar):
            print(f'{goreli}:{satir}: {anahtar}() zorunlu argüman eksik "{z}"'); sorun += 1
# Alıcısı çözülemeyen yöntem ve üst düzey fonksiyon çağrıları: yalnızca depoda tek tanımı olan, adlandırılmış
# parametresi bulunan adlar (Flutter/Dart'ta aynı adla bir yöntem olabileceği için yalnızca bilinmeyen argüman raporlanır).
for f in dosyalar:
    kaynak = open(f).read()
    goreli = f.replace(KOK + '/', '')
    for m in re.finditer(r'(?:(?<=\.)|(?<![\w.]))([a-z]\w*)\(', kaynak):
        ad = m.group(1)
        pr = tek_yontemler.get(ad)
        if pr is None or not pr[0]:
            continue
        onceki = kaynak[max(0, m.start() - 40):m.start()]
        if re.search(r'(Future<[^>]*>|void|[A-Z]\w*[?>]?|static|get|bool|int|String|double)\s+$', onceki):
            continue  # tanım
        _, args = argumanlar(kaynak, m.end() - 1)
        adlar = {re.match(r'([A-Za-z_]\w*)\s*:', x).group(1) for x in args if re.match(r'[A-Za-z_]\w*\s*:(?!:)', x)}
        satir = kaynak.count('\n', 0, m.start()) + 1
        for x in sorted(adlar - pr[0]):
            print(f'{goreli}:{satir}: {ad}() bilinmeyen argüman "{x}"'); sorun += 1
        for z in sorted(pr[1] - adlar):
            if adlar:
                print(f'{goreli}:{satir}: {ad}() zorunlu argüman eksik "{z}" (aynı adlı başka bir yöntem olabilir)'); sorun += 1
print('kurucu:', len(kurucular), 'sorun:', sorun)
