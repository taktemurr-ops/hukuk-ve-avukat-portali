-- Şifre sıfırlama. Bağlantıdaki kodun yalnızca SHA-256 özeti saklanır; kod 1 saat geçerli ve tek kullanımlıktır.
-- Aynı e-posta birden çok kurumda kayıtlıysa (giriş de e-postayla yapılır) sıfırlama hepsine uygulanır.
-- İstek, adres kayıtlı olsun olmasın aynı yanıtı alır (hesap varlığı sızdırılmaz); e-posta başına saatte 3 istek.
BEGIN;

CREATE TABLE hukuk.sifre_sifirlama (
  kod_ozeti      char(64) PRIMARY KEY,
  eposta         text NOT NULL,
  olusturma      timestamptz NOT NULL DEFAULT now(),
  son_gecerlilik timestamptz NOT NULL DEFAULT now() + interval '1 hour',
  kullanildi     timestamptz
);
CREATE INDEX sifre_sifirlama_eposta ON hukuk.sifre_sifirlama (eposta, olusturma DESC);
ALTER TABLE hukuk.sifre_sifirlama ENABLE ROW LEVEL SECURITY;  -- politika yok: yalnızca fonksiyonlarla

-- Metin bağlantıyı (kodu) içerir; kuyrukta gönderilince silinir. Hesap yoksa ya da sınır aşıldıysa sessizce hiçbir şey yapmaz.
CREATE FUNCTION hukuk.sifre_sifirlama_iste(p_eposta text, p_kod_ozeti char(64), p_konu text, p_metin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text := lower(trim(p_eposta));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hukuk.kullanici WHERE lower(eposta) = v_eposta AND aktif) THEN
    RETURN;
  END IF;
  IF (SELECT count(*) FROM hukuk.sifre_sifirlama WHERE eposta = v_eposta AND olusturma > now() - interval '1 hour') >= 3 THEN
    RETURN;
  END IF;
  -- Yeni istek eskilerini geçersiz kılar.
  UPDATE hukuk.sifre_sifirlama SET son_gecerlilik = now() WHERE eposta = v_eposta AND kullanildi IS NULL AND son_gecerlilik > now();
  INSERT INTO hukuk.sifre_sifirlama (kod_ozeti, eposta) VALUES (p_kod_ozeti, v_eposta);
  PERFORM hukuk.eposta_ekle(NULL, v_eposta, p_konu, p_metin, 'sifreSifirlama');
END $$;

-- Kodu doğrular, aktif hesapların şifresini değiştirir, tüm oturumları kapatır, giriş kilidini çözer ve her kurumun
-- denetim kaydına yazar. Dönen: değişen hesap sayısı. Geçersiz/süresi dolmuş/kullanılmış kodda hata.
CREATE FUNCTION hukuk.sifre_sifirla(p_kod_ozeti char(64), p_sifre_ozeti text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text;
  v_sayi integer;
  u record;
BEGIN
  UPDATE hukuk.sifre_sifirlama SET kullanildi = now()
  WHERE kod_ozeti = p_kod_ozeti AND kullanildi IS NULL AND son_gecerlilik > now()
  RETURNING eposta INTO v_eposta;
  IF v_eposta IS NULL THEN
    RAISE EXCEPTION 'Bağlantı geçersiz ya da süresi dolmuş. Yeniden şifre sıfırlama isteyin.' USING ERRCODE = '22023';
  END IF;
  UPDATE hukuk.kullanici SET sifre_ozeti = p_sifre_ozeti WHERE lower(eposta) = v_eposta AND aktif;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  UPDATE hukuk.oturum o SET iptal = now() FROM hukuk.kullanici k
  WHERE o.kullanici_id = k.id AND lower(k.eposta) = v_eposta AND o.iptal IS NULL;
  INSERT INTO hukuk.giris_denemesi (eposta, basarili) VALUES (v_eposta, true);  -- kilidi çözer
  FOR u IN SELECT id, kiraci_id FROM hukuk.kullanici WHERE lower(eposta) = v_eposta AND aktif LOOP
    INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
    VALUES (u.kiraci_id, u.id, 'degisiklik', 'kullanici', u.id::text, 'Şifre e-posta bağlantısıyla sıfırlandı', '', '');
  END LOOP;
  RETURN v_sayi;
END $$;

REVOKE ALL ON FUNCTION hukuk.sifre_sifirlama_iste(text, char, text, text), hukuk.sifre_sifirla(char, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.sifre_sifirlama_iste(text, char, text, text), hukuk.sifre_sifirla(char, text) TO hukuk_uygulama;

COMMIT;
