-- =============================================================
-- BKM FIFO - POST DEPLOY VALIDATION (NON-DESTRUCTIVE)
-- SQL Server 2016+
-- =============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '========================================';
PRINT 'BKM FIFO VALIDATION';
PRINT '========================================';
PRINT '';

DECLARE @hasError BIT = 0;

-- 1) Required objects
PRINT '1) Required objects';
DECLARE @missing TABLE (
    objectName SYSNAME NOT NULL,
    objectType VARCHAR(20) NOT NULL
);

IF OBJECT_ID('bkm.fifo_SabitFiyat', 'U') IS NULL
BEGIN
    INSERT INTO @missing (objectName, objectType) VALUES ('bkm.fifo_SabitFiyat', 'TABLE');
    SET @hasError = 1;
END
IF OBJECT_ID('bkm.sp_fifo_StokMaliyetAcilis', 'P') IS NULL
BEGIN
    INSERT INTO @missing (objectName, objectType) VALUES ('bkm.sp_fifo_StokMaliyetAcilis', 'PROC');
    SET @hasError = 1;
END
IF OBJECT_ID('bkm.sp_fifo_StokMaliyetAlisKatman', 'P') IS NULL
BEGIN
    INSERT INTO @missing (objectName, objectType) VALUES ('bkm.sp_fifo_StokMaliyetAlisKatman', 'PROC');
    SET @hasError = 1;
END
IF OBJECT_ID('bkm.sp_fifo_StokMaliyetFIFOCikis', 'P') IS NULL
BEGIN
    INSERT INTO @missing (objectName, objectType) VALUES ('bkm.sp_fifo_StokMaliyetFIFOCikis', 'PROC');
    SET @hasError = 1;
END
IF OBJECT_ID('bkm.sp_fifo_StokMaliyetCalistir', 'P') IS NULL
BEGIN
    INSERT INTO @missing (objectName, objectType) VALUES ('bkm.sp_fifo_StokMaliyetCalistir', 'PROC');
    SET @hasError = 1;
END

IF EXISTS (SELECT 1 FROM @missing)
BEGIN
    PRINT 'Missing required objects:';
    SELECT objectType, objectName FROM @missing ORDER BY objectType, objectName;
END
ELSE
BEGIN
    PRINT 'OK';
END
PRINT '';

-- 2) Duplicate names across object types
PRINT '2) Duplicate names across object types';
IF OBJECT_ID('tempdb..#dupNames', 'U') IS NOT NULL DROP TABLE #dupNames;

SELECT
    s.name AS schemaName,
    o.name AS objectName
INTO #dupNames
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.type IN ('U','P','V','FN','IF','TF','TR')
GROUP BY s.name, o.name
HAVING COUNT(*) > 1;

IF EXISTS (SELECT 1 FROM #dupNames)
BEGIN
    SET @hasError = 1;
    PRINT 'Duplicate names found:';
    SELECT d.schemaName, d.objectName, o.type
    FROM #dupNames d
    JOIN sys.objects o
      ON o.name = d.objectName
     AND o.schema_id = SCHEMA_ID(d.schemaName)
    WHERE o.type IN ('U','P','V','FN','IF','TF','TR')
    ORDER BY d.schemaName, d.objectName, o.type;
END
ELSE
BEGIN
    PRINT 'OK';
END
PRINT '';

-- 3) Unresolved dependencies
PRINT '3) Unresolved dependencies';
IF OBJECT_ID('tempdb..#deps', 'U') IS NOT NULL DROP TABLE #deps;

SELECT
    OBJECT_SCHEMA_NAME(d.referencing_id) AS schemaName,
    OBJECT_NAME(d.referencing_id) AS objectName,
    d.referenced_schema_name,
    d.referenced_entity_name,
    d.referenced_server_name,
    d.referenced_database_name
INTO #deps
FROM sys.sql_expression_dependencies d
WHERE d.referenced_id IS NULL
  AND d.is_ambiguous = 0
  AND d.referenced_entity_name IS NOT NULL;

