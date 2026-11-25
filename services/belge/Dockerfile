# Belge servisi. Türkiye'deki sunucuda, yalnızca iç ağda çalışır; dışarıya ağ çağrısı yapmaz.
FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-tur poppler-utils \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 belge
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY belge_servisi ./belge_servisi

USER belge
EXPOSE 8090
CMD ["uvicorn", "belge_servisi.app:app", "--host", "0.0.0.0", "--port", "8090", "--workers", "2"]
