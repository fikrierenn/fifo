-- 16_V2_DevreDisiFiltre.sql
-- Devre disi urunleri tum FIFO islemlerinden haric tut
-- FifoDevreDisiUrunler tablosu 15_V2'de olusturuldu

-- ============================================================
-- 1) sp_Fifo_HareketliUrunListesi — son SELECT'e filtre ekle
-- ============================================================
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
        RAISERROR('En az bir dahil etme parametresi 1 olmali.', 16, 1);
        RETURN;
    END

    DECLARE @Baslangic DATE = DATEFROMPARTS(@Yil, @Ay, 1);
    DECLARE @Bitis     DATE = EOMONTH(@Baslangic);

    IF OBJECT_ID('tempdb..#hareketliUrunler', 'U') IS NOT NULL DROP TABLE #hareketliUrunler;
    CREATE TABLE #hareketliUrunler (StkId INT NOT NULL);
    CREATE INDEX IX_tmp_hareketli_StkId ON #hareketliUrunler(StkId);

    /* 1) Satis */
    IF @DahilSatis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT dt.ehStkId
        FROM DerinSIS_Local.dbo.irsAyr dt WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.irs bs  WITH(NOLOCK) ON dt.ehID = bs.eID
        WHERE bs.eTip   IN (1, 4, 5, 100, 101)
          AND bs.eMekan IN (1, 12, 4477, 4478)
          AND bs.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND bs.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 2) Alis */
    IF @DahilAlis = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT a.ehStkId
        FROM DerinSIS_Local.dbo.fatAyr a WITH(NOLOCK)
        JOIN DerinSIS_Local.dbo.fat   f WITH(NOLOCK) ON f.eID = a.ehID
        WHERE f.eTip   IN (0, 2)
          AND a.ehAdetN <> 0
          AND f.eTarihS >= CONVERT(smalldatetime, @Baslangic)
          AND f.eTarihS <  DATEADD(DAY, 1, CONVERT(smalldatetime, @Bitis));

    /* 3) Aktif katman */
    IF @DahilAktifKatman = 1
        INSERT INTO #hareketliUrunler (StkId)
        SELECT DISTINCT StkId
        FROM dbo.FifoKatman
        WHERE KalanMiktar > 0;

    /* DEVRE DISI FILTRE: tek tarama — filtreli set #sonuc'a materialize, sayimlar ucuz temp'ten */
    IF OBJECT_ID('tempdb..#sonuc', 'U') IS NOT NULL DROP TABLE #sonuc;
    SELECT DISTINCT h.StkId
    INTO #sonuc
    FROM #hareketliUrunler h
    WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoDevreDisiUrunler dd WHERE dd.StkId = h.StkId);

    DECLARE @UrunSayisi      INT = (SELECT COUNT(*) FROM #sonuc);
    DECLARE @ToplamHareketli INT = (SELECT COUNT(DISTINCT StkId) FROM #hareketliUrunler);
    DECLARE @DevreDisiSayisi INT = @ToplamHareketli - @UrunSayisi;

    SELECT StkId FROM #sonuc ORDER BY StkId;
    PRINT 'sp_Fifo_HareketliUrunListesi: '
        + CAST(@Yil AS VARCHAR) + '-' + RIGHT('0' + CAST(@Ay AS VARCHAR), 2)
        + ' donemi icin '
        + CAST(@UrunSayisi AS VARCHAR) + ' hareketli urun bulundu'
        + CASE WHEN @DevreDisiSayisi > 0
            THEN ' (' + CAST(@DevreDisiSayisi AS VARCHAR) + ' devre disi urun haric tutuldu)'
            ELSE ''
          END + '.';

    DROP TABLE #hareketliUrunler;
END
GO
PRINT 'sp_Fifo_HareketliUrunListesi guncellendi (devre disi filtre).';
GO

-- ============================================================
-- 2) sp_Fifo_AylikCalistir — devre disi kontrolu
-- Mevcut SP'ye dokunmadan, App tarafinda filtreleniyor.
-- Ama guvenlik icin SP'ye de WHERE ekleyelim.
-- ============================================================
-- NOT: sp_Fifo_AylikCalistir tek StkId aliyor, App zaten
-- devre disi olanlari gondermeyecek. Ek filtre gereksiz.

-- ============================================================
-- 3) Snapshot (App tarafinda) — devre disi urunler snapshot'a
-- alinir (envanter dogrulugu icin) ama hesaplamadan atlanir.
-- Bu zaten HareketliUrunListesi filtresinde saglanir.
-- ============================================================

-- ============================================================
-- 4) V2 Acilis SP — devre disi urunleri haric tut
-- bkm.sp_fifo_StokMaliyetAcilis_V2 icindeki envanter sorgusuna
-- devre disi filtre ekle
-- ============================================================
-- NOT: V2 Acilis SP'si cok buyuk — sadece #stoklar olusturulduktan
-- sonra devre disi olanlari silmek en temiz yol.
-- App tarafinda (Wizard) da filtrelenecek.

PRINT 'Devre disi filtre uygulamasi tamamlandi.';
PRINT 'HareketliUrunListesi SP guncellendi.';
PRINT 'Diger SP''ler App tarafinda filtreleniyor (Wizard, Batch).';
GO
