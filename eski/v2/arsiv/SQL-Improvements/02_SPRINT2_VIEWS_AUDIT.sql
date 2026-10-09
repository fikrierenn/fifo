USE BKMMaliyet;
GO
-- =============================================================
-- FIFO SISTEMI - SPRINT 2: YARDIMCI VIEW'LAR VE DEGISIM GUNLUGU
-- Versiyon: 2.0
-- Tarih: 2025-01-19
-- Amac: Muhasebe kontrolu ve denetim izleri kurmak
-- =============================================================
-- UYARI: Sprint 1 uygulandiktan sonra calistiriniz!
-- Efor: 2-3 saat
-- Risk: Dusuk (sadece ekleme, veri kopyalamiyor)
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '=============================================================';
PRINT 'FIFO SPRINT 2: YARDIMCI VIEW''LAR VE DEGISIM GUNLUGU';
PRINT '=============================================================';
PRINT '';
PRINT 'Bu script asagidaki degisiklikleri yapar:';
PRINT '1. Degisim Gunlugu tablosu ve trigger''lari olustur';
PRINT '2. 8 x Muhasebe/karlilik view''i olustur';
PRINT '3. 2 x Degisim log view''i olustur';
PRINT '4. 3 x Yardimci stored procedure olustur';
PRINT '';
PRINT 'Baslangic Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '=============================================================';
PRINT '';
GO

-- =============================================================
-- BOLUM 1: DEGISIM GUNLUGU TABLOSU VE TRIGGER'LAR
-- =============================================================

PRINT 'BOLUM 1: Degisim Gunlugu Yapisi Olusturuluyor...';
PRINT '';
GO

-- Degisim Gunlugu Tablosu
IF OBJECT_ID('bkm.fifo_DegisimGunlugu', 'U') IS NULL
BEGIN
    CREATE TABLE bkm.fifo_DegisimGunlugu (
        degisimID BIGINT IDENTITY(1,1) PRIMARY KEY,
        tabloAdi VARCHAR(50) NOT NULL,
        islemTipi VARCHAR(10) NOT NULL,  -- EKLE/GUNCELLE/SIL
        etkilenenID INT NOT NULL,
        eskiDegerler NVARCHAR(MAX) NULL,
        yeniDegerler NVARCHAR(MAX) NULL,
        degistiren NVARCHAR(100) NOT NULL DEFAULT(SUSER_NAME()),
        degisimTarihi DATETIME2(3) NOT NULL DEFAULT(GETDATE()),
        
        CONSTRAINT CK_DegisimGunlugu_IslemTipi CHECK (islemTipi IN ('EKLE', 'GUNCELLE', 'SIL'))
    );
    
    PRINT '   x fifo_DegisimGunlugu tablosu olusturuldu.';
END
ELSE
BEGIN
    PRINT '   i fifo_DegisimGunlugu tablosu zaten mevcut.';
END
GO

