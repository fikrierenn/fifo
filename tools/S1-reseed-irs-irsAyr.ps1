# =============================================================================
# S1-reseed-irs-irsAyr.ps1  —  Uretim master DOGRULAMA ortami icin irs+irsAyr re-seed
# Plan: docs/PLAN-uretim-master-deploy.md S1.
#
# Neden: disk-temizliginde irs (stub: sadece eID,eMekan) + irsAyr (DROP) gitti.
# Acilis SP irs.eTip/eTarih/eMekan + irsAyr(ehID,ehSira) bridge ister. Cikis irsHrk
# kullanir (lokalde 58M, var) → irsAyr SADECE ALIS bridge'i icin gerekli.
# Minimal kolon + ALIS-only (eTip 0,2,10,3,6,102,103) 2021-05-31+ → irs 290K / irsAyr 4.6M.
#
# Kaynak 201 conn sqlcli.json'dan RUNTIME okunur (sifre hardcode YOK).
# Hedef: BT-FIKRI / DerinSIS_Local.
# =============================================================================
$ErrorActionPreference = 'Stop'
$cfg = Get-Content 'D:\Dev\sqlcli\sqlcli.json' -Raw | ConvertFrom-Json
$src = $cfg.Profiles.bkm    # 192.168.40.201, Database=master (3-part ad ile DerinSISBkm)
$dst = 'Server=BT-FIKRI;Database=DerinSIS_Local;Integrated Security=true;TrustServerCertificate=true;'
if ([string]::IsNullOrWhiteSpace($src)) { throw 'sqlcli.json Profiles.bkm bulunamadi' }

$filter = "i.eTarih >= '20210531' AND i.eTip IN (0,2,10,3,6,102,103)"   # ALIS irsaliyeleri

Write-Host '== 1) Hedef tablolari (yeniden) kur (minimal kolon) =='
$ddl = @'
IF OBJECT_ID('dbo.irsAyr','U') IS NOT NULL DROP TABLE dbo.irsAyr;
IF OBJECT_ID('dbo.irs','U')    IS NOT NULL DROP TABLE dbo.irs;
CREATE TABLE dbo.irs (
    eID     int          NOT NULL,
    eTip    tinyint      NOT NULL,
    eTarih  smalldatetime NULL,
    eTarihS smalldatetime NULL,
    eMekan  int          NOT NULL,
    eGC     tinyint      NOT NULL
);
CREATE TABLE dbo.irsAyr (
    ehID    int NOT NULL,
    ehSira  int NOT NULL,
    ehStkID int NOT NULL
);
'@
Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -Database 'DerinSIS_Local' -Query $ddl

Write-Host '== 2) irs kopyala (ALIS 2021+, ~290K) =='
$qIrs = "SELECT eID, eTip, eTarih, eTarihS, eMekan, eGC FROM DerinSISBkm.dbo.irs i WITH(NOLOCK) WHERE $filter"
dotnet run --project D:\Dev\sqlcli -- copy --from $src --to $dst --table 'dbo.irs' --truncate --query $qIrs

Write-Host '== 3) irsAyr kopyala (ALIS bridge, ~4.6M) =='
$qAyr = "SELECT ia.ehID, ia.ehSira, ia.ehStkID FROM DerinSISBkm.dbo.irsAyr ia WITH(NOLOCK) JOIN DerinSISBkm.dbo.irs i WITH(NOLOCK) ON i.eID = ia.ehID WHERE $filter"
dotnet run --project D:\Dev\sqlcli -- copy --from $src --to $dst --table 'dbo.irsAyr' --truncate --query $qAyr

Write-Host '== 4) Indeksler =='
Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -Database 'DerinSIS_Local' -Query @'
CREATE INDEX IX_irs_eID ON dbo.irs(eID) INCLUDE(eTip,eTarih,eTarihS,eMekan,eGC);
CREATE INDEX IX_irsAyr_ehID ON dbo.irsAyr(ehID, ehSira) INCLUDE(ehStkID);
'@

Write-Host '== 5) Mutabakat (beklenen: irs 290306 / irsAyr 4618838) =='
Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -Database 'DerinSIS_Local' -Query @'
SELECT 'irs' tbl, COUNT(*) n FROM dbo.irs
UNION ALL SELECT 'irsAyr', COUNT(*) FROM dbo.irsAyr;
'@ | Format-Table -AutoSize
