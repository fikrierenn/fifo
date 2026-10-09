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
PRINT '========================================';
PRINT 'FIFO V2 (dbo) master deploy basliyor...';
PRINT '========================================';
GO
:r .\01_V2_Tables.sql
:r .\02_V2_CoreProcedures.sql
:r .\03_V2_Views.sql
:r .\04_V2_SentetikFallback.sql
:r .\05_V2_AylikRutinFull.sql
:r .\07_V2_HareketliUrunListesi.sql
:r .\09_V2_BatchOrchestration.sql
GO
PRINT '========================================';
PRINT 'FIFO V2 (dbo) master deploy tamamlandi.';
PRINT '========================================';
GO