-- Degisim Gunlugu Indeksleri (idempotent)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DegisimGunlugu_TabloIslem'
               AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu'))
    CREATE INDEX IX_DegisimGunlugu_TabloIslem
        ON bkm.fifo_DegisimGunlugu(tabloAdi, islemTipi, degisimTarihi DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DegisimGunlugu_EtkilenenID'
               AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu'))
    CREATE INDEX IX_DegisimGunlugu_EtkilenenID
        ON bkm.fifo_DegisimGunlugu(tabloAdi, etkilenenID, degisimTarihi DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DegisimGunlugu_Degistiren'
               AND object_id = OBJECT_ID('bkm.fifo_DegisimGunlugu'))
    CREATE INDEX IX_DegisimGunlugu_Degistiren
        ON bkm.fifo_DegisimGunlugu(degistiren, degisimTarihi DESC);

PRINT '   x Degisim Gunlugu indeksleri olusturuldu.';
GO

-- Trigger: fifo_StokMaliyetHavuzu Degisim
IF OBJECT_ID('bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu', 'TR') IS NOT NULL
    DROP TRIGGER bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu;
GO

CREATE TRIGGER bkm.tr_fifo_StokMaliyetHavuzu_DegisimGunlugu
ON bkm.fifo_StokMaliyetHavuzu
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO bkm.fifo_DegisimGunlugu 
        (tabloAdi, islemTipi, etkilenenID, eskiDegerler, yeniDegerler, degistiren, degisimTarihi)
    SELECT
        'fifo_StokMaliyetHavuzu',
        CASE WHEN DELETED.ID IS NULL THEN 'EKLE'
             WHEN INSERTED.ID IS NULL THEN 'SIL'
             ELSE 'GUNCELLE' END,
        COALESCE(INSERTED.ID, DELETED.ID),
        (SELECT * FROM DELETED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT * FROM INSERTED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        SUSER_NAME(),
        GETDATE()
    FROM INSERTED
    FULL OUTER JOIN DELETED ON INSERTED.ID = DELETED.ID
    WHERE INSERTED.ID IS NOT NULL OR DELETED.ID IS NOT NULL;
END
GO

PRINT '   x tr_fifo_StokMaliyetHavuzu_DegisimGunlugu trigger''i olusturuldu.';
GO

-- Trigger: fifo_StokMaliyetCikis Degisim
IF OBJECT_ID('bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu', 'TR') IS NOT NULL
    DROP TRIGGER bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu;
GO

CREATE TRIGGER bkm.tr_fifo_StokMaliyetCikis_DegisimGunlugu
ON bkm.fifo_StokMaliyetCikis
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO bkm.fifo_DegisimGunlugu 
        (tabloAdi, islemTipi, etkilenenID, eskiDegerler, yeniDegerler, degistiren, degisimTarihi)
    SELECT
        'fifo_StokMaliyetCikis',
        CASE WHEN DELETED.ID IS NULL THEN 'EKLE'
             WHEN INSERTED.ID IS NULL THEN 'SIL'
             ELSE 'GUNCELLE' END,
        COALESCE(INSERTED.ID, DELETED.ID),
        (SELECT * FROM DELETED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT * FROM INSERTED FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        SUSER_NAME(),
        GETDATE()
    FROM INSERTED
    FULL OUTER JOIN DELETED ON INSERTED.ID = DELETED.ID
    WHERE INSERTED.ID IS NOT NULL OR DELETED.ID IS NOT NULL;
END
GO

PRINT '   x tr_fifo_StokMaliyetCikis_DegisimGunlugu trigger''i olusturuldu.';
PRINT '';
GO

-- =============================================================
-- BOLUM 2: MUHASEBE KONTROL VIEW'LARI
-- =============================================================

PRINT 'BOLUM 2: Muhasebe Kontrol View''lari Olusturuluyor...';
PRINT '';
GO

-- VIEW 1: FIFO Katman Tuketimi ve Tutarlilik Kontrol
CREATE OR ALTER VIEW bkm.vw_KatmanTuketimRaporu
AS
WITH KatmanTuketim AS (
    SELECT
        h.ID AS katmanID,
        h.stkID,
        h.girisTarihi,
        h.kaynakTip,
        h.belgeNo AS girisBelgeNo,
        h.belgeTarihi AS girisBelgeTarihi,
        h.miktarToplam,
        h.miktarKalan,
        (h.miktarToplam - h.miktarKalan) AS hesaplananTuketim,
        ISNULL(SUM(c.miktar), 0) AS raporlananTuketim,
        h.birimMaliyet,
        (h.miktarToplam - h.miktarKalan) * h.birimMaliyet AS hesaplananTutar,
        ISNULL(SUM(c.cikisTutar), 0) AS raporlananTutar
    FROM bkm.fifo_StokMaliyetHavuzu h
    LEFT JOIN bkm.fifo_StokMaliyetCikis c ON c.katmanID = h.ID
    GROUP BY h.ID, h.stkID, h.girisTarihi, h.kaynakTip, h.belgeNo, h.belgeTarihi,
             h.miktarToplam, h.miktarKalan, h.birimMaliyet
)
SELECT
    katmanID,
    stkID,
    girisTarihi,
    kaynakTip,
    girisBelgeNo,
    girisBelgeTarihi,
    miktarToplam,
    miktarKalan,
    hesaplananTuketim,
    raporlananTuketim,
    (hesaplananTuketim - raporlananTuketim) AS tuketimFarki,
    birimMaliyet,
    hesaplananTutar,
    raporlananTutar,
    (hesaplananTutar - raporlananTutar) AS tutarFarki,
    CASE 
        WHEN ABS(hesaplananTuketim - raporlananTuketim) < 0.01 THEN 'OK'
        ELSE 'UYUSMAZLIK'
    END AS kontrolDurumu,
    GETDATE() AS raporTarihi
FROM KatmanTuketim;
GO

PRINT '   x vw_KatmanTuketimRaporu olusturuldu.';
GO

-- VIEW 2: FIFO Cikis Detayli Rapor
CREATE OR ALTER VIEW bkm.vw_CikisDetayliRapor
AS
SELECT
    c.ID AS cikisID,
    c.stkID,
    c.hareketTarihi,
    c.hareketTipi,
    c.hareketMekanID,
    c.satisBelgeNo,
    c.katmanID,
    c.katmanTarihi,
    c.katmanBelgeNo,
    c.miktar,
    c.birimMaliyet,
    c.cikisTutar,
    h.kaynakTip,
    h.durum AS katmanDurum,
    h.girisTarihi,
    h.miktarToplam AS katmanMiktarToplam,
    h.miktarKalan AS katmanMiktarKalan,
    (h.miktarToplam - h.miktarKalan) AS katmanTuketilenMiktar
FROM bkm.fifo_StokMaliyetCikis c
LEFT JOIN bkm.fifo_StokMaliyetHavuzu h ON h.ID = c.katmanID;
GO

PRINT '   x vw_CikisDetayliRapor olusturuldu.';
GO

-- VIEW 3: Gunluk SMM (Stok Maliyet Muhasebesi) Ozeti
CREATE OR ALTER VIEW bkm.vw_GunlukSMM_Ozeti
AS
SELECT
    hareketTarihi,
    hareketMekanID,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) AS satisBasiMiktar,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN miktar ELSE 0 END) AS iadeBasiMiktar,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisBasiMaliyet,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeBasiMaliyet,
    SUM(cikisTutar) AS toplamMaliyet,
    COUNT(*) AS satirSayisi,
    CASE 
        WHEN SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END) > 0
        THEN SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) 
             / SUM(CASE WHEN hareketTipi = 'SATIS' THEN miktar ELSE 0 END)
        ELSE 0
    END AS ortalamaSatisBirimMaliyet
