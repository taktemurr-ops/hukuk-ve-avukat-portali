-- Müvekkil portalı. Portal oturumunda app.kiraci_id ayarlanmaz; büro tablolarının satır politikaları hiçbir şey
-- döndürmez. Müvekkil yalnızca aşağıdaki SECURITY DEFINER fonksiyonlarıyla, kendi kişi kartının müvekkil olduğu ve
-- büronun portalda paylaştığı dosyalara erişir.

CREATE TABLE hukuk.portal_paylasim (
  dosya_id  uuid PRIMARY KEY REFERENCES hukuk.dosya(id),
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  paylasan  uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  zaman     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hukuk.belge ADD COLUMN portalda boolean NOT NULL DEFAULT false;

CREATE TABLE hukuk.portal_mesaj (
  id              bigserial PRIMARY KEY,
  kiraci_id       uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id        uuid NOT NULL REFERENCES hukuk.dosya(id),
  gonderen        uuid NOT NULL,
  muvekkilden     boolean NOT NULL,
  metin           text NOT NULL CHECK (length(trim(metin)) BETWEEN 1 AND 5000),
  zaman           timestamptz NOT NULL DEFAULT now(),
  okundu          timestamptz
);
CREATE INDEX portal_mesaj_dosya ON hukuk.portal_mesaj (dosya_id, id);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['portal_paylasim', 'portal_mesaj'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY dosya_uzerinden ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci() AND '
                   'EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id)) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id))', t);
  END LOOP;
END $$;
GRANT SELECT, INSERT, DELETE ON hukuk.portal_paylasim TO hukuk_uygulama;
GRANT SELECT, INSERT ON hukuk.portal_mesaj TO hukuk_uygulama;
GRANT UPDATE (okundu) ON hukuk.portal_mesaj TO hukuk_uygulama;
GRANT UPDATE (portalda) ON hukuk.belge TO hukuk_uygulama;
GRANT USAGE ON SEQUENCE hukuk.portal_mesaj_id_seq TO hukuk_uygulama;

-- Portal oturumunun kişisi ve kullanıcısı (sunucu her portal işleminde ayarlar).
CREATE FUNCTION hukuk.portal_kisi() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.portal_kisi', true), '')::uuid $$;

-- Müvekkil bu dosyayı görebilir mi: dosya paylaşılmış, kişisi dosyada müvekkil, kullanıcı aktif ve aynı kurumda.
CREATE FUNCTION hukuk.portal_erisim(p_dosya uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT hukuk.portal_kisi() IS NOT NULL AND EXISTS (
    SELECT 1 FROM hukuk.portal_paylasim p
    JOIN hukuk.dosya_taraf t ON t.dosya_id = p.dosya_id AND t.sifat = 'muvekkil' AND t.kisi_id = hukuk.portal_kisi()
    JOIN hukuk.kullanici u ON u.id = hukuk.aktif_kullanici() AND u.kiraci_id = p.kiraci_id AND u.aktif
                          AND u.kisi_id = hukuk.portal_kisi()
    WHERE p.dosya_id = p_dosya)
$$;

CREATE FUNCTION hukuk.portal_dosyalari()
RETURNS TABLE (id uuid, ic_no text, tur text, baslik text, asama text, acilis date, kapanis date, sorumlu text,
               sonraki_durusma timestamptz, sonraki_durusma_yeri text, okunmamis integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT d.id, d.ic_no, d.tur, d.baslik, d.asama, d.acilis, d.kapanis, s.ad_soyad,
         du.baslangic, du.yer,
         (SELECT count(*) FROM hukuk.portal_mesaj m WHERE m.dosya_id = d.id AND NOT m.muvekkilden AND m.okundu IS NULL)::integer
  FROM hukuk.dosya d
  JOIN hukuk.kullanici s ON s.id = d.sorumlu
  LEFT JOIN LATERAL (SELECT x.baslangic, x.yer FROM hukuk.durusma x WHERE x.dosya_id = d.id AND x.baslangic > now()
                     ORDER BY x.baslangic LIMIT 1) du ON true
  WHERE hukuk.portal_erisim(d.id)
  ORDER BY d.acilis DESC
$$;

CREATE FUNCTION hukuk.portal_belgeleri(p_dosya uuid)
RETURNS TABLE (id uuid, ad text, tur text, no integer, sha256 text, boyut bigint, dosya_adi text, zaman timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT b.id, b.ad, b.tur, s.no, s.sha256, s.boyut, s.dosya_adi, s.zaman
  FROM hukuk.belge b
  JOIN LATERAL (SELECT * FROM hukuk.belge_surum x WHERE x.belge_id = b.id ORDER BY x.no DESC LIMIT 1) s ON true
  WHERE b.dosya_id = p_dosya AND b.portalda AND NOT b.gizli AND hukuk.portal_erisim(p_dosya)
  ORDER BY s.zaman DESC
$$;

-- İndirme için yalnızca paylaşılmış belgenin son sürümü.
CREATE FUNCTION hukuk.portal_belge_icerigi(p_belge uuid)
RETURNS TABLE (depo_anahtari text, sha256 text, dosya_adi text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT s.depo_anahtari, s.sha256, s.dosya_adi
  FROM hukuk.belge b
  JOIN LATERAL (SELECT * FROM hukuk.belge_surum x WHERE x.belge_id = b.id ORDER BY x.no DESC LIMIT 1) s ON true
  WHERE b.id = p_belge AND b.portalda AND NOT b.gizli AND hukuk.portal_erisim(b.dosya_id)
$$;

CREATE FUNCTION hukuk.portal_mesajlari(p_dosya uuid)
RETURNS TABLE (id bigint, muvekkilden boolean, gonderen text, metin text, zaman timestamptz, okundu timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT m.id, m.muvekkilden, u.ad_soyad, m.metin, m.zaman, m.okundu
  FROM hukuk.portal_mesaj m JOIN hukuk.kullanici u ON u.id = m.gonderen
  WHERE m.dosya_id = p_dosya AND hukuk.portal_erisim(p_dosya)
  ORDER BY m.id
$$;

CREATE FUNCTION hukuk.portal_mesaj_gonder(p_dosya uuid, p_metin text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  yeni bigint;
BEGIN
  IF NOT hukuk.portal_erisim(p_dosya) THEN
    RAISE EXCEPTION 'Dosya bulunamadı' USING ERRCODE = 'no_data_found';
  END IF;
  -- Kötüye kullanıma karşı: dosya başına saatte en fazla 30 mesaj.
  IF (SELECT count(*) FROM hukuk.portal_mesaj WHERE dosya_id = p_dosya AND muvekkilden AND zaman > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Çok sayıda mesaj gönderildi; lütfen daha sonra tekrar deneyin' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO hukuk.portal_mesaj (kiraci_id, dosya_id, gonderen, muvekkilden, metin)
  SELECT d.kiraci_id, d.id, hukuk.aktif_kullanici(), true, trim(p_metin) FROM hukuk.dosya d WHERE d.id = p_dosya
  RETURNING id INTO yeni;
  RETURN yeni;
END $$;

-- Müvekkil, büronun mesajlarını okudu.
CREATE FUNCTION hukuk.portal_mesajlari_oku(p_dosya uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.portal_mesaj SET okundu = now()
  WHERE dosya_id = p_dosya AND NOT muvekkilden AND okundu IS NULL AND hukuk.portal_erisim(p_dosya)
$$;

GRANT EXECUTE ON FUNCTION hukuk.portal_kisi(), hukuk.portal_erisim(uuid), hukuk.portal_dosyalari(),
  hukuk.portal_belgeleri(uuid), hukuk.portal_belge_icerigi(uuid), hukuk.portal_mesajlari(uuid),
  hukuk.portal_mesaj_gonder(uuid, text), hukuk.portal_mesajlari_oku(uuid) TO hukuk_uygulama;

-- Portal kullanıcısının kendi bilgileri.
CREATE FUNCTION hukuk.portal_ben()
RETURNS TABLE (ad_soyad text, eposta text, kurum text, hesap_turu text, kisi_adi text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT u.ad_soyad, u.eposta, k.ad, k.hesap_turu, p.ad
  FROM hukuk.kullanici u JOIN hukuk.kiraci k ON k.id = u.kiraci_id JOIN hukuk.kisi p ON p.id = u.kisi_id
  WHERE u.id = hukuk.aktif_kullanici() AND u.kisi_id = hukuk.portal_kisi() AND u.aktif
$$;
GRANT EXECUTE ON FUNCTION hukuk.portal_ben() TO hukuk_uygulama;
