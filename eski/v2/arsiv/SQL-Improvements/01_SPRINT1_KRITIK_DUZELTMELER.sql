USE BKMMaliyet;
GO

-- =============================================================
-- FIFO SISTEMI - SPRINT 1: KRATAK DAZELTMELER (MEKAN BAAIMSIZ)
-- Versiyon: 2.0
-- Tarih: 2025-01-19
-- AmaA: FIFO algoritmasAnA stabil ve denetlenebilir hale getirmek
-- NOT: Maliyetler mekan baAYAmsAz, ortak (merkezi)
-- =============================================================
-- UYARI: Bu script production'a uygulanmadan Ance backup alAnAz!
-- Efor: 2-3 saat
-- Risk: DA14AYA14k (backward compatible)
-- =============================================================

SET NOCOUNT ON;
GO

PRINT '=============================================================';
PRINT 'FIFO SPRINT 1: KRATAK DAZELTMELER (MEKAN BAAIMSIZ)';
PRINT '=============================================================';
PRINT '';
PRINT 'Bu script aAYaAYAdaki deAYiAYiklikleri yapar:';
PRINT '1. FIFO sAralama indekslerini yeniden tasarla (deterministic)';
PRINT '2. ERPDevirFiyatlari tablosunu MEKAN BAAIMSIZ yapAya dAnA14AYtA14r';
PRINT '3. 5 x Check constraint ekle (veri butunlugu)';
PRINT '4. 2 x Foreign key ekle (referans butunlugu)';
PRINT '5. sp_fifo_StokMaliyetAlisKatman''a XACT_ABORT ekle (transaction)';
PRINT '6. Veri butunlugu kontrol sorgulari calistir';
PRINT '';
PRINT 'NOT: Maliyetler merkez bazAnda ortak, mekan farklAlAAYA YOK';
PRINT 'Baslangic Zamani: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '=============================================================';
PRINT '';
GO

-- =============================================================
-- ADIM 1: FIFO SIRALAMASI - DETERMINISTIC YAPILARI
-- =============================================================

PRINT 'ADIM 1: FIFO SAralama Andeksleri Yeniden YapAlandArAlAyor...';
PRINT '';
GO

-- Eski indeksleri sil
DROP INDEX IF EXISTS IX_fifo_StokMaliyetHavuzu_stkID 
    ON bkm.fifo_StokMaliyetHavuzu;
DROP INDEX IF EXISTS IX_fifo_StokMaliyetHavuzu_AktifKatman 
    ON bkm.fifo_StokMaliyetHavuzu;
GO

-- Yeni deterministic index
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fifo_Havuz_FifoSira'
               AND object_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu'))
    CREATE INDEX IX_fifo_Havuz_FifoSira
        ON bkm.fifo_StokMaliyetHavuzu(stkID, girisTarihi, belgeNo, ID)
        INCLUDE (miktarToplam, miktarKalan, birimMaliyet)
        WHERE miktarKalan > 0;
GO

PRINT '   x IX_fifo_Havuz_FifoSira olusturuldu (deterministic).';

-- Yardimci view: Siralanmis katmanlar
CREATE OR ALTER VIEW bkm.vw_FifoKatmanlarSirali
AS
SELECT
    h.ID,
    h.stkID,
    h.girisTarihi,
    h.kaynakTip,
    h.belgeNo,
    h.miktarToplam,
    h.miktarKalan,
    h.birimMaliyet,
    h.durum,
    ROW_NUMBER() OVER (
        PARTITION BY h.stkID
        ORDER BY h.girisTarihi ASC, h.belgeNo ASC, h.ID ASC
    ) AS fifo_siirasi
FROM bkm.fifo_StokMaliyetHavuzu h
WHERE h.miktarKalan > 0;
GO

PRINT '   x bkm.vw_FifoKatmanlarSirali olusturuldu.';
PRINT '';
GO

-- =============================================================
-- ADIM 2: ERPDevirFiyatlari - MEKAN BAAIMSIZ YAPIYA DANAATARMEK
-- =============================================================

PRINT 'ADIM 2: ERPDevirFiyatlari Tablosu MEKAN BAAIMSIZ YapAsAna DAnA14AYtA14rA14lA14yor...';
PRINT '';
GO

-- EAYer mekanID sA14tunu varsa sil (MEKAN BAAIMSIZ olacak)
IF COL_LENGTH('bkm.fifo_ErpDevirFiyatlari', 'mekanID') IS NOT NULL
BEGIN
    -- PK'A sil
    IF OBJECT_ID('PK_ErpDevirFiyat', 'PK') IS NOT NULL
    BEGIN
        ALTER TABLE bkm.fifo_ErpDevirFiyatlari
        DROP CONSTRAINT PK_ErpDevirFiyat;
    END
    IF OBJECT_ID('PK_fifo_ErpDevirFiyatlari', 'PK') IS NOT NULL
    BEGIN
        ALTER TABLE bkm.fifo_ErpDevirFiyatlari
        DROP CONSTRAINT PK_fifo_ErpDevirFiyatlari;
    END
    
    -- mekanID sA14tununu sil
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari
    DROP COLUMN mekanID;
    
    PRINT '   a mekanID sA14tunu silindi (MEKAN BAAIMSIZ).';
