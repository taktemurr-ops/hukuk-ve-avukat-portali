-- İcra dosya hesabı için takip öncesi/sonrası masraflar ve işlemiş faizin elle girilmesi.
BEGIN;
ALTER TABLE hukuk.icra_dosyasi
  ADD COLUMN takip_oncesi_masraf_kurus bigint NOT NULL DEFAULT 0 CHECK (takip_oncesi_masraf_kurus >= 0),
  ADD COLUMN takip_sonrasi_masraf_kurus bigint NOT NULL DEFAULT 0 CHECK (takip_sonrasi_masraf_kurus >= 0),
  ADD COLUMN islemis_faiz_elle_kurus bigint CHECK (islemis_faiz_elle_kurus >= 0),
  ADD COLUMN teblig_tarihi date;
COMMIT;

-- Sözleşmesel (akdi) faizde yıllık oran; diğer faiz türlerinde boş kalır.
ALTER TABLE hukuk.icra_dosyasi
  ADD COLUMN akdi_oran numeric(7,4) CHECK (akdi_oran >= 0 AND akdi_oran <= 1000),
  ADD CONSTRAINT icra_akdi_oran_zorunlu CHECK (faiz_turu <> 'akdi' OR akdi_oran IS NOT NULL);

-- Emanet hareket türleri çekirdek paketteki EmanetHareketTuru adlarıyla hizalanır
-- (muvekkileOdeme → muvekkileAktarim, mahsup → ucretMahsubu).
ALTER TABLE hukuk.emanet_hareket DROP CONSTRAINT emanet_hareket_tur_check;
ALTER TABLE hukuk.emanet_hareket DROP CONSTRAINT emanet_hareket_check;
UPDATE hukuk.emanet_hareket SET tur = 'muvekkileAktarim' WHERE tur = 'muvekkileOdeme';
UPDATE hukuk.emanet_hareket SET tur = 'ucretMahsubu' WHERE tur = 'mahsup';
ALTER TABLE hukuk.emanet_hareket
  ADD CONSTRAINT emanet_hareket_tur_check CHECK (tur IN ('giris', 'muvekkileAktarim', 'ucretMahsubu')),
  ADD CONSTRAINT emanet_mahsup_onayi CHECK (tur <> 'ucretMahsubu' OR coalesce(length(trim(mahsup_onayi)), 0) > 0);
