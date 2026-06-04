USE BKMMaliyet;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO
SET NOCOUNT ON;
GO

/* ============================================================
   ORTALAMA AYLIK MALIYET
   Tablo + sp_Ortalama_AylikHesapla

   FIFO ile paralel calisir:
     - Acilis: FifoAcilisEnvanter + FifoKatman agirlikli ort.
     - Aylik alislar: DerinSIS_Local.dbo.fat + fatAyr
     - Ay sonu stok: DerinSIS_Local.dbo.irsHrk
     - Formula: (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)

   PK: (YilAy, StkId) -- FifoKatman gibi lokasyon aggregate
   ============================================================ */

/* -------- TABLO -------- */
IF OBJECT_ID('dbo.OrtalamaAylikMaliyet', 'U') IS NOT NULL
    DROP TABLE dbo.OrtalamaAylikMaliyet;
GO

CREATE TABLE dbo.OrtalamaAylikMaliyet (
    YilAy               INT             NOT NULL,  -- YYYYMM (ornek: 202601)
    StkId               INT             NOT NULL,
    AyBasiMiktar        DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AyBasiMiktar  DEFAULT 0,
    AyBasiTutar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AyBasiTutar   DEFAULT 0,
    GirisMiktar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_GirisMiktar   DEFAULT 0,
    GirisTutar          DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_GirisTutar    DEFAULT 0,
    CikisMiktar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_CikisMiktar   DEFAULT 0,
    AySonuMiktar        DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AySonuMiktar  DEFAULT 0,
    AySonuBirimMaliyet  DECIMAL(18,6)   NOT NULL CONSTRAINT DF_OAM_AySonuBMal   DEFAULT 0,
    AySonuTutar         DECIMAL(18,4)   NOT NULL CONSTRAINT DF_OAM_AySonuTutar   DEFAULT 0,
    CreateUtc           DATETIME2(0)    NOT NULL CONSTRAINT DF_OAM_CreateUtc     DEFAULT GETUTCDATE(),
    UpdateUtc           DATETIME2(0)    NOT NULL CONSTRAINT DF_OAM_UpdateUtc     DEFAULT GETUTCDATE(),
    CONSTRAINT PK_OrtalamaAylikMaliyet PRIMARY KEY (YilAy, StkId)
);
GO

CREATE INDEX IX_OAM_StkIdYilAy
    ON dbo.OrtalamaAylikMaliyet(StkId, YilAy)
    INCLUDE (AySonuMiktar, AySonuBirimMaliyet, AySonuTutar);
GO

PRINT 'dbo.OrtalamaAylikMaliyet olusturuldu.';
GO

