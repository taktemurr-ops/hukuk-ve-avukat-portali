-- Giden e-posta kuyruğu (outbox). İşlemle aynı veritabanı işleminde yazılır; ayrı bir görev gönderir ve
-- başarısızlıkta artan aralıklarla yeniden dener. İçerik (davet bağlantısı gibi) gönderimden sonra silinir.
-- Uygulama rolü kuyruğu doğrudan okuyamaz; yalnızca aşağıdaki fonksiyonlarla çalışır.

CREATE TABLE hukuk.eposta_kuyrugu (
  id             bigserial PRIMARY KEY,
  kiraci_id      uuid REFERENCES hukuk.kiraci(id),
  alici          text NOT NULL CHECK (alici ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  konu           text NOT NULL CHECK (length(konu) BETWEEN 1 AND 200),
  metin          text NOT NULL,
  tur            text NOT NULL,
  durum          text NOT NULL DEFAULT 'bekliyor' CHECK (durum IN ('bekliyor', 'gonderiliyor', 'gonderildi', 'hata')),
  deneme         integer NOT NULL DEFAULT 0,
  son_hata       text,
  olusturma      timestamptz NOT NULL DEFAULT now(),
  sonraki_deneme timestamptz NOT NULL DEFAULT now(),
  gonderim       timestamptz
);
CREATE INDEX eposta_kuyrugu_bekleyen ON hukuk.eposta_kuyrugu (sonraki_deneme) WHERE durum IN ('bekliyor', 'gonderiliyor');
ALTER TABLE hukuk.eposta_kuyrugu ENABLE ROW LEVEL SECURITY;  -- politika yok: doğrudan erişim kapalı

CREATE FUNCTION hukuk.eposta_ekle(p_kiraci uuid, p_alici text, p_konu text, p_metin text, p_tur text) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  INSERT INTO hukuk.eposta_kuyrugu (kiraci_id, alici, konu, metin, tur)
  VALUES (p_kiraci, lower(trim(p_alici)), p_konu, p_metin, p_tur) RETURNING id
$$;

-- Gönderici görev: sırası gelen en fazla p_adet iletiyi alır. 10 dakikadan uzun "gönderiliyor"da kalan
-- (çöken görev) tekrar alınır. Aynı anda birden çok görev çalışabilir (SKIP LOCKED).
CREATE FUNCTION hukuk.eposta_al(p_adet integer)
RETURNS TABLE (id bigint, alici text, konu text, metin text)
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.eposta_kuyrugu q SET durum = 'gonderiliyor', deneme = q.deneme + 1, sonraki_deneme = now() + interval '10 minutes'
  WHERE q.id IN (SELECT x.id FROM hukuk.eposta_kuyrugu x
                 WHERE x.durum IN ('bekliyor', 'gonderiliyor') AND x.sonraki_deneme <= now()
                 ORDER BY x.sonraki_deneme LIMIT p_adet FOR UPDATE SKIP LOCKED)
  RETURNING q.id, q.alici, q.konu, q.metin
$$;

-- Sonuç: başarıda içerik silinir; hatada 5, 30, 120, 480 dakika sonra yeniden denenir; 5. denemeden sonra "hata".
CREATE FUNCTION hukuk.eposta_sonuc(p_id bigint, p_basarili boolean, p_hata text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.eposta_kuyrugu SET
    durum = CASE WHEN p_basarili THEN 'gonderildi' WHEN deneme >= 5 THEN 'hata' ELSE 'bekliyor' END,
    gonderim = CASE WHEN p_basarili THEN now() END,
    metin = CASE WHEN p_basarili THEN '' ELSE metin END,
    son_hata = CASE WHEN p_basarili THEN NULL ELSE left(p_hata, 500) END,
    sonraki_deneme = now() + (CASE deneme WHEN 1 THEN 5 WHEN 2 THEN 30 WHEN 3 THEN 120 ELSE 480 END) * interval '1 minute'
  WHERE id = p_id AND durum = 'gonderiliyor'
$$;

GRANT EXECUTE ON FUNCTION hukuk.eposta_ekle(uuid, text, text, text, text), hukuk.eposta_al(integer),
  hukuk.eposta_sonuc(bigint, boolean, text) TO hukuk_uygulama;
