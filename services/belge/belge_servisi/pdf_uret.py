"""Şablon motorunun ürettiği metinden PDF (A4). Word çıktısıyla aynı kurallar: '# ' ile başlayan satır ortalı kalın
başlık, boş satır paragraf ayırır, [EKSİK: alan] işaretleri sarı vurgulanır. Türkçe karakterler için yazı tipi
gömülür (Liberation Serif: Times New Roman ile aynı ölçüler; SIL OFL)."""

from __future__ import annotations

import io
import os
import re
from xml.sax.saxutils import escape

from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from .docx_uret import EKSIK
from .guvenlik import BelgeHatasi

_ADAYLAR = [
    os.environ.get("BELGE_PDF_FONT_KLASORU", ""),
    "/usr/share/fonts/truetype/liberation",
    "/usr/share/fonts/truetype/liberation2",
]
_yuklendi = False


def _font_yukle() -> None:
    global _yuklendi
    if _yuklendi:
        return
    for klasor in _ADAYLAR:
        duz = os.path.join(klasor, "LiberationSerif-Regular.ttf")
        kalin = os.path.join(klasor, "LiberationSerif-Bold.ttf")
        if klasor and os.path.exists(duz) and os.path.exists(kalin):
            pdfmetrics.registerFont(TTFont("BelgeSerif", duz))
            pdfmetrics.registerFont(TTFont("BelgeSerif-Kalin", kalin))
            pdfmetrics.registerFontFamily("BelgeSerif", normal="BelgeSerif", bold="BelgeSerif-Kalin")
            _yuklendi = True
            return
    raise BelgeHatasi("PDF yazı tipi bulunamadı (fonts-liberation kurulu olmalı).")


def _satir_isaretle(satir: str) -> str:
    parcalar = []
    konum = 0
    for m in EKSIK.finditer(satir):
        parcalar.append(escape(satir[konum:m.start()]))
        parcalar.append(f'<font backColor="#FFF200">{escape(m.group(0))}</font>')
        konum = m.end()
    parcalar.append(escape(satir[konum:]))
    return "".join(parcalar)


def pdf_uret(baslik: str, metin: str, punto: int = 12) -> bytes:
    _font_yukle()
    govde = ParagraphStyle("govde", fontName="BelgeSerif", fontSize=punto, leading=punto * 1.4, alignment=TA_JUSTIFY,
                           spaceAfter=punto * 0.6)
    ust = ParagraphStyle("ust", parent=govde, fontName="BelgeSerif-Kalin", alignment=TA_CENTER, spaceAfter=punto)
    akis = []
    for blok in re.split(r"\n\s*\n", metin.strip()):
        satirlar = blok.split("\n")
        if satirlar[0].startswith("# "):
            akis.append(Paragraph(escape(satirlar[0][2:].strip()), ust))
            satirlar = satirlar[1:]
            if not satirlar:
                continue
        akis.append(Paragraph("<br/>".join(_satir_isaretle(s) for s in satirlar), govde))
    if not akis:
        akis.append(Spacer(1, 1))
    cikti = io.BytesIO()
    belge = SimpleDocTemplate(cikti, pagesize=A4, leftMargin=2.5 * cm, rightMargin=2.5 * cm, topMargin=2.5 * cm,
                              bottomMargin=2.5 * cm, title=baslik, author="Hukuk ve Avukat Portalı", creator="Hukuk ve Avukat Portalı")
    belge.build(akis)
    return cikti.getvalue()