/* -------- STORED PROCEDURE -------- */
CREATE OR ALTER PROCEDURE dbo.sp_Ortalama_AylikHesapla
(
    @Yil            INT,
    @Ay             INT,
    @AcilisTarihi   DATE            = NULL,     -- Sadece ilk ay: FIFO acilis tarihi
    @StkId          INT             = NULL,     -- NULL = tum urunler
    @IslemId        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* --- Parametre validasyonu --- */
    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    DECLARE @YilAy       INT  = @Yil * 100 + @Ay;
    DECLARE @AyBas       DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @AySonu      DATE = EOMONTH(@AyBas);
    DECLARE @OncekiYilAy INT  = CASE WHEN @Ay = 1
                                     THEN (@Yil - 1) * 100 + 12
                                     ELSE @YilAy - 1 END;

    IF @IslemId IS NOT NULL
        EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
             10, 'CALISIYOR', NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ================================================
           ADIM 1: Ay basi bakiyesi
           - Onceki ay kaydi varsa: OrtalamaAylikMaliyet'ten
           - Yoksa ve @AcilisTarihi verilmisse: FIFO katmanindan
           ================================================ */
        IF OBJECT_ID('tempdb..#ayBas', 'U') IS NOT NULL DROP TABLE #ayBas;
        CREATE TABLE #ayBas (StkId INT NOT NULL PRIMARY KEY,
                             Miktar DECIMAL(18,4) NOT NULL,
                             Tutar  DECIMAL(18,4) NOT NULL);

        IF EXISTS (
            SELECT 1 FROM dbo.OrtalamaAylikMaliyet
            WHERE YilAy = @OncekiYilAy
              AND (@StkId IS NULL OR StkId = @StkId)
        )
        BEGIN
            INSERT INTO #ayBas (StkId, Miktar, Tutar)
            SELECT StkId, AySonuMiktar, AySonuTutar
            FROM   dbo.OrtalamaAylikMaliyet
            WHERE  YilAy = @OncekiYilAy
              AND  (@StkId IS NULL OR StkId = @StkId)
              AND  AySonuMiktar > 0;

            PRINT CONCAT('[1/4] Ay basi: onceki ay (', @OncekiYilAy, ') kaydindan alindi. ',
                         @@ROWCOUNT, ' urun.');
        END
        ELSE IF @AcilisTarihi IS NOT NULL
        BEGIN
            /* FifoAcilisEnvanter miktar + FifoKatman agirlikli ort birim maliyet */
            INSERT INTO #ayBas (StkId, Miktar, Tutar)
            SELECT
                e.StkId,
                SUM(e.StokMiktar) AS Miktar,
                SUM(e.StokMiktar) * ISNULL(k.OrtBirimMaliyet, 0) AS Tutar
            FROM dbo.FifoAcilisEnvanter e
            LEFT JOIN (
                SELECT
                    StkId,
                    SUM(GirisMiktar * BirimMaliyet) / NULLIF(SUM(GirisMiktar), 0)
                        AS OrtBirimMaliyet
                FROM  dbo.FifoKatman
                WHERE KaynakTip IN ('ACILIS', 'ACILIS_TAMAMLA')
                  AND GirisTarihi = @AcilisTarihi
                  AND (@StkId IS NULL OR StkId = @StkId)
                GROUP BY StkId
            ) k ON k.StkId = e.StkId
            WHERE e.EnvanterTarihi = @AcilisTarihi
              AND (@StkId IS NULL OR e.StkId = @StkId)
              AND e.StokMiktar > 0
            GROUP BY e.StkId, k.OrtBirimMaliyet;

            PRINT CONCAT('[1/4] Ay basi: FIFO acilis (', @AcilisTarihi, ') katmanindan alindi. ',
                         @@ROWCOUNT, ' urun.');
        END
        ELSE
        BEGIN
            PRINT '[1/4] Ay basi: onceki ay yok, AcilisTarihi verilmedi. Sifir baslangic.';
        END

        /* ================================================
           ADIM 2: Ay ici alislar (fat + fatAyr, eTip IN 0/2)
           eGC=0 normal alis, eGC=1 alis iadesi (negatif)
           ================================================ */
        IF OBJECT_ID('tempdb..#giris', 'U') IS NOT NULL DROP TABLE #giris;
        SELECT
            a.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4),
                a.ehAdetN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END
            )) AS GirisMiktar,
            SUM(CONVERT(DECIMAL(18,4),
                a.ehTutarN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END
            )) AS GirisTutar
        INTO #giris
        FROM DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.fat    f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE f.eTip IN (0, 2)
          AND a.ehAdetN <> 0
          AND f.eTarihS >= CONVERT(smalldatetime, @AyBas)
          AND f.eTarihS <  CONVERT(smalldatetime, DATEADD(DAY, 1, @AySonu))
          AND (@StkId IS NULL OR a.ehStkId = @StkId)
        GROUP BY a.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4),
                   a.ehAdetN * CASE WHEN f.eGC = 0 THEN 1 ELSE -1 END)) > 0;

        PRINT CONCAT('[2/4] Girisler: ', @@ROWCOUNT, ' urun icin ay ici alis alindi.');

        /* ================================================
           ADIM 3: Ay sonu stok (irsHrk kumulatif)
           ================================================ */
        IF OBJECT_ID('tempdb..#aySonu', 'U') IS NOT NULL DROP TABLE #aySonu;
        SELECT
            h.ehStkId AS StkId,
            SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) AS AySonuMiktar
        INTO #aySonu
        FROM DerinSIS_Local.dbo.irsHrk h WITH(NOLOCK)
        WHERE h.ehTrhS <= @AySonu
          AND h.ehMekan IN (1, 12, 4477, 4478)   -- FIX: FIFO ile ayni mekan havuzu (kural: ortak havuz)
          AND h.ehAltDepo = 0                      -- FIX: alt depo haric (FIFO acilis ile tutarli)
          AND (@StkId IS NULL OR h.ehStkId = @StkId)
        GROUP BY h.ehStkId
        HAVING SUM(CONVERT(DECIMAL(18,4), h.ehAdetN)) > 0;

        PRINT CONCAT('[3/4] Ay sonu stok: ', @@ROWCOUNT, ' urun.');

        /* ================================================
           ADIM 4: Hesapla + upsert
           Formula:
             AySonuBirimMaliyet = (AyBasiTutar + GirisTutar)
                                / NULLIF(AyBasiMiktar + GirisMiktar, 0)
             CikisMiktar        = AyBasiMiktar + GirisMiktar - AySonuMiktar
           ================================================ */
        DELETE FROM dbo.OrtalamaAylikMaliyet
        WHERE YilAy = @YilAy
          AND (@StkId IS NULL OR StkId = @StkId);

        INSERT INTO dbo.OrtalamaAylikMaliyet
            (YilAy, StkId,
             AyBasiMiktar, AyBasiTutar,
             GirisMiktar,  GirisTutar,
             CikisMiktar,
             AySonuMiktar, AySonuBirimMaliyet, AySonuTutar)
        SELECT
            @YilAy,
            StkId,
            AyBasiMiktar,
            AyBasiTutar,
            GirisMiktar,
            GirisTutar,
            /* Cikis = acilis + giris - aySonu (negatife dustugunde 0) */
            CASE WHEN AyBasiMiktar + GirisMiktar - AySonuMiktar < 0
                 THEN 0
                 ELSE AyBasiMiktar + GirisMiktar - AySonuMiktar END AS CikisMiktar,
            AySonuMiktar,
            /* Sifir bolme koruması: stok gelip tukenmisse onceki birim fiyat kalir */
            CASE
                WHEN AyBasiMiktar + GirisMiktar = 0 THEN 0
                ELSE (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)
            END AS AySonuBirimMaliyet,
            AySonuMiktar *
            CASE
                WHEN AyBasiMiktar + GirisMiktar = 0 THEN 0
                ELSE (AyBasiTutar + GirisTutar) / (AyBasiMiktar + GirisMiktar)
            END AS AySonuTutar
        FROM (
            SELECT
                ISNULL(b.StkId, ISNULL(g.StkId, s.StkId))   AS StkId,
                ISNULL(b.Miktar,      0)                       AS AyBasiMiktar,
                ISNULL(b.Tutar,       0)                       AS AyBasiTutar,
                ISNULL(g.GirisMiktar, 0)                       AS GirisMiktar,
                ISNULL(g.GirisTutar,  0)                       AS GirisTutar,
                ISNULL(s.AySonuMiktar,
                       ISNULL(b.Miktar, 0) + ISNULL(g.GirisMiktar, 0)
                )                                              AS AySonuMiktar
            FROM      #ayBas b
            FULL JOIN #giris g  ON g.StkId = b.StkId
            FULL JOIN #aySonu s ON s.StkId = ISNULL(b.StkId, g.StkId)
        ) calc
        WHERE AyBasiMiktar + GirisMiktar > 0;  -- kayda degmez satiri yazma

        PRINT CONCAT('[4/4] Upsert tamamlandi: ', @@ROWCOUNT, ' urun yazildi.');

        COMMIT TRANSACTION;

        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
                 10, 'TAMAMLANDI', NULL;

        PRINT CONCAT('sp_Ortalama_AylikHesapla tamamlandi. YilAy=', @YilAy);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @HataMesaji NVARCHAR(500) = ERROR_MESSAGE();
        IF @IslemId IS NOT NULL
            EXEC dbo.sp_MaliyetAdimYaz @IslemId, 'ort_hesapla', 'Ortalama maliyet hesaplama',
                 10, 'HATA', @HataMesaji;
        THROW;
    END CATCH
END
GO

PRINT 'dbo.sp_Ortalama_AylikHesapla olusturuldu.';
GO

/* -------- KONTROL SORGUSU -------- */
SELECT
    OBJECT_ID('dbo.OrtalamaAylikMaliyet', 'U')           AS tablo_var,
    OBJECT_ID('dbo.sp_Ortalama_AylikHesapla', 'P')       AS sp_var;
GO
