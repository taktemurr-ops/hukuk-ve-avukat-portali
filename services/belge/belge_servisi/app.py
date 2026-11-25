"""HTTP arayüzü. Uygulama sunucusu (Serverpod) bu servisi iç ağdan çağırır; dışarıya açılmaz."""

from __future__ import annotations

from urllib.parse import quote

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from .cikarim import metin_cikar, ocr_var
from .docx_uret import docx_uret, eksik_alanlar
from .guvenlik import AZAMI_BOYUT, BelgeHatasi
from .pdf_uret import pdf_uret
from .tablo import tablo_oku
from .tablo_uret import pdf_tablo_uret, xlsx_uret

app = FastAPI(title="Hukuk ve Avukat Portalı belge servisi", version="0.1.0")


@app.get("/saglik")
def saglik() -> dict:
    return {"durum": "ok", "ocr": ocr_var()}


@app.post("/metin")
async def metin(dosya: UploadFile = File(...)) -> dict:
    veri = await dosya.read(AZAMI_BOYUT + 1)
    try:
        return metin_cikar(veri, dosya.filename or "").sozluk()
    except BelgeHatasi as e:
        raise HTTPException(status_code=422, detail=str(e)) from e


@app.post("/tablo")
async def tablo(dosya: UploadFile = File(...)) -> dict:
    veri = await dosya.read(AZAMI_BOYUT + 1)
    try:
        return tablo_oku(veri, dosya.filename or "")
    except BelgeHatasi as e:
        raise HTTPException(status_code=422, detail=str(e)) from e


class RaporSayfasi(BaseModel):
    ad: str = Field(default="Rapor", max_length=100)
    basliklar: list[str] = Field(max_length=50)
    satirlar: list[list[str | float | int | None]]


class RaporIstegi(BaseModel):
    baslik: str = Field(min_length=1, max_length=200)
    sayfalar: list[RaporSayfasi] = Field(min_length=1, max_length=20)
    bicim: str = Field(default="xlsx", pattern="^(xlsx|pdf)$")


@app.post("/rapor")
def rapor(istek: RaporIstegi) -> Response:
    sayfalar = [s.model_dump() for s in istek.sayfalar]
    try:
        if istek.bicim == "pdf":
            veri, tur, uzanti = pdf_tablo_uret(istek.baslik, sayfalar), "application/pdf", "pdf"
        else:
            veri = xlsx_uret(istek.baslik, sayfalar)
            tur, uzanti = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"
    except BelgeHatasi as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    return Response(content=veri, media_type=tur,
                    headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(istek.baslik + '.' + uzanti)}"})


class DocxIstegi(BaseModel):
    baslik: str = Field(min_length=1, max_length=200)
    metin: str = Field(min_length=1, max_length=500_000)
    eksikVarsaReddet: bool = False
    # "docx" (Word, düzenlenebilir) ya da "pdf" (gönderime hazır, yazı tipi gömülü).
    bicim: str = Field(default="docx", pattern="^(docx|pdf)$")


@app.post("/docx")
def docx(istek: DocxIstegi) -> Response:
    eksik = eksik_alanlar(istek.metin)
    if eksik and istek.eksikVarsaReddet:
        raise HTTPException(status_code=422, detail={"mesaj": "Eksik alanlar var.", "alanlar": eksik})
    if istek.bicim == "pdf":
        try:
            veri = pdf_uret(istek.baslik, istek.metin)
        except BelgeHatasi as e:
            raise HTTPException(status_code=503, detail=str(e)) from e
        return Response(
            content=veri,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(istek.baslik + '.pdf')}",
                     "X-Eksik-Alan-Sayisi": str(len(eksik))},
        )
    veri = docx_uret(istek.baslik, istek.metin)
    ad = quote(f"{istek.baslik}.docx")
    return Response(
        content=veri,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{ad}", "X-Eksik-Alan-Sayisi": str(len(eksik))},
    )