FROM bkm.fifo_StokMaliyetCikis
GROUP BY hareketTarihi, hareketMekanID;
GO

PRINT '   x vw_GunlukSMM_Ozeti olusturuldu.';
GO

-- VIEW 4: Urun Bazli SMM Raporu
CREATE OR ALTER VIEW bkm.vw_UrunBazliSMM_Detay
AS
SELECT
    stkID,
    hareketTarihi,
    hareketTipi,
    hareketMekanID,
    COUNT(DISTINCT katmanID) AS katmanSayisi,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet,
    CASE WHEN SUM(miktar) <> 0 
         THEN SUM(cikisTutar) / SUM(miktar) 
         ELSE 0 
    END AS ortalamaBirimMaliyet,
    CAST(GETDATE() AS DATE) AS raporTarihi
FROM bkm.fifo_StokMaliyetCikis
GROUP BY stkID, hareketTarihi, hareketTipi, hareketMekanID;
GO

PRINT '   x vw_UrunBazliSMM_Detay olusturuldu.';
GO

-- VIEW 5: Katman Durumu Ozeti
CREATE OR ALTER VIEW bkm.vw_KatmanDurumuOzeti
AS
SELECT
    stkID,
    kaynakTip,
    girisTarihi,
    durum,
    COUNT(*) AS katmanSayisi,
    SUM(miktarToplam) AS toplamMiktar,
    SUM(miktarKalan) AS kalanMiktar,
    SUM(miktarToplam - miktarKalan) AS tuketilenMiktar,
    AVG(birimMaliyet) AS ortalamaBirimMaliyet,
    MIN(birimMaliyet) AS minBirimMaliyet,
    MAX(birimMaliyet) AS maxBirimMaliyet,
    SUM(miktarKalan * birimMaliyet) AS kalanTutar
FROM bkm.fifo_StokMaliyetHavuzu
GROUP BY stkID, kaynakTip, girisTarihi, durum;
GO

PRINT '   x vw_KatmanDurumuOzeti olusturuldu.';
GO

-- VIEW 6: Sorunlu Stoklar Raporu
CREATE OR ALTER VIEW bkm.vw_SorunluStoklar_Rapor
AS
SELECT
    sorunTip,
    envanterTarihi,
    COUNT(DISTINCT stkID) AS urunSayisi,
    SUM(stokMiktar) AS toplamMiktar,
    MIN(kayitTarihi) AS ilkKayit,
    MAX(kayitTarihi) AS sonKayit,
    COUNT(*) AS kayitSayisi
