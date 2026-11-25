"""İçe aktarmaların çözülmesi ve testlerdeki Key('...') değerlerinin kaynakta bulunması kontrolü."""
import glob, os, re
KOK = str(__import__('pathlib').Path(__file__).resolve().parents[1])
paketler = {'hukuk_cekirdek': 'packages/hukuk_cekirdek/lib', 'portal': 'apps/portal/lib', 'hukuk_sunucu': 'backend/sunucu/lib'}
sorun = 0
for yol in glob.glob(KOK + '/**/*.dart', recursive=True):
    metin = open(yol).read()
    for m in re.finditer(r"^(?:import|export) '([^']+)'", metin, re.M):
        hedef = m.group(1)
        if hedef.startswith('dart:'):
            continue
        if hedef.startswith('package:'):
            ad, _, ic = hedef[8:].partition('/')
            if ad not in paketler:
                continue
            dosya = os.path.join(KOK, paketler[ad], ic)
        else:
            dosya = os.path.normpath(os.path.join(os.path.dirname(yol), hedef))
        if not os.path.exists(dosya):
            print('ÇÖZÜLMEDİ', yol.replace(KOK + '/', ''), hedef); sorun += 1
# Test anahtarları
kaynak = ''.join(open(f).read() for f in glob.glob(KOK + '/apps/portal/lib/**/*.dart', recursive=True))
# Kaynaktaki enterpolasyonlu anahtarlar: Key('emanet-aktar-$m-$d'), Key('$anahtar-kaydet') ...
dinamik = []
for m in re.finditer(r"Key\('([^']*\$[^']*)'\)", kaynak):
    desen = re.escape(m.group(1))
    desen = re.sub(r'\\\$\\\{[^}]*\\\}|\\\$\w+', '.+', desen)
    dinamik.append(re.compile(desen))
for t in glob.glob(KOK + '/apps/portal/test/*.dart'):
    for m in re.finditer(r"Key\('([^'$]+)'\)|_bas\(tester, '([^'$]+)'\)|_sec\(tester, '([^'$]+)'", open(t).read()):
        k = m.group(1) or m.group(2) or m.group(3)
        if f"'{k}'" in kaynak:
            continue
        if any(r.fullmatch(k) for r in dinamik):
            continue
        if k.startswith('menu-'):
            continue
        print('ANAHTAR YOK', os.path.basename(t), k); sorun += 1
print('sorun:', sorun)
