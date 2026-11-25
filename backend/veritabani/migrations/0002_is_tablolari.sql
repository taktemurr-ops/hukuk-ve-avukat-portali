-- Finans, zaman, sözleşme, talep, icra, uyum, davet ve abonelik tabloları.
BEGIN;

-- ---------------------------------------------------------------------------
-- Finans: müvekkil carisi ve emanet hesabı
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.cari_hareket (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  muvekkil_id uuid NOT NULL REFERENCES hukuk.kisi(id),
  dosya_id    uuid REFERENCES hukuk.dosya(id),
  tur         text NOT NULL CHECK (tur IN ('masrafAvansiAlindi', 'masrafYapildi', 'avansIadesi', 'ucretTahakkuku', 'ucretTahsilati')),
  tutar_kurus bigint NOT NULL CHECK (tutar_kurus > 0),
  tarih       date NOT NULL,
  aciklama    text NOT NULL,
  belge_no    text,
  olusturan   uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  zaman       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hukuk.emanet_hareket (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  muvekkil_id  uuid NOT NULL REFERENCES hukuk.kisi(id),
  dosya_id     uuid NOT NULL REFERENCES hukuk.dosya(id),
  tur          text NOT NULL CHECK (tur IN ('giris', 'muvekkileOdeme', 'mahsup')),
  tutar_kurus  bigint NOT NULL CHECK (tutar_kurus > 0),
  tarih        date NOT NULL,
  aciklama     text NOT NULL,
  mahsup_onayi text,
  olusturan    uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  CHECK (tur <> 'mahsup' OR coalesce(length(trim(mahsup_onayi)), 0) > 0)
);

-- Müvekkil parası hiçbir zaman eksiye düşmez (müvekkil + dosya bazında).
CREATE FUNCTION hukuk.emanet_bakiye_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  bakiye bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.muvekkil_id::text || NEW.dosya_id::text, 1));
  SELECT coalesce(sum(CASE WHEN tur = 'giris' THEN tutar_kurus ELSE -tutar_kurus END), 0) INTO bakiye
    FROM hukuk.emanet_hareket WHERE muvekkil_id = NEW.muvekkil_id AND dosya_id = NEW.dosya_id;
  IF NEW.tur <> 'giris' AND bakiye < NEW.tutar_kurus THEN
    RAISE EXCEPTION 'Emanet bakiyesi yetersiz (bakiye % kuruş, çıkış % kuruş)', bakiye, NEW.tutar_kurus
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER emanet_bakiye_kontrol BEFORE INSERT ON hukuk.emanet_hareket
FOR EACH ROW EXECUTE FUNCTION hukuk.emanet_bakiye_kontrol();

-- ---------------------------------------------------------------------------
-- Zaman kaydı
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.zaman_kaydi (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id        uuid NOT NULL REFERENCES hukuk.kiraci(id),
  kullanici_id     uuid NOT NULL,
  dosya_id         uuid NOT NULL REFERENCES hukuk.dosya(id),
  tarih            date NOT NULL CHECK (tarih <= current_date),
  dakika           integer NOT NULL CHECK (dakika BETWEEN 1 AND 1440),
  aciklama         text NOT NULL CHECK (length(trim(aciklama)) >= 5),
  saatlik_kurus    bigint NOT NULL CHECK (saatlik_kurus >= 0),
  faturalanabilir  boolean NOT NULL DEFAULT true,
  durum            text NOT NULL DEFAULT 'taslak' CHECK (durum IN ('taslak', 'onaylandi', 'faturalandi')),
  onaylayan        uuid,
  fatura_no        text,
  CHECK (onaylayan IS NULL OR onaylayan <> kullanici_id),
  CHECK (durum = 'taslak' OR onaylayan IS NOT NULL),
  CHECK (durum <> 'faturalandi' OR fatura_no IS NOT NULL),
  FOREIGN KEY (kiraci_id, kullanici_id) REFERENCES hukuk.kullanici (kiraci_id, id)
);

