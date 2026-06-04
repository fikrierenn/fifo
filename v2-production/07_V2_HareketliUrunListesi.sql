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

-- =============================================================
-- V2-03: Hareketli Urun Listesi
-- Aylik rutin icin incremental urun secimi.
-- Tum urunler yerine sadece verilen ay icinde hareketi olan
-- urunleri dondurur. Batch orchestrator bu listeyi alir,
-- stkID batch'lerine boler ve sp_Fifo_AylikCalistir'i cagirir.
--
-- Parametreler:
--   @Yil, @Ay          : Calistirilacak donem
--   @DahilSatis        : irs/irsAyr satis hareketlerini dahil et (default 1)
--   @DahilAlis         : fat/fatAyr alis faturalarini dahil et (default 1)
--   @DahilAktifKatman  : Aktif FifoKatman'i olan urunleri de dahil et (default 0,
--                        genis filtre - genellikle gerek yok)
-- =============================================================

CREATE OR ALTER PROCEDURE dbo.sp_Fifo_HareketliUrunListesi
(
    @Yil               INT,
    @Ay                INT,
    @DahilSatis        BIT = 1,
    @DahilAlis         BIT = 1,
    @DahilAktifKatman  BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Yil IS NULL OR @Ay IS NULL OR @Ay NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR('Gecersiz yil/ay parametresi.', 16, 1);
        RETURN;
    END

    IF @DahilSatis = 0 AND @DahilAlis = 0 AND @DahilAktifKatman = 0
    BEGIN
        RAISERROR('En az bir dahil etme parametresi (DahilSatis/DahilAlis/DahilAktifKatman) 1 olmali.', 16, 1);
        RETURN;
    END

    DECLARE @Baslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @Bitis     DATE = EOMONTH(@Baslangic);

    IF OBJECT_ID('tempdb..#hareketliUrunler', 'U') IS NOT NULL DROP TABLE #hareketliUrunler;
    CREATE TABLE #hareketliUrunler (StkId INT NOT NULL);
    CREATE INDEX IX_tmp_hareketli_StkId ON #hareketliUrunler(StkId);

    /* 1) Satis: irs + irsAyr, sadece taninan mekanlar */
    IF @DahilSatis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT dt.ehStkId
        FROM DerinSIS_Local.dbo.irsAyr dt WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.irs bs  WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip   IN (1, 4, 5, 100, 101)
          AND bs.eMekan IN (1, 12, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 2) Alis: fat + fatAyr (satin alma faturalari, tip 0=alis, 2=iade) */
    IF @DahilAlis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT a.ehStkId
        FROM DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.fat   f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE f.eTip   IN (0, 2)
          AND a.ehAdetN <> 0
          AND f.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 3) Aktif katman (opsiyonel - genis filtre, katman kapatilmamis tum urunler) */
    IF @DahilAktifKatman = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT StkId
        FROM dbo.FifoKatman
        WHERE KalanMiktar > 0;

    SELECT DISTINCT StkId
    FROM #hareketliUrunler
    ORDER BY StkId;

    DECLARE @UrunSayisi INT = (SELECT COUNT(DISTINCT StkId) FROM #hareketliUrunler);
    PRINT 'sp_Fifo_HareketliUrunListesi: '
        + CAST(@Yil AS VARCHAR) + '-' + RIGHT('0' + CAST(@Ay AS VARCHAR), 2)
        + ' donemi icin '
        + CAST(@UrunSayisi AS VARCHAR)
        + ' hareketli urun bulundu.';

    DROP TABLE #hareketliUrunler;
END
GO

PRINT 'sp_Fifo_HareketliUrunListesi proseduru olusturuldu';
GO
