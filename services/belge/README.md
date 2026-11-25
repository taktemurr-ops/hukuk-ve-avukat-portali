# Belge servisi

Uygulama sunucusunun iç ağdan çağırdığı Python servisi:

| Uç | Ne yapar |
| --- | --- |
| `GET /saglik` | Durum ve OCR (Türkçe Tesseract) var mı |
| `POST /metin` | PDF, Word (.docx), UDF, görüntü veya düz metinden metin çıkarır; taranmış PDF ve görüntüde Türkçe OCR yapar. SHA-256 özetini de döner |
| `POST /docx` | Şablon motorunun ürettiği metinden Word belgesi üretir; `[EKSİK: alan]` işaretlerini sarı vurgular, istenirse eksik alan varken reddeder |

Güvenlik: 25 MB sınırı, uzantıya değil içeriğe bakarak tür tespiti, şifreli ve aşırı sıkıştırılmış (zip bombası) dosyaların reddi, root olmayan kullanıcıyla çalışma. Servis dışarıya bağlanmaz; yapay zekâ modeli eklendiğinde o da Türkiye'deki sunucuda çalışacak.

UDF (UYAP Doküman Editörü) okuma `content.xml` içeriğine dayanır; gerçek UYAP dosyalarıyla doğrulanmalıdır.

## Çalıştırma

```bash
cd services/belge
pip install -r requirements-test.txt
python -m pytest -q          # 13 test
uvicorn belge_servisi.app:app --port 8090
```

Docker: `docker build -t hukuk-belge . && docker run -p 8090:8090 hukuk-belge`