CREATE FUNCTION hukuk.zaman_kurallari() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  toplam integer;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.durum = 'faturalandi' THEN
    RAISE EXCEPTION 'Faturalanmış zaman kaydı değiştirilemez' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.durum <> 'taslak' THEN
      RAISE EXCEPTION 'Onaylanmış zaman kaydı silinemez' USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  SELECT coalesce(sum(dakika), 0) INTO toplam FROM hukuk.zaman_kaydi
   WHERE kullanici_id = NEW.kullanici_id AND tarih = NEW.tarih AND id <> NEW.id;
  IF toplam + NEW.dakika > 1440 THEN
    RAISE EXCEPTION 'Bir gün için toplam 24 saat aşılamaz' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER zaman_kurallari BEFORE INSERT OR UPDATE OR DELETE ON hukuk.zaman_kaydi
FOR EACH ROW EXECUTE FUNCTION hukuk.zaman_kurallari();

-- ---------------------------------------------------------------------------
-- Kurumsal: grup şirketleri, sözleşmeler, onay, hukuk talepleri
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.sirket (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  unvan         text NOT NULL,
  kisa_ad       text,
  vkn           text CHECK (vkn ~ '^[0-9]{10}$'),
  ana_sirket_id uuid REFERENCES hukuk.sirket(id),
  CHECK (ana_sirket_id IS NULL OR ana_sirket_id <> id)
);
CREATE UNIQUE INDEX sirket_vkn_tekil ON hukuk.sirket (kiraci_id, vkn) WHERE vkn IS NOT NULL;

CREATE TABLE hukuk.sozlesme (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id        uuid NOT NULL REFERENCES hukuk.kiraci(id),
  no               text NOT NULL,
  sirket_id        uuid REFERENCES hukuk.sirket(id),
  baslik           text NOT NULL,
  tur              text NOT NULL,
  karsi_taraf      text NOT NULL DEFAULT '',
  sorumlu          uuid NOT NULL,
  durum            text NOT NULL DEFAULT 'taslak'
                   CHECK (durum IN ('taslak', 'muzakere', 'onayda', 'imzada', 'yururlukte', 'sonaErdi', 'feshedildi')),
  baslangic        date,
  bitis            date,
  otomatik_yenileme boolean NOT NULL DEFAULT false,
  ihbar_gun        integer CHECK (ihbar_gun >= 0),
  bedel_kurus      bigint CHECK (bedel_kurus >= 0),
  para_birimi      char(3) NOT NULL DEFAULT 'TRY',
  tarama           jsonb,
  UNIQUE (kiraci_id, no),
  CHECK (bitis IS NULL OR baslangic IS NULL OR bitis >= baslangic),
  CHECK (durum <> 'yururlukte' OR baslangic IS NOT NULL)
);

CREATE TABLE hukuk.sozlesme_onay (
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  sozlesme_id uuid NOT NULL REFERENCES hukuk.sozlesme(id),
  tur_no      integer NOT NULL,
  adim_sira   integer NOT NULL,
  adim_kodu   text NOT NULL,
  kullanici_id uuid NOT NULL,
  karar       text NOT NULL CHECK (karar IN ('onay', 'ret', 'revizyon')),
  notu        text NOT NULL DEFAULT '',
  zaman       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sozlesme_id, tur_no, adim_sira),
  CHECK (karar = 'onay' OR length(trim(notu)) >= 5)
);
-- Aynı onay turunda bir kişi yalnızca bir adımı onaylayabilir.
CREATE UNIQUE INDEX sozlesme_onay_kisi ON hukuk.sozlesme_onay (sozlesme_id, tur_no, kullanici_id) WHERE karar = 'onay';

CREATE TABLE hukuk.hukuk_talebi (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  no           text NOT NULL,
  sirket_id    uuid REFERENCES hukuk.sirket(id),
  baslik       text NOT NULL,
  aciklama     text NOT NULL DEFAULT '',
  tur          text NOT NULL,
  oncelik      text NOT NULL CHECK (oncelik IN ('dusuk', 'normal', 'yuksek', 'acil')),
  talep_eden   text NOT NULL,
  birim        text NOT NULL,
  atanan       uuid,
  durum        text NOT NULL DEFAULT 'yeni'
               CHECK (durum IN ('yeni', 'atandi', 'bilgiBekleniyor', 'incelemede', 'onayda', 'tamamlandi', 'reddedildi')),
  sla_son_gun  date NOT NULL,
  olusturma    date NOT NULL DEFAULT current_date,
  kapanis      date,
  ret_gerekcesi text,
  sozlesme_id  uuid REFERENCES hukuk.sozlesme(id),
  UNIQUE (kiraci_id, no),
  CHECK (durum <> 'reddedildi' OR coalesce(length(trim(ret_gerekcesi)), 0) > 0),
  CHECK ((durum IN ('tamamlandi', 'reddedildi')) = (kapanis IS NOT NULL))
);