IF EXISTS (SELECT 1 FROM #deps)
BEGIN
    SET @hasError = 1;
    PRINT 'Unresolved dependencies found:';
    SELECT *
    FROM #deps
    ORDER BY schemaName, objectName, referenced_schema_name, referenced_entity_name;
END
ELSE
BEGIN
    PRINT 'OK';
END
PRINT '';

-- 4) Proc standards
PRINT '4) Proc standards';
DECLARE @procCheck TABLE (
    procName SYSNAME NOT NULL,
    hasDefinition BIT NOT NULL,
    hasXactAbort BIT NOT NULL,
    hasRaiseError BIT NOT NULL,
    hasCatch BIT NOT NULL,
    hasThrow BIT NOT NULL
);

WITH targets AS (
    SELECT 'bkm.sp_fifo_StokMaliyetAcilis' AS procName UNION ALL
    SELECT 'bkm.sp_fifo_StokMaliyetAlisKatman' UNION ALL
    SELECT 'bkm.sp_fifo_StokMaliyetFIFOCikis' UNION ALL
    SELECT 'bkm.sp_fifo_StokMaliyetCalistir'
)
INSERT INTO @procCheck (procName, hasDefinition, hasXactAbort, hasRaiseError, hasCatch, hasThrow)
SELECT
    t.procName,
    CASE WHEN m.definition IS NULL THEN 0 ELSE 1 END AS hasDefinition,
    CASE WHEN m.definition LIKE '%SET XACT_ABORT ON%' THEN 1 ELSE 0 END AS hasXactAbort,
    CASE WHEN m.definition LIKE '%RAISERROR%' THEN 1 ELSE 0 END AS hasRaiseError,
    CASE WHEN m.definition LIKE '%BEGIN CATCH%' THEN 1 ELSE 0 END AS hasCatch,
    CASE WHEN m.definition LIKE '%THROW%' THEN 1 ELSE 0 END AS hasThrow
FROM targets t
LEFT JOIN sys.objects o ON o.object_id = OBJECT_ID(t.procName)
LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id;

IF EXISTS (
    SELECT 1
    FROM @procCheck
    WHERE hasDefinition = 0
       OR hasXactAbort = 0
       OR hasRaiseError = 1
       OR hasCatch = 0
       OR hasThrow = 0
)
BEGIN
    SET @hasError = 1;
    PRINT 'Proc standard violations:';
    SELECT
        procName,
        hasDefinition,
        hasXactAbort,
        hasRaiseError,
        hasCatch,
        hasThrow
    FROM @procCheck
    WHERE hasDefinition = 0
       OR hasXactAbort = 0
       OR hasRaiseError = 1
       OR hasCatch = 0
       OR hasThrow = 0
    ORDER BY procName;
END
ELSE
BEGIN
    PRINT 'OK';
END
PRINT '';

-- 5) View compile check
PRINT '5) View compile check';
DECLARE @views TABLE (
    schemaName SYSNAME NOT NULL,
    viewName SYSNAME NOT NULL
);

-- Optional explicit list can be inserted here; default is all bkm views.
IF NOT EXISTS (SELECT 1 FROM @views)
BEGIN
    INSERT INTO @views (schemaName, viewName)
    SELECT s.name, v.name
    FROM sys.views v
    JOIN sys.schemas s ON s.schema_id = v.schema_id
    WHERE s.name = 'bkm'
    ORDER BY s.name, v.name;
END

DECLARE @viewSchema SYSNAME;
DECLARE @viewName SYSNAME;
DECLARE @viewSql NVARCHAR(MAX);
DECLARE @viewChecked INT = 0;
DECLARE @viewFailed INT = 0;

DECLARE view_cursor CURSOR LOCAL FAST_FORWARD
FOR SELECT schemaName, viewName FROM @views ORDER BY schemaName, viewName;

OPEN view_cursor;
FETCH NEXT FROM view_cursor INTO @viewSchema, @viewName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @viewChecked = @viewChecked + 1;
    BEGIN TRY
        SET @viewSql = N'SELECT TOP (0) * FROM ' + QUOTENAME(@viewSchema) + N'.' + QUOTENAME(@viewName) + N';';
        EXEC sp_executesql @viewSql;
    END TRY
    BEGIN CATCH
        SET @hasError = 1;
        SET @viewFailed = @viewFailed + 1;
        PRINT 'View compile failed: ' + QUOTENAME(@viewSchema) + '.' + QUOTENAME(@viewName);
        PRINT ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM view_cursor INTO @viewSchema, @viewName;
