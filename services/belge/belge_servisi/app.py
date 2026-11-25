"""HTTP arayüzü. Uygulama sunucusu (Serverpod) bu servisi iç ağdan çağırır; dışarıya açılmaz."""

from __future__ import annotations

from urllib.parse import quote

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from .cikarim import metin_cikar, ocr_var
from .docx_uret import docx_uret, eksik_alanlar
from .guvenlik import AZAMI_BOYUT, BelgeHatasi
from .tablo import tablo_oku

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


class DocxIstegi(BaseModel):
    baslik: str = Field(min_length=1, max_length=200)
    metin: str = Field(min_length=1, max_length=500_000)
    eksikVarsaReddet: bool = False


@app.post("/docx")
def docx(istek: DocxIstegi) -> Response:
    eksik = eksik_alanlar(istek.metin)
    if eksik and istek.eksikVarsaReddet:
        raise HTTPException(status_code=422, detail={"mesaj": "Eksik alanlar var.", "alanlar": eksik})
    veri = docx_uret(istek.baslik, istek.metin)
    ad = quote(f"{istek.baslik}.docx")
    return Response(
        content=veri,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{ad}", "X-Eksik-Alan-Sayisi": str(len(eksik))},
    )