-- ---------------------------------------------------------------------------
-- İcra
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.icra_dosyasi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id       uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id        uuid NOT NULL REFERENCES hukuk.dosya(id),
  icra_dairesi    text NOT NULL,
  esas_no         text,
  borclu          text NOT NULL,
  takip_turu      text NOT NULL CHECK (takip_turu IN ('ilamsiz', 'kambiyo', 'kira', 'ilamli', 'rehin')),
  asil_kurus      bigint NOT NULL CHECK (asil_kurus > 0),
  temerrut        date NOT NULL,
  takip_tarihi    date NOT NULL,
  faiz_turu       text NOT NULL CHECK (faiz_turu IN ('yasal', 'avans', 'akdi')),
  durum           text NOT NULL DEFAULT 'takipAcildi',
  vekalet_kurus   bigint NOT NULL DEFAULT 0 CHECK (vekalet_kurus >= 0),
  CHECK (temerrut <= takip_tarihi)
);

CREATE TABLE hukuk.icra_tahsilat (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  icra_id       uuid NOT NULL REFERENCES hukuk.icra_dosyasi(id),
  tarih         date NOT NULL CHECK (tarih <= current_date),
  tutar_kurus   bigint NOT NULL CHECK (tutar_kurus > 0),
  aciklama      text NOT NULL DEFAULT ''
);

-- ---------------------------------------------------------------------------
-- Uyum: ihbar ve iç soruşturma (yalnızca soruşturma ekibi görür)
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.ihbar (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id       uuid NOT NULL REFERENCES hukuk.kiraci(id),
  takip_kodu_ozet char(64) NOT NULL,
  zaman           timestamptz NOT NULL DEFAULT now(),
  kanal           text NOT NULL,
  kategori        text NOT NULL,
  aciklama        text NOT NULL CHECK (length(trim(aciklama)) >= 20),
  anonim          boolean NOT NULL DEFAULT true,
  iletisim        text,
  ilgili_kisiler  uuid[] NOT NULL DEFAULT '{}',
  CHECK (NOT anonim OR iletisim IS NULL)
);

CREATE TABLE hukuk.sorusturma (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  ihbar_id  uuid NOT NULL UNIQUE REFERENCES hukuk.ihbar(id),
  sorumlu   uuid NOT NULL,
  ekip      uuid[] NOT NULL DEFAULT '{}',
  durum     text NOT NULL DEFAULT 'onInceleme'
            CHECK (durum IN ('onInceleme', 'sorusturma', 'raporlama', 'kapandi', 'reddedildi')),
  sonuc     text,
  sonuc_ozeti text,
  acilis    timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION hukuk.sorusturma_cikar_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  ilgili uuid[];
BEGIN
  SELECT ilgili_kisiler INTO ilgili FROM hukuk.ihbar WHERE id = NEW.ihbar_id;
  IF NEW.sorumlu = ANY (ilgili) OR NEW.ekip && ilgili THEN
    RAISE EXCEPTION 'İhbar edilen kişi soruşturmada yer alamaz' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER sorusturma_cikar_kontrol BEFORE INSERT OR UPDATE ON hukuk.sorusturma
FOR EACH ROW EXECUTE FUNCTION hukuk.sorusturma_cikar_kontrol();

-- İhbar içeriğini yalnızca soruşturmanın sorumlusu ve ekibi görür; soruşturması olmayan ihbarı yalnızca hukuk direktörü
-- (veya uyum sorumlusu) görür ki soruşturma açılabilsin.
CREATE FUNCTION hukuk.ihbar_gorunur(p_ihbar uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM hukuk.sorusturma s WHERE s.ihbar_id = p_ihbar) THEN
      EXISTS (SELECT 1 FROM hukuk.sorusturma s
              WHERE s.ihbar_id = p_ihbar
                AND (s.sorumlu = hukuk.aktif_kullanici() OR hukuk.aktif_kullanici() = ANY (s.ekip)))
    ELSE EXISTS (SELECT 1 FROM hukuk.kullanici_rol r
                 WHERE r.kullanici_id = hukuk.aktif_kullanici() AND r.rol IN ('hukukDirektoru', 'uyumSorumlusu'))
  END
$$;

-- ---------------------------------------------------------------------------
-- Davet ve abonelik
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.davet (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  eposta     text NOT NULL,
  roller     text[] NOT NULL CHECK (cardinality(roller) > 0),
  -- Bağlantıdaki kodun yalnızca özeti saklanır.
  kod_ozeti  char(64) NOT NULL UNIQUE,
  davet_eden uuid NOT NULL,
  olusturma  timestamptz NOT NULL DEFAULT now(),
  son_gecerlilik timestamptz NOT NULL DEFAULT now() + interval '72 hours',
  kullanildi timestamptz,
  iptal      timestamptz
);

CREATE TABLE hukuk.abonelik (
  kiraci_id      uuid PRIMARY KEY REFERENCES hukuk.kiraci(id),
  durum          text NOT NULL CHECK (durum IN ('deneme', 'aktif', 'odemeBekliyor', 'askida', 'iptal')),
  donem          text NOT NULL CHECK (donem IN ('aylik', 'yillik')),
  donem_basi     date NOT NULL,
  donem_sonu     date NOT NULL CHECK (donem_sonu > donem_basi),
  ucretli_koltuk integer NOT NULL DEFAULT 1 CHECK (ucretli_koltuk >= 1),
  ilk_basarisiz  date,
  donem_sonunda_iptal boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------------
-- Satır düzeyi güvenlik ve yetkiler
-- ---------------------------------------------------------------------------

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['sirket', 'sozlesme', 'sozlesme_onay', 'hukuk_talebi', 'davet', 'abonelik', 'cari_hareket'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY kiraci_ayrimi ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci()) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci())', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['emanet_hareket', 'zaman_kaydi', 'icra_dosyasi'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY dosya_uzerinden ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci() AND '
                   'EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id)) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci())', t);
  END LOOP;
