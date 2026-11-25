-- Kendi kendine kayıtta e-posta doğrulaması. Davetle gelen hesaplar (davet e-postası adresi zaten doğrular) ve
-- önceki hesaplar doğrulanmış sayılır; kayıtta sunucu hesabı açtığı işlemde doğrulamayı başlatır. Doğrulanmamış
-- hesap şifresi doğru olsa da oturum açamaz (bu bilgi yalnızca şifre doğruysa verilir; hesap varlığı sızmaz).
BEGIN;

ALTER TABLE hukuk.kullanici ADD COLUMN eposta_dogrulandi timestamptz DEFAULT now();

CREATE TABLE hukuk.eposta_dogrulama (
  kod_ozeti      char(64) PRIMARY KEY,
  eposta         text NOT NULL,
  olusturma      timestamptz NOT NULL DEFAULT now(),
  son_gecerlilik timestamptz NOT NULL DEFAULT now() + interval '48 hours',
  kullanildi     timestamptz
);
CREATE INDEX eposta_dogrulama_eposta ON hukuk.eposta_dogrulama (eposta, olusturma DESC);
ALTER TABLE hukuk.eposta_dogrulama ENABLE ROW LEVEL SECURITY;  -- politika yok: yalnızca fonksiyonlarla

-- İç yardımcı: kodu kaydeder ve e-postayı kuyruğa yazar (saatte 3 sınırı aşılmışsa hiçbir şey yapmaz).
CREATE FUNCTION hukuk._dogrulama_gonder(p_eposta text, p_kod_ozeti char(64), p_konu text, p_metin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF (SELECT count(*) FROM hukuk.eposta_dogrulama WHERE eposta = p_eposta AND olusturma > now() - interval '1 hour') >= 3 THEN
    RETURN;
  END IF;
  INSERT INTO hukuk.eposta_dogrulama (kod_ozeti, eposta) VALUES (p_kod_ozeti, p_eposta);
  PERFORM hukuk.eposta_ekle(NULL, p_eposta, p_konu, p_metin, 'epostaDogrulama');
END $$;
REVOKE ALL ON FUNCTION hukuk._dogrulama_gonder(text, char, text, text) FROM PUBLIC;

-- Kayıttan hemen sonra (aynı işlemde): yeni hesabı doğrulanmamış yapar ve doğrulama e-postasını gönderir.
CREATE FUNCTION hukuk.eposta_dogrulama_baslat(p_kullanici uuid, p_kod_ozeti char(64), p_konu text, p_metin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text;
BEGIN
  -- Yalnızca az önce açılmış ve henüz oturum açmamış hesap için (eski hesapları kilitlemek için kullanılamaz).
  UPDATE hukuk.kullanici u SET eposta_dogrulandi = NULL
  WHERE u.id = p_kullanici AND u.olusturma > now() - interval '5 minutes'
    AND NOT EXISTS (SELECT 1 FROM hukuk.oturum o WHERE o.kullanici_id = u.id)
  RETURNING lower(u.eposta) INTO v_eposta;
  IF v_eposta IS NULL THEN
    RAISE EXCEPTION 'Doğrulama yalnızca yeni açılan hesap için başlatılabilir.' USING ERRCODE = '42501';
  END IF;
  PERFORM hukuk._dogrulama_gonder(v_eposta, p_kod_ozeti, p_konu, p_metin);
END $$;

-- Bağlantıdaki kodla doğrular; aynı e-postanın doğrulanmamış tüm hesapları doğrulanır. Dönen: hesap sayısı.
CREATE FUNCTION hukuk.eposta_dogrula(p_kod_ozeti char(64)) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text;
  v_sayi integer;
BEGIN
  UPDATE hukuk.eposta_dogrulama SET kullanildi = now()
  WHERE kod_ozeti = p_kod_ozeti AND kullanildi IS NULL AND son_gecerlilik > now()
  RETURNING eposta INTO v_eposta;
  IF v_eposta IS NULL THEN
    RAISE EXCEPTION 'Doğrulama bağlantısı geçersiz ya da süresi dolmuş. Girişte yeni bağlantı isteyebilirsiniz.'
      USING ERRCODE = '22023';
  END IF;
  UPDATE hukuk.kullanici SET eposta_dogrulandi = now() WHERE lower(eposta) = v_eposta AND eposta_dogrulandi IS NULL;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

-- Yeni bağlantı: yalnızca doğrulanmamış aktif hesap varsa gönderilir; yanıt her durumda aynı.
CREATE FUNCTION hukuk.eposta_dogrulama_yenile(p_eposta text, p_kod_ozeti char(64), p_konu text, p_metin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text := lower(trim(p_eposta));
BEGIN
  IF EXISTS (SELECT 1 FROM hukuk.kullanici WHERE lower(eposta) = v_eposta AND aktif AND eposta_dogrulandi IS NULL) THEN
    PERFORM hukuk._dogrulama_gonder(v_eposta, p_kod_ozeti, p_konu, p_metin);
  END IF;
END $$;

CREATE FUNCTION hukuk.eposta_dogrulandi_mi(p_kullanici uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT eposta_dogrulandi IS NOT NULL FROM hukuk.kullanici WHERE id = p_kullanici
$$;

REVOKE ALL ON FUNCTION hukuk.eposta_dogrulama_baslat(uuid, char, text, text), hukuk.eposta_dogrula(char),
  hukuk.eposta_dogrulama_yenile(text, char, text, text), hukuk.eposta_dogrulandi_mi(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.eposta_dogrulama_baslat(uuid, char, text, text), hukuk.eposta_dogrula(char),
  hukuk.eposta_dogrulama_yenile(text, char, text, text), hukuk.eposta_dogrulandi_mi(uuid) TO hukuk_uygulama;

COMMIT;