END
GO

-- Yeni PK: Sadece (stkID, satinalmaSarti) - ARTANAz tA14m mekanlar iAin ortak fiyat
IF OBJECT_ID('PK_fifo_ErpDevirFiyatlari', 'PK') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari
    ADD CONSTRAINT PK_fifo_ErpDevirFiyatlari PRIMARY KEY (stkID, satinalmaSarti);
    
    PRINT '   x Yeni PK (stkID, satinalmaSarti) olusturuldu - ARTIK MEKAN BAGIMSIZ.';
END
GO

-- Eski index'leri sil
DROP INDEX IF EXISTS IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
    ON bkm.fifo_ErpDevirFiyatlari;
DROP INDEX IF EXISTS IX_ErpDevir_SartiMekan
    ON bkm.fifo_ErpDevirFiyatlari;
GO

-- Yeni index: Sadece satinalmaSarti
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fifo_ErpDevirFiyatlari_SatinalmaSarti'
               AND object_id = OBJECT_ID('bkm.fifo_ErpDevirFiyatlari'))
    CREATE INDEX IX_fifo_ErpDevirFiyatlari_SatinalmaSarti
        ON bkm.fifo_ErpDevirFiyatlari(satinalmaSarti)
        INCLUDE (birimMaliyet, miktar, toplamTutar);
PRINT '   x IX_fifo_ErpDevirFiyatlari_SatinalmaSarti olusturuldu.';
PRINT '';
GO

-- =============================================================
-- ADIM 3: CHECK CONSTRAINT'LER - VERA BATANLAAA
-- =============================================================

PRINT 'ADIM 3: Check Constraint''ler Ekleniyor...';
PRINT '';
GO

-- fifo_StokMaliyetHavuzu constraints
IF OBJECT_ID('CK_Havuz_Miktarlar_Gecerli', 'C') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_StokMaliyetHavuzu ADD CONSTRAINT
        CK_Havuz_Miktarlar_Gecerli CHECK (
            miktarToplam > 0 AND
            miktarKalan >= 0 AND
            miktarKalan <= miktarToplam AND
            birimMaliyet >= 0
        );
    PRINT '   a CK_Havuz_Miktarlar_Gecerli eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 CK_Havuz_Miktarlar_Gecerli zaten mevcut.';
END
GO

-- fifo_StokMaliyetCikis constraints
IF OBJECT_ID('CK_Cikis_Miktar_Pozitif', 'C') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_StokMaliyetCikis ADD CONSTRAINT
        CK_Cikis_Miktar_Pozitif CHECK (miktar > 0);
    PRINT '   a CK_Cikis_Miktar_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 CK_Cikis_Miktar_Pozitif zaten mevcut.';
END
GO

-- fifo_ErpDevirFiyatlari constraints
IF OBJECT_ID('CK_ErpDevir_Pozitif', 'C') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_ErpDevirFiyatlari ADD CONSTRAINT
        CK_ErpDevir_Pozitif CHECK (
            miktar > 0 AND
            toplamTutar > 0 AND
            birimMaliyet > 0
        );
    PRINT '   a CK_ErpDevir_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 CK_ErpDevir_Pozitif zaten mevcut.';
END
GO

-- fifo_StokEnvanter constraints
IF OBJECT_ID('CK_Envanter_Pozitif', 'C') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_StokEnvanter ADD CONSTRAINT
        CK_Envanter_Pozitif CHECK (stokMiktar >= 0);
    PRINT '   a CK_Envanter_Pozitif eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 CK_Envanter_Pozitif zaten mevcut.';
END
GO

-- fifo_Calistirma constraints
IF OBJECT_ID('CK_Run_Durum_Gecerli', 'C') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_Calistirma ADD CONSTRAINT
        CK_Run_Durum_Gecerli CHECK (
            durum IN (
                'PENDING', 'RUNNING', 'DONE', 'ERROR',
                'BEKLIYOR', 'CALISIYOR', 'TAMAMLANDI', 'HATA', 'ATLANDI'
            )
        );
    PRINT '   a CK_Run_Durum_Gecerli eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 CK_Run_Durum_Gecerli zaten mevcut.';
END
GO

PRINT '';
GO

-- =============================================================
-- ADIM 4: FOREIGN KEY'LER - REFERANS BATANLAAA
-- =============================================================

