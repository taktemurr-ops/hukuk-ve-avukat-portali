"""tree-sitter Dart dilbilgisiyle sözdizimi denetimi: hatalı düğümlerin satırlarını listeler."""
import sys, glob
from tree_sitter_language_pack import get_parser

p = get_parser('dart')
toplam = 0
for yol in sys.argv[1:] or glob.glob('' + str(__import__('pathlib').Path(__file__).resolve().parents[1]) + '/**/*.dart', recursive=True):
    kaynak = open(yol, 'rb').read()
    agac = p.parse(kaynak)
    if not agac.root_node.has_error:
        continue
    hatalar = []
    def gez(n):
        if n.type == 'ERROR' or n.is_missing:
            hatalar.append(n)
            return
        if n.has_error:
            for c in n.children:
                gez(c)
    gez(agac.root_node)
    for h in hatalar[:5]:
        satir = kaynak.split(b'\n')[h.start_point[0]].decode(errors='replace').strip()
        print(f'{yol.split("portali/")[-1]}:{h.start_point[0]+1}: {"EKSİK " + h.type if h.is_missing else "HATA"}: {satir[:110]}')
    toplam += 1
print('hatali dosya:', toplam)
