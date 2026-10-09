/* =====================================================================
   19_V2_DevreDisi_Fallback_Seed.sql
   Ocak 2026 sorunlu urun temizligi — idempotent seed (rerun-safe).
   Kaynak: 2026-06-06 sorunlu urun tam taramasi (sorunlu-urun-dedektif).

   1) Non-inventory urunler FifoDevreDisiUrunler'e (gozle dogrulanmis, additive).
   2) Fiyatsiz gercek urunlere FifoFallbackFiyatlari (SonAlis veya SatisFiyat*0.65).

   NOT: FifoFallbackFiyatlari fallback'i acilis SP'sinde
        @fallbackSatinalmaSarti='DEVIR_FALLBACK' ile devreye girer.
   ===================================================================== */
SET XACT_ABORT ON;
SET NOCOUNT ON;

/* ---------- 1) NON-INVENTORY (additive, WHERE NOT EXISTS) ---------- */
INSERT INTO dbo.FifoDevreDisiUrunler (StkId, Sebep, EkleyenKullanici, EklenmeTarihi)
SELECT v.StkId, v.Sebep, 'claude-dedektif', SYSDATETIME()
FROM (VALUES
  -- gelir/gider kalemleri + hediye ceki + teshir/stand (SatisFiyat=0)
  (107911,  N'STAND BEDELSIZ - teshir/non-inventory'),
  (432001,  N'ALIS KARGO GIDERI TEVKIFATLI - gider/non-inventory'),
  (1596966, N'Bkmkitap 750TL Hediye Ceki - non-inventory'),
  (144860,  N'KARGO GELIRI - gelir kalemi/non-inventory'),
  (144963,  N'KAPIDA ODEME GELIRI - gelir kalemi/non-inventory'),
  (436306,  N'KOMISYON BEDELI - gelir kalemi/non-inventory'),
  -- demirbas / sabit kiymet (SatisFiyat=0)
  (275486,  N'ISYERI DEMIRBASLARI - sabit kiymet'),
  (248339,  N'ISYERI DEMIRBASLARI - sabit kiymet'),
  (269485,  N'ISYERI MOBILYALARI - sabit kiymet'),
  (105512,  N'KAFETERYA DEMIRBASLARI - sabit kiymet'),
  (431951,  N'KLIMA - sabit kiymet'),
  (438548,  N'FOTOGRAF MAKINESI - sabit kiymet'),
  (179941,  N'YAZARKASA - sabit kiymet'),
  (105513,  N'YENI NESIL YAZAR KASA - sabit kiymet')
) v(StkId, Sebep)
WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = v.StkId);

/* ---------- 2) FALLBACK FIYAT (fiyatsiz gercek urunler) ----------
   FIYAT_YOK + kaynakta (fytOzl) fiyat yok + devre-disi degil + (SonAlis>0 OR SatisFiyat>0).
   BirimMaliyet = SonAlis (varsa) yoksa SatisFiyat*0.65 (%35 marj tahmini).
   UYARI: SatisFiyat*0.65 = TAHMIN, gercek fatura gelince override edilmeli. */
;WITH fy AS (
  SELECT DISTINCT s.StkId FROM dbo.FifoSorunluStoklar s
  WHERE s.SorunTipi = 'FIYAT_YOK'
    AND NOT EXISTS (SELECT 1 FROM DerinSIS_Local.dbo.fytOzl f
                    WHERE f.fStkID = s.StkId AND f.fTarih <= '2025-12-31')
    AND NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler d WHERE d.StkId = s.StkId)
)
INSERT INTO dbo.FifoFallbackFiyatlari
    (StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama, KayitTarihi)
SELECT fy.StkId, 'DEVIR_FALLBACK', 0,
  CASE WHEN u.SonAlis > 0 THEN u.SonAlis ELSE CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)) END,
  1,
  CASE WHEN u.SonAlis > 0 THEN u.SonAlis ELSE CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)) END,
  CASE WHEN u.SonAlis > 0 THEN N'SonAlis fallback' ELSE N'SatisFiyat*0.65 tahmini' END,
  SYSDATETIME()
FROM fy
JOIN DerinSIS_Local.dbo.UrunBilgi u ON u.stkID = fy.StkId
WHERE (u.SonAlis > 0 OR u.SatisFiyat > 0)
  AND NOT EXISTS (SELECT 1 FROM dbo.FifoFallbackFiyatlari ff
                  WHERE ff.StkId = fy.StkId AND ff.SatinalmaSarti = 'DEVIR_FALLBACK' AND ff.MekanId = 0);

/* ---------- 3) COST ANOMALI — MANUEL MALIYET OVERRIDE ----------
   ERP SonAlis koli/qty hatasi olan urunler (BirimMaliyet >> SatisFiyat).
   Acilis SP'si FifoManuelMaliyet'i en yuksek oncelikli kaynak olarak ezer.
   Tahmin = SatisFiyat*0.65; gercek fatura koli teyidi sonrasi guncellenecek.
   Karne Hediyesi (200772) HARIC — anomalisi gelir tarafi (SatisFiyat=0.01 kasitli). */
;WITH anomali AS (
  SELECT v.StkId FROM (VALUES
    (1690718),(1690719),(1690720),(1690721), -- Okapi Kalem Cantasi x4
    (1559504),(1627067),(500233),(259297),(1607635),
    (1628142),(1648583),(175537),(203436),(153251)
  ) v(StkId)
)
INSERT INTO dbo.FifoManuelMaliyet (StkId, BirimMaliyet, GecerliBaslangic, GecerliBitis, Aciklama, EkleyenKullanici, Aktif)
SELECT a.StkId, CAST(u.SatisFiyat * 0.65 AS DECIMAL(18,6)), '2025-12-31', NULL,
       N'Cost anomali (ERP SonAlis koli/qty hatasi). Tahmin=SatisFiyat*0.65, fatura teyidi sonrasi guncelle.',
       'claude-dedektif', 1
FROM anomali a
JOIN DerinSIS_Local.dbo.UrunBilgi u ON u.stkID = a.StkId
WHERE u.SatisFiyat > 0
  AND NOT EXISTS (SELECT 1 FROM dbo.FifoManuelMaliyet m WHERE m.StkId = a.StkId AND m.Aktif = 1);

PRINT 'Devre-disi + fallback + manuel-maliyet seed tamamlandi. Acilis re-run: @fallbackSatinalmaSarti=''DEVIR_FALLBACK''.';