END
CLOSE view_cursor;
DEALLOCATE view_cursor;

IF @viewChecked = 0
    PRINT 'No views found for validation.';
ELSE
    PRINT 'Views checked: ' + CAST(@viewChecked AS VARCHAR(10)) + ', failures: ' + CAST(@viewFailed AS VARCHAR(10));
PRINT '';

-- 6) FIFO sanity checks (negative values)
PRINT '6) FIFO sanity checks (negative values)';
DECLARE @cols TABLE (
    schemaName SYSNAME NOT NULL,
    tableName SYSNAME NOT NULL,
    columnName SYSNAME NOT NULL
);

INSERT INTO @cols (schemaName, tableName, columnName)
SELECT
    s.name AS schemaName,
    t.name AS tableName,
    c.name AS columnName
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE s.name = 'bkm'
  AND t.name LIKE 'fifo[_]%'
  AND ty.name IN ('int','bigint','smallint','tinyint','decimal','numeric','money','smallmoney','float','real')
  AND (
      c.name LIKE '%Miktar%'
      OR c.name LIKE '%Adet%'
      OR c.name LIKE '%Tutar%'
      OR c.name LIKE '%ToplamTutar%'
      OR c.name LIKE '%Maliyet%'
      OR c.name LIKE '%BakiyeMiktar%'
  );

IF NOT EXISTS (SELECT 1 FROM @cols)
BEGIN
    PRINT 'No eligible columns found.';
END
ELSE
BEGIN
    IF OBJECT_ID('tempdb..#negatives', 'U') IS NOT NULL DROP TABLE #negatives;
    CREATE TABLE #negatives (
        schemaName SYSNAME NOT NULL,
        tableName SYSNAME NOT NULL,
        columnName SYSNAME NOT NULL
    );

    DECLARE @colSchema SYSNAME;
    DECLARE @colTable SYSNAME;
    DECLARE @colName SYSNAME;
    DECLARE @colSql NVARCHAR(MAX);

    DECLARE col_cursor CURSOR LOCAL FAST_FORWARD
    FOR SELECT schemaName, tableName, columnName FROM @cols ORDER BY schemaName, tableName, columnName;

    OPEN col_cursor;
    FETCH NEXT FROM col_cursor INTO @colSchema, @colTable, @colName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @colSql = N'IF EXISTS (SELECT 1 FROM ' + QUOTENAME(@colSchema) + N'.' + QUOTENAME(@colTable)
                        + N' WHERE ' + QUOTENAME(@colName) + N' < 0) '
                        + N'INSERT INTO #negatives (schemaName, tableName, columnName) '
                        + N'VALUES (@schemaName, @tableName, @columnName);';
            EXEC sp_executesql
                @colSql,
                N'@schemaName SYSNAME, @tableName SYSNAME, @columnName SYSNAME',
                @schemaName = @colSchema,
                @tableName = @colTable,
                @columnName = @colName;
        END TRY
        BEGIN CATCH
            PRINT 'INFO: Negative check skipped for ' + QUOTENAME(@colSchema) + '.' + QUOTENAME(@colTable)
                + '.' + QUOTENAME(@colName) + ' - ' + ERROR_MESSAGE();
        END CATCH
        FETCH NEXT FROM col_cursor INTO @colSchema, @colTable, @colName;
    END
    CLOSE col_cursor;
    DEALLOCATE col_cursor;

    IF EXISTS (SELECT 1 FROM #negatives)
    BEGIN
        SET @hasError = 1;
        PRINT 'Negative values found:';
        SELECT schemaName, tableName, columnName FROM #negatives ORDER BY schemaName, tableName, columnName;
    END
    ELSE
    BEGIN
        PRINT 'OK';
    END
END

PRINT '';

IF @hasError = 1
BEGIN
    PRINT 'Validation failed.';
    THROW 51007, 'Validation failed. Review output.', 1;
END
ELSE
BEGIN
    PRINT 'Validation succeeded.';
END
GO