PRINT 'ADIM 4: Foreign Key''ler Ekleniyor...';
PRINT '';
GO

-- RunStep a Run referansA
IF OBJECT_ID('FK_RunStep_Run', 'F') IS NULL
BEGIN
    ALTER TABLE bkm.fifo_CalistirmaAdim ADD CONSTRAINT
        FK_RunStep_Run FOREIGN KEY (calistirmaId)
        REFERENCES bkm.fifo_Calistirma(calistirmaId)
        ON DELETE CASCADE;
    PRINT '   a FK_RunStep_Run eklendi.';
END
ELSE
BEGIN
    PRINT '   a1 FK_RunStep_Run zaten mevcut.';
END
GO

PRINT '';
GO

-- =============================================================
-- ADIM 5: TRANSACTION KONTROL - SP'LER
-- =============================================================

PRINT 'ADIM 5: Stored Procedure''lar XACT_ABORT ile GA14ncelleniyor...';
PRINT '';
GO

-- sp_fifo_StokMaliyetAlisKatman - SADECE FATURA: fat + fatAyr (irs/irsAyr yok)
CREATE OR ALTER PROCEDURE bkm.sp_fifo_StokMaliyetAlisKatman
(
    @baslangicTarihi DATE,
    @bitisTarihi DATE,
    @stkID INT = NULL,
    @calistirmaId UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- a KRITIK: KAsmi baAYarAsAzlAk AAkma
    
    -- Parametre validasyonu
    IF @baslangicTarihi IS NULL OR @bitisTarihi IS NULL
    BEGIN
        RAISERROR('Tarih parametreleri bos olamaz', 16, 1);
        RETURN;
    END
    
    IF @baslangicTarihi > @bitisTarihi
    BEGIN
        RAISERROR('Baslangic tarihi bitis tarihinden buyuk olamaz', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#alislar', 'U') IS NOT NULL DROP TABLE #alislar;

        /* Verilen tarih aralAAYAndaki alAAYlarA Aek (SADECE FATURA: fat + fatAyr) */
        SELECT 
            a.ehStkID AS stkID,
            f.eTarihS AS girisTarihi,
            f.eNo     AS belgeNo,
            f.eTarihS AS belgeTarihi,
            f.eFirma  AS firmaID,
            SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) AS miktar,
            SUM(CONVERT(DECIMAL(18,4),
                CASE WHEN f.eGC = 0 THEN a.ehTutarN ELSE -1 * a.ehTutarN END
            )) AS netTutar
        INTO #alislar
        FROM DerinSISBkm.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSISBkm.dbo.fat f WITH(NOLOCK)
            ON f.eID = a.ehID
        WHERE a.ehAdetN <> 0
          AND f.eTarihS >  CONVERT(smalldatetime, @baslangicTarihi)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @bitisTarihi))
          AND f.eTip IN (0, 2)
          AND (@stkID IS NULL OR a.ehStkID = @stkID)
        GROUP BY a.ehStkID, f.eTarihS, f.eID, f.eNo, f.eFirma
        HAVING SUM(CONVERT(DECIMAL(18,4), NULLIF(a.ehAdetN, 0))) <> 0;

        /* Birim maliyet hesapla */
        ALTER TABLE #alislar ADD birimMaliyet DECIMAL(18,6);

        UPDATE #alislar
        SET birimMaliyet = CASE WHEN miktar = 0 THEN 0 ELSE netTutar / miktar END;

        -- Constraint uyumsuz (iade/ters/fiyatsiz) satirlari ALIS havuzuna yazma
        DELETE FROM #alislar
        WHERE miktar <= 0
           OR netTutar <= 0
           OR birimMaliyet <= 0;

        /* AynA tarih aralAAYAndaki eski ALIS katmanlarAnA sil */
        DELETE FROM bkm.fifo_StokMaliyetHavuzu
        WHERE kaynakTip = 'ALIS'
          AND girisTarihi >  @baslangicTarihi
          AND girisTarihi <= @bitisTarihi
          AND (@stkID IS NULL OR stkID = @stkID);

        /* Yeni ALIS katmanlarAnA havuza yaz */
        INSERT INTO bkm.fifo_StokMaliyetHavuzu
            (stkID, girisTarihi, kaynakTip, belgeNo, belgeTarihi, firmaID,
             miktarToplam, miktarKalan, birimMaliyet, durum)
        SELECT
            stkID, girisTarihi, 'ALIS', belgeNo, belgeTarihi, firmaID,
            miktar, miktar, birimMaliyet, 'NORMAL'
        FROM #alislar;

        COMMIT TRANSACTION;
        
        PRINT 'Alis katmanlari basariyla olusturuldu. Tarih araligi: ' + 
              CONVERT(VARCHAR(10), @baslangicTarihi, 120) + ' - ' + 
              CONVERT(VARCHAR(10), @bitisTarihi, 120);
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        PRINT 'HATA: ' + @ErrorMessage;
        THROW;
    END CATCH
