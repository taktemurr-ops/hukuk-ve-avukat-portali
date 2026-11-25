-- Abonelik ödemesi (sağlayıcıdan bağımsız). Abonelik yalnızca doğrulanmış ödeme bildirimiyle değişir;
-- uygulama rolü abonelik satırını doğrudan yazamaz.

REVOKE INSERT, UPDATE ON hukuk.abonelik FROM hukuk_uygulama;

CREATE TABLE hukuk.odeme (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  saglayici     text NOT NULL,
  -- Sağlayıcıya gönderilen ve bildirimde geri gelen referans (tahmin edilemez, tekil).
  referans      text NOT NULL UNIQUE CHECK (length(referans) >= 20),
  saglayici_islem_no text,
  donem         text NOT NULL CHECK (donem IN ('aylik', 'yillik')),
  koltuk        integer NOT NULL CHECK (koltuk >= 1),
  matrah_kurus  bigint NOT NULL CHECK (matrah_kurus > 0),
  kdv_kurus     bigint NOT NULL CHECK (kdv_kurus >= 0),
  toplam_kurus  bigint NOT NULL CHECK (toplam_kurus = matrah_kurus + kdv_kurus),
  durum         text NOT NULL DEFAULT 'baslatildi' CHECK (durum IN ('baslatildi', 'basarili', 'basarisiz')),
  hata          text,
  baslatan      uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  olusturma     timestamptz NOT NULL DEFAULT now(),
  sonuclanma    timestamptz,
  CHECK ((durum = 'baslatildi') = (sonuclanma IS NULL))
);
CREATE UNIQUE INDEX odeme_saglayici_islem ON hukuk.odeme (saglayici, saglayici_islem_no) WHERE saglayici_islem_no IS NOT NULL;
ALTER TABLE hukuk.odeme ENABLE ROW LEVEL SECURITY;
CREATE POLICY odeme_okuma ON hukuk.odeme FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
-- Ödemeyi yalnızca yönetici başlatır; sonucu yalnızca bildirim fonksiyonu yazar.
CREATE POLICY odeme_baslatma ON hukuk.odeme FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND durum = 'baslatildi'
              AND baslatan = hukuk.aktif_kullanici());
GRANT SELECT, INSERT ON hukuk.odeme TO hukuk_uygulama;

-- Günlük işi beklemeden geçerli durum: deneme bitti → askıda; ödeme 7 günden fazla gecikti → askıda;
-- dönem sonunda iptal → iptal; aktif dönem bitti ve yenilenmedi → ödeme bekliyor (7 gün), sonra askıda.
CREATE FUNCTION hukuk.abonelik_etkin_durum(a hukuk.abonelik) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN a.durum = 'deneme' AND a.donem_sonu <= current_date THEN 'askida'
    WHEN a.durum = 'odemeBekliyor' AND a.ilk_basarisiz IS NOT NULL AND current_date - a.ilk_basarisiz > 7 THEN 'askida'
    WHEN a.durum = 'aktif' AND a.donem_sonunda_iptal AND a.donem_sonu <= current_date THEN 'iptal'
    WHEN a.durum = 'aktif' AND a.donem_sonu < current_date - 7 THEN 'askida'
    WHEN a.durum = 'aktif' AND a.donem_sonu < current_date THEN 'odemeBekliyor'
    ELSE a.durum
  END
$$;

