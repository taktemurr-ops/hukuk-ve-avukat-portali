"""Rapor tablolarından Excel (.xlsx) ya da PDF. Hücreler metin olarak gelir; sayıya benzeyenler (1.234,56 / 12) Excel'de
sayı olarak yazılır ki toplanabilsin. Formül enjeksiyonuna karşı '=', '+', '-', '@' ile başlayan metinler kaçışlanır."""

from __future__ import annotations

import io
import re
from xml.sax.saxutils import escape

from .guvenlik import BelgeHatasi

_SAYI = re.compile(r"^-?\d{1,3}(\.\d{3})*(,\d+)?$|^-?\d+(,\d+)?$")
AZAMI_SATIR = 20000


def _sayi_mi(h: str) -> float | None:
    t = h.strip().removesuffix(" TL").strip()
    if not t or not _SAYI.match(t):
        return None
    return float(t.replace(".", "").replace(",", "."))


def _guvenli(h: str) -> str:
    return "'" + h if h[:1] in ("=", "+", "-", "@") and _sayi_mi(h) is None else h


def _dogrula(sayfalar: list[dict]) -> None:
    if not sayfalar:
        raise BelgeHatasi("Rapor boş.")
    if sum(len(s.get("satirlar", [])) for s in sayfalar) > AZAMI_SATIR:
        raise BelgeHatasi(f"Rapor {AZAMI_SATIR} satırı aşıyor.")


def xlsx_uret(baslik: str, sayfalar: list[dict]) -> bytes:
    _dogrula(sayfalar)
    import openpyxl
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    kitap = openpyxl.Workbook()
    kitap.remove(kitap.active)
    kitap.properties.title = baslik
    kitap.properties.creator = "Hukuk ve Avukat Portalı"
    for s in sayfalar:
        ad = re.sub(r"[\[\]:*?/\\]", "-", str(s.get("ad") or "Rapor"))[:31] or "Rapor"
        sayfa = kitap.create_sheet(ad)
        basliklar = [str(b) for b in s.get("basliklar", [])]
        sayfa.append(basliklar)
        for h in sayfa[1]:
            h.font = Font(bold=True, color="FFFFFF")
            h.fill = PatternFill("solid", fgColor="0E5A4E")
            h.alignment = Alignment(vertical="center")
        for satir in s.get("satirlar", []):
            hucreler = []
            for h in satir:
                metin = "" if h is None else str(h)
                n = _sayi_mi(metin)
                hucreler.append(n if n is not None else _guvenli(metin))
            sayfa.append(hucreler)
        sayfa.freeze_panes = "A2"
        for i, b in enumerate(basliklar, start=1):
            genislik = max([len(b)] + [len(str(r[i - 1])) for r in s.get("satirlar", []) if len(r) >= i] + [6])
            sayfa.column_dimensions[get_column_letter(i)].width = min(genislik + 2, 60)
    cikti = io.BytesIO()
    kitap.save(cikti)
    return cikti.getvalue()


def pdf_tablo_uret(baslik: str, sayfalar: list[dict]) -> bytes:
    _dogrula(sayfalar)
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import cm
    from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    from .pdf_uret import _font_yukle

    _font_yukle()
    hucre = ParagraphStyle("hucre", fontName="BelgeSerif", fontSize=8.5, leading=10.5)
    kalin = ParagraphStyle("kalin", parent=hucre, fontName="BelgeSerif-Kalin", textColor=colors.white)
    ust = ParagraphStyle("ust", fontName="BelgeSerif-Kalin", fontSize=14, leading=18, spaceAfter=8)
    akis = [Paragraph(escape(baslik), ust)]
    for i, s in enumerate(sayfalar):
        if i:
            akis.append(PageBreak())
        if len(sayfalar) > 1:
            akis.append(Paragraph(escape(str(s.get("ad") or "")), ParagraphStyle("alt", parent=ust, fontSize=11)))
        veri = [[Paragraph(escape(str(b)), kalin) for b in s.get("basliklar", [])]]
        veri += [[Paragraph(escape("" if h is None else str(h)), hucre) for h in r] for r in s.get("satirlar", [])]
        t = Table(veri, repeatRows=1)
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0E5A4E")),
            ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#C9C3B6")),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F7F5F0")]),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        akis += [t, Spacer(1, 6)]
    cikti = io.BytesIO()
    SimpleDocTemplate(cikti, pagesize=landscape(A4), leftMargin=1.5 * cm, rightMargin=1.5 * cm, topMargin=1.5 * cm,
                      bottomMargin=1.5 * cm, title=baslik, author="Hukuk ve Avukat Portalı").build(akis)
    return cikti.getvalue()