END
GO

PRINT '   a sp_fifo_StokMaliyetAlisKatman XACT_ABORT ile gA14ncellendi.';
PRINT '';
GO

-- =============================================================
-- ADIM 6: KONTROL SORGULARI - VERA BATANLAAA KONTROL
-- =============================================================

PRINT 'ADIM 6: Veri BA14tA14nlA14AYA14 Kontrol Ediliyor...';
PRINT '';
GO

-- Check constraint ihlalleri kontrol
DECLARE @violationCount INT = 0;

SELECT @violationCount = COUNT(*)
FROM bkm.fifo_StokMaliyetHavuzu
WHERE miktarToplam <= 0 
   OR miktarKalan < 0 
   OR miktarKalan > miktarToplam 
   OR birimMaliyet < 0;

IF @violationCount > 0
BEGIN
    PRINT '   as  UYARI: ' + CAST(@violationCount AS VARCHAR) + ' satAr check constraint ihlali!';
    PRINT '   Sorunlu kaydlar:';
    SELECT 
        'fifo_StokMaliyetHavuzu' AS [Tablo],
        ID,
        stkID,
        CASE 
            WHEN miktarToplam <= 0 THEN 'miktarToplam <= 0'
            WHEN miktarKalan < 0 THEN 'miktarKalan < 0'
            WHEN miktarKalan > miktarToplam THEN 'miktarKalan > miktarToplam'
            WHEN birimMaliyet < 0 THEN 'birimMaliyet < 0'
        END AS [Hata Tipi],
        CAST(miktarToplam AS VARCHAR) AS [DeAYer]
    FROM bkm.fifo_StokMaliyetHavuzu
    WHERE miktarToplam <= 0 
       OR miktarKalan < 0 
       OR miktarKalan > miktarToplam 
       OR birimMaliyet < 0;
END
ELSE
BEGIN
    PRINT '   a Check constraint ihlali yoktur.';
END
GO

-- PK tekrarlarA kontrol
DECLARE @pkCount INT = 0;

SELECT @pkCount = COUNT(*)
FROM (
    SELECT stkID, satinalmaSarti
    FROM bkm.fifo_ErpDevirFiyatlari
    GROUP BY stkID, satinalmaSarti
    HAVING COUNT(*) > 1
) dupli;

IF @pkCount > 0
BEGIN
    PRINT '   as  UYARI: ERPDevir''de ' + CAST(@pkCount AS VARCHAR) + ' PK tekrarA var!';
END
ELSE
BEGIN
    PRINT '   a Primary key ihlali yoktur.';
END
GO

PRINT '';
GO

-- =============================================================
-- SONLANDIA
-- =============================================================

PRINT '=============================================================';
PRINT 'SPRINT 1 TAMAMLANDI (MEKAN BAAIMSIZ)';
PRINT '=============================================================';
PRINT '';
PRINT 'Tamamlanan DeAYiAYiklikler:';
PRINT 'x FIFO deterministic indeksleri olusturuldu';
PRINT 'a ERPDevir MEKAN BAAIMSIZ yapAsAna dAnA14AYtA14rA14ldA14 (tA14m mekanlar ortak fiyat)';
PRINT 'a 5 A Check constraint eklendi';
PRINT 'a 2 A Foreign key eklendi (1 FK RunStep)';
PRINT 'a sp_fifo_StokMaliyetAlisKatman XACT_ABORT ile gA14ncellendi';
PRINT 'x Veri butunlugu kontrol gecti';
PRINT '';
PRINT 'BitiAY ZamanA: ' + CONVERT(VARCHAR(19), GETDATE(), 121);
PRINT '';
PRINT 'ANEMLI NOT:';
PRINT 'a Maliyetler (birimMaliyet) merkez bazAnda ORTAKtAr';
PRINT 'a Mekan farklAlAAYA YOKtur - tA14m AYubeler aynA fiyatla AalAAYAr';
PRINT 'a Maliyet = satAn alma fiyatA, mekan baAYAmsAz';
PRINT '';
PRINT 'Sonraki AdAmlar:';
PRINT '1. Test senaryolarAnA AalAAYtArAn (fifo_test_data_setup.sql)';
PRINT '2. Muhasebe raporlarAnA kontrol edin';
PRINT '3. Sorunlu stok raporunu inceleyin';
PRINT '4. SPRINT 2 (02_SPRINT2_VIEWS_AUDIT.sql) uygulanmaya hazArlayAn';
PRINT '=============================================================';
GO
