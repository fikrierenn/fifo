/* ============================================================================
   01a_V2_Tables_RESET.sql  —  YIKICI. TUM MALIYET DEFTERINI SILER.

   BU DOSYA MASTER'A DAHIL DEGILDIR (tools/build-master.sh SECTIONS listesinde yok).
   Sadece bos/atilabilir bir ortami sifirlamak icin elle calistirilir.

   NE SILER:
     FifoKatman        — FIFO maliyet katmanlari (maliyet defteri)
     FifoCikisDetay    — satilan mal maliyeti detayi
     FifoAcilisEnvanter, FifoSorunluStoklar, FifoFallbackFiyatlari
     MaliyetIslem, MaliyetIslemAdim — islem log / denetim izi

   KULLANIM (onay degiskeni ZORUNLU, HEDEF DB ADINI ICERIR):
     Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -Database 'BKMMaliyet_Test' `
       -InputFile '01a_V2_Tables_RESET.sql' -Variable "ConfirmDataLoss=EVET-SIL:BKMMaliyet_Test"

   ONAY DB ADINA BAGLIDIR: test icin yazilan komut baska bir DB'de CALISMAZ.
   Onay yanlis/eksikse script hicbir sey silmez, uyari basip cikar.

   DIKKAT: burada `USE BKMMaliyet;` YOKTUR ve OLMAMALIDIR. `USE`, cagiranin
   -Database parametresini ezer ve test icin yazilmis komutu uretim veritabanina
   yoneltirdi. Hedef DB'yi yalnizca cagiran belirler.

   Sonrasinda 01_V2_Tables.sql (veya master) tablolari yeniden olusturur.
   ============================================================================ */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @Onay     NVARCHAR(200) = N'$(ConfirmDataLoss)';
DECLARE @Beklenen NVARCHAR(200) = N'EVET-SIL:' + DB_NAME();

IF @Onay <> @Beklenen
BEGIN
    PRINT '============================================================';
    PRINT 'RESET IPTAL — onay eslesmedi. Hicbir tablo silinmedi.';
    PRINT 'Hedef DB : ' + DB_NAME();
    PRINT 'Beklenen : -Variable "ConfirmDataLoss=' + @Beklenen + '"';
    PRINT '============================================================';
END
ELSE
BEGIN
    DECLARE @katmanSayi   BIGINT = 0;
    DECLARE @cikisSayi    BIGINT = 0;

    IF OBJECT_ID('dbo.FifoKatman','U')     IS NOT NULL SELECT @katmanSayi = COUNT_BIG(*) FROM dbo.FifoKatman;
    IF OBJECT_ID('dbo.FifoCikisDetay','U') IS NOT NULL SELECT @cikisSayi  = COUNT_BIG(*) FROM dbo.FifoCikisDetay;

    PRINT '!!! YIKICI RESET BASLIYOR — DB: ' + DB_NAME();
    PRINT '!!! Silinecek katman satiri : ' + CAST(@katmanSayi AS VARCHAR(20));
    PRINT '!!! Silinecek cikis satiri  : ' + CAST(@cikisSayi  AS VARCHAR(20));

    /* Child-first drop (FK sirasi) */
    IF OBJECT_ID('dbo.MaliyetIslemAdim','U')      IS NOT NULL DROP TABLE dbo.MaliyetIslemAdim;
    IF OBJECT_ID('dbo.FifoCikisDetay','U')        IS NOT NULL DROP TABLE dbo.FifoCikisDetay;
    IF OBJECT_ID('dbo.FifoSorunluStoklar','U')    IS NOT NULL DROP TABLE dbo.FifoSorunluStoklar;
    IF OBJECT_ID('dbo.FifoAcilisEnvanter','U')    IS NOT NULL DROP TABLE dbo.FifoAcilisEnvanter;
    IF OBJECT_ID('dbo.FifoKatman','U')            IS NOT NULL DROP TABLE dbo.FifoKatman;
    IF OBJECT_ID('dbo.FifoFallbackFiyatlari','U') IS NOT NULL DROP TABLE dbo.FifoFallbackFiyatlari;
    IF OBJECT_ID('dbo.MaliyetIslem','U')          IS NOT NULL DROP TABLE dbo.MaliyetIslem;

    PRINT 'RESET tamamlandi. Simdi 01_V2_Tables.sql veya master ile tablolari yeniden olusturun.';
END
GO