FROM bkm.fifo_StokMaliyetSorunlu
GROUP BY sorunTip, envanterTarihi;
GO

PRINT '   x vw_SorunluStoklar_Rapor olusturuldu.';
PRINT '';
GO

-- VIEW 7: Gunluk-Mekan-Urun Satis Gelir Ozeti (raporlama grain)
IF COL_LENGTH('DerinSISBkm.dbo.irsAyr', 'ehTutar') IS NOT NULL
BEGIN
    EXEC(N'
    CREATE OR ALTER VIEW bkm.vw_SatisGelir_GunlukMekanUrun
    AS
    SELECT
        dt.ehStkID AS stkID,
        CAST(bs.eTarihS AS DATE) AS hareketTarihi,
        bs.eMekan AS hareketMekanID,
        CASE WHEN SUM(CONVERT(DECIMAL(18,4), dt.ehAdet)) < 0 THEN ''SATIS'' ELSE ''IADE'' END AS hareketTipi,
        SUM(ABS(CONVERT(DECIMAL(18,4), dt.ehAdet))) AS toplamMiktar,
        SUM(CASE WHEN CONVERT(DECIMAL(18,4), dt.ehAdet) < 0
                 THEN ABS(CONVERT(DECIMAL(18,6), ISNULL(dt.ehTutar,0)))
                 ELSE 0 END) AS satisTutari,
        SUM(CASE WHEN CONVERT(DECIMAL(18,4), dt.ehAdet) > 0
                 THEN ABS(CONVERT(DECIMAL(18,6), ISNULL(dt.ehTutar,0)))
                 ELSE 0 END) AS iadeTutari,
        SUM(CASE WHEN CONVERT(DECIMAL(18,4), dt.ehAdet) < 0
                 THEN ABS(CONVERT(DECIMAL(18,6), ISNULL(dt.ehTutar,0)))
                 WHEN CONVERT(DECIMAL(18,4), dt.ehAdet) > 0
                 THEN -ABS(CONVERT(DECIMAL(18,6), ISNULL(dt.ehTutar,0)))
                 ELSE 0 END) AS netGelirTutari
    FROM DerinSISBkm.dbo.irs bs WITH(NOLOCK)
    JOIN DerinSISBkm.dbo.irsAyr dt WITH(NOLOCK) ON dt.ehID = bs.eID
    WHERE bs.eTip IN (1,4,5,100,101)
      AND bs.eMekan IN (1, 12, 4477, 4478)
    GROUP BY dt.ehStkID, CAST(bs.eTarihS AS DATE), bs.eMekan;
    ');

    PRINT '   x vw_SatisGelir_GunlukMekanUrun olusturuldu.';
END
ELSE
BEGIN
    PRINT '   ! vw_SatisGelir_GunlukMekanUrun olusturulmadi (irsAyr.ehTutar kolonu bulunamadi).';
END
GO

-- VIEW 8: Gunluk-Mekan-Urun Brut Karlilik (gelir + FIFO maliyet)
IF OBJECT_ID('bkm.vw_SatisGelir_GunlukMekanUrun', 'V') IS NOT NULL
BEGIN
    EXEC(N'
    CREATE OR ALTER VIEW bkm.vw_BrutKarlilik_GunlukMekanUrun
    AS
    WITH Maliyet AS (
        SELECT
            c.stkID,
            c.hareketTarihi,
            c.hareketMekanID,
            c.hareketTipi,
            SUM(c.miktar) AS maliyetMiktari,
            SUM(c.cikisTutar) AS toplamMaliyet
        FROM bkm.fifo_StokMaliyetCikis c
        GROUP BY c.stkID, c.hareketTarihi, c.hareketMekanID, c.hareketTipi
    )
    SELECT
        COALESCE(g.stkID, m.stkID) AS stkID,
        COALESCE(g.hareketTarihi, m.hareketTarihi) AS hareketTarihi,
        COALESCE(g.hareketMekanID, m.hareketMekanID) AS hareketMekanID,
        COALESCE(g.hareketTipi, m.hareketTipi) AS hareketTipi,
        ISNULL(g.toplamMiktar, 0) AS satisMiktari,
        ISNULL(g.satisTutari, 0) AS satisTutari,
        ISNULL(g.iadeTutari, 0) AS iadeTutari,
        ISNULL(g.netGelirTutari, 0) AS netGelirTutari,
        ISNULL(m.maliyetMiktari, 0) AS maliyetMiktari,
        ISNULL(m.toplamMaliyet, 0) AS toplamMaliyet,
        ISNULL(g.netGelirTutari, 0) - ISNULL(m.toplamMaliyet, 0) AS brutKarTutari,
        CASE
            WHEN ISNULL(g.netGelirTutari, 0) <> 0
            THEN (ISNULL(g.netGelirTutari, 0) - ISNULL(m.toplamMaliyet, 0)) / NULLIF(ISNULL(g.netGelirTutari, 0), 0)
            ELSE NULL
        END AS brutKarMarji
    FROM bkm.vw_SatisGelir_GunlukMekanUrun g
    FULL OUTER JOIN Maliyet m
      ON m.stkID = g.stkID
     AND m.hareketTarihi = g.hareketTarihi
     AND ISNULL(m.hareketMekanID, -1) = ISNULL(g.hareketMekanID, -1)
     AND m.hareketTipi = g.hareketTipi;
    ');

    PRINT '   x vw_BrutKarlilik_GunlukMekanUrun olusturuldu.';
END
ELSE
BEGIN
    PRINT '   ! vw_BrutKarlilik_GunlukMekanUrun olusturulmadi (gelir view mevcut degil).';
END
GO

-- =============================================================
-- BOLUM 3: DEGISIM GUNLUGU SORGULAMA VIEW'LARI
-- =============================================================

PRINT 'BOLUM 3: Degisim Gunlugu Sorgulama View''lari Olusturuluyor...';
PRINT '';
GO

-- Degisim View 1: Son degisiklikler
CREATE OR ALTER VIEW bkm.vw_SonDegisiklikler
AS
SELECT TOP 1000
    degisimID,
    tabloAdi,
    islemTipi,
    etkilenenID,
    degistiren,
    degisimTarihi,
    DATEDIFF(MINUTE, degisimTarihi, GETDATE()) AS oncekiDakika
FROM bkm.fifo_DegisimGunlugu
ORDER BY degisimID DESC;
GO

PRINT '   x vw_SonDegisiklikler olusturuldu.';
GO

-- Degisim View 2: Kullanici aktiviteleri
CREATE OR ALTER VIEW bkm.vw_KullaniciAktiviteleri
AS
SELECT
    degistiren,
    tabloAdi,
    islemTipi,
    COUNT(*) AS islemSayisi,
    MIN(degisimTarihi) AS ilkIslem,
    MAX(degisimTarihi) AS sonIslem
FROM bkm.fifo_DegisimGunlugu
GROUP BY degistiren, tabloAdi, islemTipi;
GO

PRINT '   x vw_KullaniciAktiviteleri olusturuldu.';
PRINT '';
GO

-- =============================================================
-- BOLUM 4: YARDIMCI STORED PROCEDURE'LAR
-- =============================================================

PRINT 'BOLUM 4: Yardimci Stored Procedure''lar Olusturuluyor...';
PRINT '';
GO

-- SP 1: Belirli bir katmanin degisim tarihcesi
CREATE OR ALTER PROCEDURE bkm.sp_KatmanDegisimTarihcesi
(
    @katmanID INT
)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        degisimID,
        tabloAdi,
        islemTipi,
        eskiDegerler,
        yeniDegerler,
        degistiren,
        degisimTarihi
    FROM bkm.fifo_DegisimGunlugu
    WHERE tabloAdi = 'fifo_StokMaliyetHavuzu'
      AND etkilenenID = @katmanID
    ORDER BY degisimID ASC;
END
GO

PRINT '   x sp_KatmanDegisimTarihcesi olusturuldu.';
GO

-- SP 2: Cikis kaydinin katman ve tutarlilik kontrolu
CREATE OR ALTER PROCEDURE bkm.sp_CikisTutarlillikKontrolu
(
    @cikisID INT
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @katmanID INT;
    DECLARE @cikisMiktar DECIMAL(18,4);
    DECLARE @birimMaliyet DECIMAL(18,6);
    
    SELECT 
        @katmanID = katmanID,
        @cikisMiktar = miktar,
        @birimMaliyet = birimMaliyet
    FROM bkm.fifo_StokMaliyetCikis
    WHERE ID = @cikisID;
    
    IF @katmanID IS NULL
    BEGIN
        RAISERROR('Cikis kaydi bulunamadi', 16, 1);
        RETURN;
    END
    
    -- Katman bilgisini al
    SELECT
        h.ID,
        h.stkID,
        h.girisTarihi,
        h.kaynakTip,
        h.miktarToplam,
        h.miktarKalan,
        h.birimMaliyet,
        (SELECT SUM(miktar) FROM bkm.fifo_StokMaliyetCikis WHERE katmanID = h.ID) AS toplamCikis,
        CASE 
            WHEN h.birimMaliyet = @birimMaliyet THEN 'OK'
            ELSE 'UYUSMAZLIK: Farkli fiyat!'
        END AS fiyatKontrol
    FROM bkm.fifo_StokMaliyetHavuzu h
    WHERE h.ID = @katmanID;
END
GO

PRINT '   x sp_CikisTutarlillikKontrolu olusturuldu.';
GO

-- SP 3: Gunluk veri tasima kontrolu
CREATE OR ALTER PROCEDURE bkm.sp_VeriTasiymaKontrolu
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE
)
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT 'Veri Tasiyma Kontrol Raporu';
    PRINT 'Tarih Araligi: ' + CONVERT(VARCHAR(10), @baslangicTarihi, 120) + 
          ' - ' + CONVERT(VARCHAR(10), @bitisTarihi, 120);
    PRINT '';
    
    PRINT '1. Acilis Katmanlari:';
    SELECT COUNT(*) AS katmanSayisi, SUM(miktarToplam) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
      AND girisTarihi >= @baslangicTarihi
      AND girisTarihi <= @bitisTarihi;
    
    PRINT '';
    PRINT '2. Alis Katmanlari:';
    SELECT COUNT(*) AS katmanSayisi, SUM(miktarToplam) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE kaynakTip = 'ALIS'
      AND girisTarihi >= @baslangicTarihi
      AND girisTarihi <= @bitisTarihi;
    
    PRINT '';
    PRINT '3. Cikis Hareketleri:';
    SELECT 
        hareketTipi,
        COUNT(*) AS satirSayisi,
        SUM(miktar) AS toplamMiktar,
        SUM(cikisTutar) AS toplamMaliyet
    FROM bkm.fifo_StokMaliyetCikis
    WHERE hareketTarihi >= @baslangicTarihi
      AND hareketTarihi <= @bitisTarihi
    GROUP BY hareketTipi;
    
    PRINT '';
    PRINT '4. Sorunlu Kayitlar:';
    SELECT 
        sorunTip,
        COUNT(*) AS kayitSayisi,
        SUM(stokMiktar) AS toplamMiktar
    FROM bkm.fifo_StokMaliyetSorunlu
    WHERE envanterTarihi >= @baslangicTarihi
      AND envanterTarihi <= @bitisTarihi
    GROUP BY sorunTip;
END
GO

PRINT '   x sp_VeriTasiymaKontrolu olusturuldu.';
PRINT '';
GO

-- =============================================================
-- SONLANDIS
-- =============================================================

PRINT '=============================================================';
PRINT 'SPRINT 2 TAMAMLANDI';
PRINT '=============================================================';
PRINT '';
PRINT 'Olusturulan Objeler:';
PRINT 'x 1 x Degisim Gunlugu Tablosu (fifo_DegisimGunlugu)';
PRINT 'x 3 x Index (degisim gunlugu icin)';
PRINT 'x 2 x Degisim Trigger (Havuzu, Cikis)';
PRINT 'x 8 x Muhasebe/Karlilik View';
PRINT 'x 2 x Degisim Gunlugu View';
PRINT 'x 3 x Yardimci Stored Procedure';
PRINT '';
PRINT 'Bitis Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '';
PRINT 'Sonraki Adimlar:';
PRINT '1. Test Veri Setup script''ini calistirin (03_TEST_DATA_SETUP.sql)';
PRINT '2. View''lari test edin (SELECT * FROM bkm.vw_KatmanTuketimRaporu)';
PRINT '3. Karlilik view''unu kontrol edin (SELECT * FROM bkm.vw_BrutKarlilik_GunlukMekanUrun)';
PRINT '4. Degisim log''u kontrol edin (SELECT * FROM bkm.vw_SonDegisiklikler)';
PRINT '5. SPRINT 3 (optimizasyon) plani yapin';
PRINT '=============================================================';
GO
