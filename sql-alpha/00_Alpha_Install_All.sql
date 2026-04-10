-- SQLCMD MODE GEREKIR (SSMS: Query > SQLCMD Mode)
-- Alpha kurulum scriptlerinin tek noktadan calistirilmasi

:r .\01_Baseline_Tables.sql
:r .\02_Baseline_CoreProcedures.sql
:r .\03_Baseline_BasicViews.sql
:r .\04_Alpha_SentetikFallback.sql
:r .\05_Alpha_AylikRutinAlpha.sql

PRINT 'SQL Alpha Install All tamamlandi.';
GO

