<#
.SYNOPSIS
  Disk kalinti temizleyici (C + D) - FIFO lokal ortam.
.DESCRIPTION
  Bilinen guvenli kalintilari bulur + raporlar. Varsayilan DRY-RUN (silmez).
  Gercek temizlik icin -Apply ver.
  Kapsam: Recycle Bin, user/Windows TEMP, SQL tempdb sismesi (shrink),
          basibos .bak/.iso, SQL Setup Bootstrap loglari, harness task ciktilari.
.EXAMPLE
  powershell -File tools\disk-temizle.ps1            # rapor (dry-run)
  powershell -File tools\disk-temizle.ps1 -Apply     # temizle
#>
param(
  [switch]$Apply,
  [string[]]$SqlInstances = @('BT-FIKRI','BT-FIKRI\SQLEXPRESS','BT-FIKRI\SQLEXPRESS01')
)
$ErrorActionPreference = 'SilentlyContinue'
function GB($bytes){ [math]::Round(($bytes/1GB),2) }
function FreeGB($d){ GB (Get-PSDrive $d).Free }
function FolderBytes($p){
  # .NET enumeration — Get-ChildItem -Recurse'tan 5-10x hizli (pipeline overhead yok), erisim hatasina dayanikli
  if(-not (Test-Path $p)){ return 0 }
  [long]$sum = 0
  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push((Convert-Path $p))
  while($stack.Count -gt 0){
    $d = $stack.Pop()
    try { foreach($sd in [System.IO.Directory]::EnumerateDirectories($d)){ $stack.Push($sd) } } catch {}
    try { foreach($f in [System.IO.Directory]::EnumerateFiles($d)){ try { $sum += ([System.IO.FileInfo]$f).Length } catch {} } } catch {}
  }
  return $sum
}

$mode = if($Apply){ 'TEMIZLE (APPLY)' } else { 'RAPOR (dry-run)' }
Write-Host "=== DISK TEMIZLE - $mode ===" -ForegroundColor Cyan
Write-Host ("Baslangic: C={0}GB  D={1}GB" -f (FreeGB C),(FreeGB D))
$plan = @()

# 1) Recycle Bin
$rb = FolderBytes 'C:\$Recycle.Bin'
if($rb -gt 50MB){ $plan += [PSCustomObject]@{ Is='Recycle Bin'; GB=GB $rb; Aksiyon={ Clear-RecycleBin -Force } } }

# 2) User + Windows TEMP
foreach($t in @($env:TEMP,'C:\Windows\Temp')){
  $b = FolderBytes $t
  if($b -gt 100MB){ $plan += [PSCustomObject]@{ Is="TEMP: $t"; GB=GB $b; Aksiyon=[scriptblock]::Create("Get-ChildItem '$t' -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue") } }
}

# 3) Basibos .bak / .iso (D:\SQLBackup, D:\SQLMedia, D:\Temp)
foreach($f in (Get-ChildItem 'D:\SQLBackup\*.bak','D:\SQLMedia\*.iso','D:\Temp\*.iso' -File -EA SilentlyContinue)){
  $plan += [PSCustomObject]@{ Is="Dosya: $($f.Name)"; GB=GB $f.Length; Aksiyon=[scriptblock]::Create("Remove-Item -LiteralPath '$($f.FullName)' -Force -EA SilentlyContinue") }
}

# 4) SQL Setup Bootstrap loglari (>0.5GB)
$boot = 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log'
$bb = FolderBytes $boot
if($bb -gt 500MB){ $plan += [PSCustomObject]@{ Is='SQL Setup logs'; GB=GB $bb; Aksiyon=[scriptblock]::Create("Get-ChildItem '$boot' -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue") } }

# Rapor
if($plan.Count){ $plan | Select-Object Is,GB | Format-Table -AutoSize } else { Write-Host "Dosya-bazli kalinti yok." }
$toplam = ($plan | Measure-Object GB -Sum).Sum
Write-Host ("Dosya temizligi potansiyeli: {0} GB" -f $toplam) -ForegroundColor Yellow

# 5) SQL tempdb sismesi - shrink (DROP degil; data tasinmaz, sadece bos alan iade)
Write-Host "`n--- tempdb shrink (her instance) ---"
foreach($inst in $SqlInstances){
  try {
    $sz = Invoke-Sqlcmd -ServerInstance $inst -Query "SELECT g=CAST(SUM(size)*8.0/1048576 AS DECIMAL(10,2)) FROM tempdb.sys.database_files" -QueryTimeout 15 -EA Stop
    $g = [decimal]$sz.g
    if($g -gt 1){
      Write-Host ("  {0}: tempdb {1}GB" -f $inst,$g) -NoNewline
      if($Apply){
        $names = Invoke-Sqlcmd -ServerInstance $inst -Query "SELECT name FROM tempdb.sys.database_files" -QueryTimeout 15
        $sql = "USE tempdb; CHECKPOINT; " + (($names | ForEach-Object { "DBCC SHRINKFILE('$($_.name)',100) WITH NO_INFOMSGS;" }) -join ' ')
        Invoke-Sqlcmd -ServerInstance $inst -Query $sql -QueryTimeout 0
        Write-Host " -> shrink OK" -ForegroundColor Green
      } else { Write-Host " (shrink edilebilir)" -ForegroundColor Yellow }
    } else { Write-Host ("  {0}: tempdb {1}GB (ok)" -f $inst,$g) }
  } catch { Write-Host ("  {0}: erisilemedi" -f $inst) -ForegroundColor DarkGray }
}

# 6) D: icerik raporu (salt-okuma — DB'ler korunur, silinmez)
Write-Host "`n--- D: icerik (top klasor) ---"
Get-ChildItem 'D:\' -Directory -Force -EA SilentlyContinue | ForEach-Object {
  [PSCustomObject]@{ Klasor=$_.Name; GB=[math]::Round((FolderBytes $_.FullName)/1GB,2) }
} | Where-Object { $_.GB -gt 0.05 } | Sort-Object GB -Descending | Format-Table -AutoSize | Out-Host
$dbf = Get-ChildItem 'D:\SQLData\*.mdf','D:\SQLData\*.ndf','D:\SQLData\*.ldf' -EA SilentlyContinue
if($dbf){
  Write-Host "  D:\SQLData (DB dosyalari - SILINMEZ):"
  $dbf | Select-Object Name,@{n='GB';e={[math]::Round($_.Length/1GB,2)}} | Sort-Object GB -Descending | Format-Table -AutoSize | Out-Host
}

# Apply: dosya aksiyonlari
if($Apply -and $plan.Count){
  Write-Host "`n--- dosya temizligi ---"
  foreach($p in $plan){ Write-Host ("  {0} ({1}GB)..." -f $p.Is,$p.GB) -NoNewline; & $p.Aksiyon; Write-Host " OK" -ForegroundColor Green }
}

Write-Host ("`nBitis: C={0}GB  D={1}GB" -f (FreeGB C),(FreeGB D)) -ForegroundColor Cyan
if(-not $Apply){ Write-Host "DRY-RUN - silmek icin: -Apply" -ForegroundColor Magenta }
