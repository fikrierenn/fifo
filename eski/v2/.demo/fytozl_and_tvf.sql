/* DerinSIS_Local — fiyat tablosu fytOzl + gerçek fn_SonGecerliFiyat(_Adv) (stub yerine).
   Canliden replike. Sadece demo. */
USE DerinSIS_Local;
GO

IF OBJECT_ID('dbo.fytOzl','U') IS NOT NULL DROP TABLE dbo.fytOzl;
CREATE TABLE dbo.fytOzl (
    fID          INT           NOT NULL,
    fhID         INT           NOT NULL,
    fStkID       INT           NOT NULL,
    fTarih       SMALLDATETIME NOT NULL,
    fTarihSon    SMALLDATETIME NULL,
    fTur         TINYINT       NOT NULL,
    fTip         INT           NOT NULL,
    sonrakiFiyat DECIMAL(15,4) NOT NULL,
    fInd1        DECIMAL(5,2)  NOT NULL,
    fInd2        DECIMAL(5,2)  NOT NULL,
    fInd3        DECIMAL(5,2)  NOT NULL,
    fInd4        DECIMAL(5,2)  NOT NULL,
    fInd5        DECIMAL(5,2)  NOT NULL,
    fFrmID       INT           NOT NULL,
    onay         TINYINT       NOT NULL
);
GO
-- TVF index hint'inin cozulebilmesi icin AYNI isimle index (fonksiyon WITH(INDEX(...)) kullaniyor)
CREATE INDEX IX_fytOzl_SonKayit_Seek
    ON dbo.fytOzl(fTip, fTur, fStkID, fTarih DESC)
    INCLUDE (fID, fFrmID, onay, sonrakiFiyat, fTarihSon, fhID, fInd1, fInd2, fInd3, fInd4, fInd5);
GO

-- Gercek _Adv (canlidan birebir)
CREATE OR ALTER FUNCTION bkm.fn_SonGecerliFiyat_Adv
( @AsOf smalldatetime, @FiyatTuru int, @FiyatTipi int, @OnayliMi bit )
RETURNS TABLE AS RETURN
(
    WITH A AS (
        SELECT f.fhID, f.fStkID, f.fTarih, f.fTur, f.sonrakiFiyat, f.fTarihSon, f.fTip,
               f.fInd1, f.fInd2, f.fInd3, f.fInd4, f.fInd5, f.fFrmID,
               rn = ROW_NUMBER() OVER (
                   PARTITION BY f.fStkID
                   ORDER BY CASE WHEN f.fFrmID = 9525 THEN 0 ELSE 1 END, f.fTarih DESC, f.fID DESC)
        FROM dbo.fytOzl f WITH (INDEX(IX_fytOzl_SonKayit_Seek))
        WHERE f.fTip = @FiyatTipi AND f.fTur = @FiyatTuru AND f.fTarih <= @AsOf
          AND (@OnayliMi = 0 OR f.onay = 1)
    )
    SELECT fhID, fStkID, fTarih, fTur, sonrakiFiyat, fTarihSon, fTip,
           fInd1, fInd2, fInd3, fInd4, fInd5, fFrmID,
           CAST(sonrakiFiyat
                * (100.0 - ISNULL(fInd1,0))/100.0
                * (100.0 - ISNULL(fInd2,0))/100.0
                * (100.0 - ISNULL(fInd3,0))/100.0
                * (100.0 - ISNULL(fInd4,0))/100.0
                * (100.0 - ISNULL(fInd5,0))/100.0 AS decimal(15,4)) AS sonrakiNet
    FROM A WHERE rn = 1
);
GO

-- Gercek basic wrapper
CREATE OR ALTER FUNCTION bkm.fn_SonGecerliFiyat
( @AsOf smalldatetime, @FiyatTuru int )
RETURNS TABLE AS RETURN
( SELECT * FROM bkm.fn_SonGecerliFiyat_Adv(@AsOf, @FiyatTuru, 1, 1) );
GO
PRINT 'fytOzl + gercek fn_SonGecerliFiyat(_Adv) kuruldu.';
GO
