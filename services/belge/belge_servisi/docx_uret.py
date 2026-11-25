"""Şablon motorunun ürettiği metinden Word (.docx) belgesi."""

from __future__ import annotations

import io
import re

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_COLOR_INDEX
from docx.shared import Cm, Pt

EKSIK = re.compile(r"\[EKSİK: ([^\]]+)\]")


def docx_uret(baslik: str, metin: str, yazi_tipi: str = "Times New Roman", punto: int = 12) -> bytes:
    """Kurallar: '# ' ile başlayan satır ortalı kalın başlık; boş satır paragraf ayırır;
    [EKSİK: alan] işaretleri sarı vurgulanır ki gönderilmeden fark edilsin."""
    belge = Document()
    for bolum in belge.sections:
        bolum.top_margin = bolum.bottom_margin = Cm(2.5)
        bolum.left_margin = bolum.right_margin = Cm(2.5)
    stil = belge.styles["Normal"]
    stil.font.name = yazi_tipi
    stil.font.size = Pt(punto)
    belge.core_properties.title = baslik

    for blok in re.split(r"\n\s*\n", metin.strip()):
        satirlar = blok.split("\n")
        if satirlar[0].startswith("# "):
            p = belge.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            r = p.add_run(satirlar[0][2:].strip())
            r.bold = True
            satirlar = satirlar[1:]
            if not satirlar:
                continue
        p = belge.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        for i, satir in enumerate(satirlar):
            if i:
                p.add_run().add_break()
            konum = 0
            for m in EKSIK.finditer(satir):
                if m.start() > konum:
                    p.add_run(satir[konum:m.start()])
                vurgu = p.add_run(m.group(0))
                vurgu.font.highlight_color = WD_COLOR_INDEX.YELLOW
                konum = m.end()
            if konum < len(satir):
                p.add_run(satir[konum:])
    cikti = io.BytesIO()
    belge.save(cikti)
    return cikti.getvalue()


def eksik_alanlar(metin: str) -> list[str]:
    return [m.group(1) for m in EKSIK.finditer(metin)]
