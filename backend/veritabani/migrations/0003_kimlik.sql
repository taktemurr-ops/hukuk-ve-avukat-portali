-- Giriş, oturum ve hatalı deneme kilidi. Bu fonksiyonlar kiracı bağlamı olmadan çağrılır (girişten önce),
-- bu yüzden SECURITY DEFINER'dır ve yalnızca gereken en az bilgiyi döner.
BEGIN;

CREATE TABLE hukuk.oturum (
  token_ozeti  char(64) PRIMARY KEY,
  kullanici_id uuid NOT NULL REFERENCES hukuk.kullanici(id),
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  olusturma    timestamptz NOT NULL DEFAULT now(),
  son_kullanma timestamptz NOT NULL,
  iptal        timestamptz,
  istemci      text NOT NULL DEFAULT ''
);

CREATE TABLE hukuk.giris_denemesi (
  eposta  text NOT NULL,
  zaman   timestamptz NOT NULL DEFAULT now(),
  basarili boolean NOT NULL
);
CREATE INDEX giris_denemesi_eposta ON hukuk.giris_denemesi (lower(eposta), zaman DESC);

ALTER TABLE hukuk.oturum ENABLE ROW LEVEL SECURITY;
CREATE POLICY kendi_oturumlari ON hukuk.oturum USING (kullanici_id = hukuk.aktif_kullanici());
ALTER TABLE hukuk.giris_denemesi ENABLE ROW LEVEL SECURITY;  -- uygulama doğrudan erişemez; politika yok

-- Son 15 dakikada (son başarılı girişten sonra) 5 hatalı deneme varsa hesap kilitlidir.
CREATE FUNCTION hukuk.giris_kilitli(p_eposta text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT count(*) >= 5 FROM hukuk.giris_denemesi g
  WHERE lower(g.eposta) = lower(p_eposta) AND NOT g.basarili AND g.zaman > now() - interval '15 minutes'
    AND g.zaman > coalesce((SELECT max(zaman) FROM hukuk.giris_denemesi b
                            WHERE lower(b.eposta) = lower(p_eposta) AND b.basarili), '-infinity')
$$;

CREATE FUNCTION hukuk.giris_denemesi_kaydet(p_eposta text, p_basarili boolean) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  INSERT INTO hukuk.giris_denemesi (eposta, basarili) VALUES (lower(p_eposta), p_basarili)
$$;

-- E-postaya ait aktif hesaplar (aynı e-posta birden çok müşteride olabilir). Kilitliyse hiçbir şey dönmez.
CREATE FUNCTION hukuk.giris_adaylari(p_eposta text)
RETURNS TABLE (kullanici_id uuid, kiraci_id uuid, kiraci_adi text, sifre_ozeti text, iki_adimli boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT u.id, u.kiraci_id, k.ad, u.sifre_ozeti, u.iki_adimli
  FROM hukuk.kullanici u JOIN hukuk.kiraci k ON k.id = u.kiraci_id
  WHERE lower(u.eposta) = lower(p_eposta) AND u.aktif AND NOT hukuk.giris_kilitli(p_eposta)
$$;

-- Oturum açar; token'ın yalnızca SHA-256 özeti saklanır.
CREATE FUNCTION hukuk.oturum_ac(p_token_ozeti char(64), p_kullanici uuid, p_sure interval, p_istemci text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  INSERT INTO hukuk.oturum (token_ozeti, kullanici_id, kiraci_id, son_kullanma, istemci)
  SELECT p_token_ozeti, u.id, u.kiraci_id, now() + p_sure, coalesce(p_istemci, '')
  FROM hukuk.kullanici u WHERE u.id = p_kullanici AND u.aktif
$$;

-- Geçerli oturumun kullanıcı ve kiracısı; süresi dolmuş, iptal edilmiş veya pasif kullanıcıda boş döner.
CREATE FUNCTION hukuk.oturum_coz(p_token_ozeti char(64)) RETURNS TABLE (kullanici_id uuid, kiraci_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT o.kullanici_id, o.kiraci_id
  FROM hukuk.oturum o JOIN hukuk.kullanici u ON u.id = o.kullanici_id
  WHERE o.token_ozeti = p_token_ozeti AND o.iptal IS NULL AND o.son_kullanma > now() AND u.aktif
$$;

CREATE FUNCTION hukuk.oturum_kapat(p_token_ozeti char(64)) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.oturum SET iptal = now() WHERE token_ozeti = p_token_ozeti AND iptal IS NULL
$$;

-- Ayrılan kullanıcının tüm oturumları anında kapanır.
CREATE FUNCTION hukuk.pasiflestirince_oturum_kapat() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF OLD.aktif AND NOT NEW.aktif THEN
    UPDATE hukuk.oturum SET iptal = now() WHERE kullanici_id = NEW.id AND iptal IS NULL;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pasiflestirince_oturum_kapat AFTER UPDATE OF aktif ON hukuk.kullanici
FOR EACH ROW EXECUTE FUNCTION hukuk.pasiflestirince_oturum_kapat();

GRANT SELECT ON hukuk.oturum TO hukuk_uygulama;
REVOKE ALL ON hukuk.giris_denemesi FROM hukuk_uygulama;
GRANT EXECUTE ON FUNCTION hukuk.giris_kilitli(text), hukuk.giris_denemesi_kaydet(text, boolean),
  hukuk.giris_adaylari(text), hukuk.oturum_ac(char, uuid, interval, text), hukuk.oturum_coz(char),
  hukuk.oturum_kapat(char) TO hukuk_uygulama;

COMMIT;
