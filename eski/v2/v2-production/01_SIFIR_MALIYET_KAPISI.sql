/* §6 KAPISI — YALNIZ CONSTRAINT BLOKLARI
   Kaynak: v2-production/00_V2_MASTER_FULL.sql satir 83-127 ve 256-284 (birebir kopya).
   Hedef : BT-FIKRI . BKMMaliyet   (YEREL dev kopya — ERP DEGIL)
   Neden ayri dosya: master 4752 satir ve su an commit'siz 478+/202- degisiklik tasiyor;
   yalniz §6 kapisini kapatmak icin 27 objeyi deploy etmek gerekmez.
*/
USE BKMMaliyet;
GO
IF OBJECT_ID('dbo.FifoKatman','U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID('dbo.FifoKatman')
          AND name         = 'CK_FifoKatman_BirimMaliyet'
          AND definition   = '([BirimMaliyet]>(0))'
          AND is_disabled  = 0
          AND is_not_trusted = 0
   )
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.FifoKatman WHERE BirimMaliyet <= 0)
    BEGIN
        DECLARE @ihlal INT = (SELECT COUNT(*) FROM dbo.FifoKatman WHERE BirimMaliyet <= 0);
        PRINT '!!! UYARI: FifoKatman icinde BirimMaliyet <= 0 olan ' + CAST(@ihlal AS VARCHAR(20)) +
              ' satir var. CK_FifoKatman_BirimMaliyet KURULAMADI — §6 KAPISI ACIK.';
        PRINT '!!! Once bu satirlari fiyatlandirin (bkz. fifo-domain.md §6), sonra tekrar calistirin.';

        -- Uyari PRINT'te kalirsa otomasyonda kaybolur; kalici denetim izi birak.
        IF OBJECT_ID('dbo.FifoSorunluStoklar','U') IS NOT NULL
        BEGIN
            DELETE FROM dbo.FifoSorunluStoklar
            WHERE EnvanterTarihi = CAST('1900-01-01' AS DATE)
              AND MekanId = 0 AND StkId = 0 AND SorunTipi = 'CONSTRAINT_KURULAMADI';

            INSERT INTO dbo.FifoSorunluStoklar
                (StkId, EnvanterTarihi, MekanId, StokMiktar, SorunTipi, Aciklama)
            VALUES (0, CAST('1900-01-01' AS DATE), 0, 0, 'CONSTRAINT_KURULAMADI',
                    CONVERT(NVARCHAR(500),
                        CONCAT(N'CK_FifoKatman_BirimMaliyet kurulamadi: BirimMaliyet<=0 satir sayisi ',
                               @ihlal, N'. Deploy devam etti, §6 kapisi ACIK.')));
        END
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE parent_object_id = OBJECT_ID('dbo.FifoKatman')
                     AND name = 'CK_FifoKatman_BirimMaliyet')
            ALTER TABLE dbo.FifoKatman DROP CONSTRAINT CK_FifoKatman_BirimMaliyet;

        ALTER TABLE dbo.FifoKatman WITH CHECK
            ADD CONSTRAINT CK_FifoKatman_BirimMaliyet CHECK (BirimMaliyet > 0);
        PRINT 'CK_FifoKatman_BirimMaliyet kuruldu/sikilastirildi: BirimMaliyet > 0.';
    END
END
GO
IF OBJECT_ID('dbo.FifoCikisDetay','U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID('dbo.FifoCikisDetay')
          AND name           = 'CK_FifoCikisDetay_BirimMaliyet'
          AND definition     = '([BirimMaliyet]>(0))'
          AND is_disabled    = 0
          AND is_not_trusted = 0
   )
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0)
    BEGIN
        DECLARE @ihlalCikis INT = (SELECT COUNT(*) FROM dbo.FifoCikisDetay WHERE BirimMaliyet <= 0);
        PRINT '!!! UYARI: FifoCikisDetay icinde BirimMaliyet <= 0 olan ' + CAST(@ihlalCikis AS VARCHAR(20)) +
              ' satir var. CK_FifoCikisDetay_BirimMaliyet KURULAMADI — §6 kapisi cikis tarafinda ACIK.';
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.check_constraints
                   WHERE parent_object_id = OBJECT_ID('dbo.FifoCikisDetay')
                     AND name = 'CK_FifoCikisDetay_BirimMaliyet')
            ALTER TABLE dbo.FifoCikisDetay DROP CONSTRAINT CK_FifoCikisDetay_BirimMaliyet;

        ALTER TABLE dbo.FifoCikisDetay WITH CHECK
            ADD CONSTRAINT CK_FifoCikisDetay_BirimMaliyet CHECK (BirimMaliyet > 0);
        PRINT 'CK_FifoCikisDetay_BirimMaliyet kuruldu: BirimMaliyet > 0.';
    END
END
GO