-- Oturumdaki kurumun aboneliği (okuma).
CREATE FUNCTION hukuk.abonelik_bilgisi()
RETURNS TABLE (durum text, etkin_durum text, donem text, donem_basi date, donem_sonu date, ucretli_koltuk integer,
               donem_sonunda_iptal boolean, hesap_turu text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT a.durum, hukuk.abonelik_etkin_durum(a), a.donem, a.donem_basi, a.donem_sonu, a.ucretli_koltuk,
         a.donem_sonunda_iptal, k.hesap_turu
  FROM hukuk.abonelik a JOIN hukuk.kiraci k ON k.id = a.kiraci_id
  WHERE a.kiraci_id = hukuk.aktif_kiraci()
$$;

-- Yazma izni: askıda veya iptal edilmiş hesapta veriler salt okunur (silinmez, dışa aktarılabilir).
-- Aboneliği olmayan kurum (eski kayıt) yazabilir sayılır.
CREATE FUNCTION hukuk.abonelik_yazilabilir(p_kiraci uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT coalesce((SELECT hukuk.abonelik_etkin_durum(a) NOT IN ('askida', 'iptal')
                   FROM hukuk.abonelik a WHERE a.kiraci_id = p_kiraci), true)
$$;

-- Dönem sonunda iptal (yönetici); o güne kadar kullanım sürer.
CREATE FUNCTION hukuk.abonelik_iptal(p_iptal boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Aboneliği yalnızca yöneticiler değiştirebilir' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE hukuk.abonelik SET donem_sonunda_iptal = p_iptal WHERE kiraci_id = hukuk.aktif_kiraci();
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (hukuk.aktif_kiraci(), hukuk.aktif_kullanici(), 'degisiklik', 'abonelik', hukuk.aktif_kiraci()::text,
          CASE WHEN p_iptal THEN 'Dönem sonunda iptal istendi' ELSE 'İptal isteği geri alındı' END, '', '');
END $$;

-- Sağlayıcı bildirimi (imzası uygulama sunucusunda doğrulandıktan sonra, oturumsuz çağrılır).
-- Tek seferlik: sonuçlanmış ödeme tekrar işlenmez. Tutar kayıtla uyuşmazsa ödeme başarısız sayılır.
CREATE FUNCTION hukuk.odeme_sonuclandi(p_referans text, p_basarili boolean, p_tutar_kurus bigint,
                                       p_islem_no text, p_hata text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  o hukuk.odeme%ROWTYPE;
  a hukuk.abonelik%ROWTYPE;
  bas date;
  v_basarili boolean := p_basarili;
  v_hata text := p_hata;
BEGIN
  SELECT * INTO o FROM hukuk.odeme WHERE referans = p_referans FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ödeme bulunamadı' USING ERRCODE = 'no_data_found';
  END IF;
  IF o.durum <> 'baslatildi' THEN
    RETURN o.durum;  -- tekrar gelen bildirim
  END IF;
  IF v_basarili AND p_tutar_kurus IS DISTINCT FROM o.toplam_kurus THEN
    v_basarili := false;
    v_hata := 'Tutar uyuşmazlığı: beklenen ' || o.toplam_kurus || ', bildirilen ' || coalesce(p_tutar_kurus::text, '-');
  END IF;
  UPDATE hukuk.odeme SET durum = CASE WHEN v_basarili THEN 'basarili' ELSE 'basarisiz' END, sonuclanma = now(),
         saglayici_islem_no = p_islem_no, hata = CASE WHEN v_basarili THEN NULL ELSE coalesce(v_hata, 'Ödeme başarısız') END
  WHERE id = o.id;

  SELECT * INTO a FROM hukuk.abonelik WHERE kiraci_id = o.kiraci_id FOR UPDATE;
  IF v_basarili THEN
    -- Yeni dönem: denemede bugünden; aksi hâlde mevcut dönem bitmediyse onun sonundan, bittiyse bugünden.
    bas := CASE WHEN NOT FOUND OR a.durum = 'deneme' OR a.donem_sonu <= current_date THEN current_date ELSE a.donem_sonu END;
    INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu, ucretli_koltuk)
    VALUES (o.kiraci_id, 'aktif', o.donem, bas,
            bas + CASE WHEN o.donem = 'yillik' THEN interval '12 months' ELSE interval '1 month' END, o.koltuk)
    ON CONFLICT (kiraci_id) DO UPDATE SET durum = 'aktif', donem = excluded.donem, donem_basi = excluded.donem_basi,
      donem_sonu = excluded.donem_sonu, ucretli_koltuk = excluded.ucretli_koltuk, ilk_basarisiz = NULL,
      donem_sonunda_iptal = false;
  ELSIF FOUND AND a.durum IN ('aktif', 'odemeBekliyor') THEN
    UPDATE hukuk.abonelik SET durum = 'odemeBekliyor', ilk_basarisiz = coalesce(ilk_basarisiz, current_date)
    WHERE kiraci_id = o.kiraci_id;
  END IF;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (o.kiraci_id, o.baslatan, 'degisiklik', 'odeme', o.id::text,
          CASE WHEN v_basarili THEN 'Ödeme alındı: ' || o.toplam_kurus || ' kuruş' ELSE 'Ödeme başarısız: ' || coalesce(v_hata, '') END,
          '', '');
  RETURN CASE WHEN v_basarili THEN 'basarili' ELSE 'basarisiz' END;
END $$;

GRANT EXECUTE ON FUNCTION hukuk.abonelik_etkin_durum(hukuk.abonelik), hukuk.abonelik_bilgisi(),
  hukuk.abonelik_yazilabilir(uuid), hukuk.abonelik_iptal(boolean),
  hukuk.odeme_sonuclandi(text, boolean, bigint, text, text) TO hukuk_uygulama;