END $$;

ALTER TABLE hukuk.icra_tahsilat ENABLE ROW LEVEL SECURITY;
CREATE POLICY icra_uzerinden ON hukuk.icra_tahsilat
  USING (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.icra_dosyasi i WHERE i.id = icra_id))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

ALTER TABLE hukuk.ihbar ENABLE ROW LEVEL SECURITY;
CREATE POLICY ihbar_okuma ON hukuk.ihbar FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.ihbar_gorunur(id));
-- Kimden gelirse gelsin ihbar kaydedilebilir (ihbar formu); kaydeden sonradan göremeyebilir.
CREATE POLICY ihbar_ekleme ON hukuk.ihbar FOR INSERT WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

ALTER TABLE hukuk.sorusturma ENABLE ROW LEVEL SECURITY;
-- Politikalar "veya" ile birleştiği için okuma, güncelleme ve ekleme ayrı tanımlanır.
CREATE POLICY sorusturma_okuma ON hukuk.sorusturma FOR SELECT
  USING (kiraci_id = hukuk.aktif_kiraci() AND (sorumlu = hukuk.aktif_kullanici() OR hukuk.aktif_kullanici() = ANY (ekip)));
CREATE POLICY sorusturma_guncelleme ON hukuk.sorusturma FOR UPDATE
  USING (kiraci_id = hukuk.aktif_kiraci() AND (sorumlu = hukuk.aktif_kullanici() OR hukuk.aktif_kullanici() = ANY (ekip)))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());
-- Soruşturmayı hukuk direktörü açar (henüz ekip olmadığı için ayrı ekleme politikası).
CREATE POLICY sorusturma_acma ON hukuk.sorusturma FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (
    SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = hukuk.aktif_kullanici() AND r.rol IN ('hukukDirektoru', 'uyumSorumlusu')));

GRANT SELECT, INSERT ON hukuk.cari_hareket, hukuk.emanet_hareket, hukuk.icra_tahsilat, hukuk.sozlesme_onay, hukuk.ihbar
  TO hukuk_uygulama;
GRANT SELECT, INSERT, UPDATE ON hukuk.sirket, hukuk.sozlesme, hukuk.hukuk_talebi, hukuk.icra_dosyasi, hukuk.sorusturma,
  hukuk.davet, hukuk.abonelik TO hukuk_uygulama;
GRANT SELECT, INSERT, UPDATE, DELETE ON hukuk.zaman_kaydi TO hukuk_uygulama;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hukuk TO hukuk_uygulama;

COMMIT;
