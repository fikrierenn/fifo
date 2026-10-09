<#
.SYNOPSIS
  FIFO DEGISMEZLERINI KOSTURUR - sema/degismezler.json

.DESCRIPTION
  NEDEN VAR
  ---------
  Bu depoda kurallar dokumanlarda yasiyordu ve kimse onlari KOSTURMUYORDU.
  "FIYAT 0 OLAMAZ" bir markdown basligiydi; 20_V2 ve 21_V2 reprice scriptleri
  o kurali ELLE onarmak icin yazilmisti. Bir kural komutla yeniden
  kosturulabiliyorsa kosturulur.

  last_verified + ttl bir BAYRAKTIR, bir OLCUM degil: suresi doldugunu gormek
  icin birinin bakmasi gerekir ve bakilmaz. Bu betik farki kapatir.

  SESSIZ ATLAMA YOK
  -----------------
  Veritabanina baglanamazsa PATLAR, "gecti" demez. Bir olcumun BOS donmesi ile
  KOSMAMASI ekranda ayni gorunur; yesil cikti degismezlerin gercekten kostugu
  anlamina gelmeli.

  CIKIS KODU 0 / 1 / 2
  --------------------
    0 = hepsi gecti
    1 = KIRIK      (olcum kostu, deger beklenenden farkli)
    2 = KOSAMADI   (baglanti yok * SQL patladi * sonuc YOK/NULL * kayit kusurlu)

  Kosamamak YESIL DEGILDIR, kirik da degildir. Ikisini ayirmayan bir cikis kodu
  "olcmedik"i "olctuk, tuttu" gibi gosterir.

  ! NULL / satir yok 0 SAYILMAZ. `karsilastirma: esit, beklenen: 0` olan
  kayitlarda bu HIC OLCMEDEN YESIL verirdi. Burada KOSAMADI (cikis 2).

  YENI DEGISMEZ EKLERKEN
  ----------------------
  Beklenen degeri bilerek boz, KIRMIZI oldugunu GOR, sonra geri al:
      pwsh tools/fifo-degismez.ps1 -Sadece <id>
  Kirilabildigi kanitlanmamis bir test, test degildir.

.EXAMPLE
  pwsh tools/fifo-degismez.ps1
  pwsh tools/fifo-degismez.ps1 -Veritabani BKMMaliyet_Run
  pwsh tools/fifo-degismez.ps1 -Sadece katman-maliyet-pozitif -Ayrintili
#>
[CmdletBinding()]
param(
    [string] $Sunucu = 'BT-FIKRI',
    [string] $Veritabani = 'BKMMaliyet',
    [string] $Sadece = '',
    [switch] $Ayrintili
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Kosamadi([string] $Mesaj) {
    Write-Host "KOSAMADI: $Mesaj" -ForegroundColor Magenta
    exit 2
}

$repo  = Split-Path -Parent $PSScriptRoot
$dosya = Join-Path $repo 'sema\degismezler.json'
if (-not (Test-Path $dosya)) { Kosamadi "sema/degismezler.json bulunamadi: $dosya" }

try {
    $veri = Get-Content $dosya -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Kosamadi "degismezler.json parse edilemedi: $($_.Exception.Message)"
}

$kayitlar = @($veri.degismezler)
if ($Sadece) { $kayitlar = @($kayitlar | Where-Object { $_.id -eq $Sadece }) }
if ($kayitlar.Count -eq 0) { Kosamadi "kosulacak kayit yok (Sadece='$Sadece')" }

# Baglanti bir kez sinanir: baglanamiyorsak HICBIR SEY yesil olamaz.
try {
    $null = Invoke-Sqlcmd -ServerInstance $Sunucu -Database $Veritabani -Query 'SELECT 1 AS x' -ErrorAction Stop
} catch {
    Kosamadi "baglanti yok ($Sunucu / $Veritabani): $($_.Exception.Message)"
}

Write-Host ""
Write-Host "FIFO DEGISMEZLERI - $Sunucu / $Veritabani - $($kayitlar.Count) kayit" -ForegroundColor Cyan
Write-Host ("-" * 78)

$gecti = 0; $kirik = @(); $kusurlu = @()

foreach ($k in $kayitlar) {

    # ?? YAPISAL DENETIM: gerekcesiz degismez kabul edilmez ??
    # Kirildiginda ne yapilacagini soylemeyen bir kayit, kirildiginda ise yaramaz.
    foreach ($alan in @('id','soru','neden','sql','karsilastirma','beklenen')) {
        if (-not $k.PSObject.Properties.Name.Contains($alan) -or
            $null -eq $k.$alan -or "$($k.$alan)".Trim() -eq '') {
            $kusurlu += "$($k.id): '$alan' bos"
        }
    }
    if ($k.karsilastirma -notin @('esit','enaz','encok')) {
        $kusurlu += "$($k.id): karsilastirma '$($k.karsilastirma)' gecersiz (esit|enaz|encok)"
    }
    if ($kusurlu.Count -gt 0) { continue }

    # ?? OLCUM ??
    $deger = $null
    try {
        $sonuc = Invoke-Sqlcmd -ServerInstance $Sunucu -Database $Veritabani -Query $k.sql -QueryTimeout 600 -ErrorAction Stop
    } catch {
        $kusurlu += "$($k.id): SQL patladi - $($_.Exception.Message)"
        continue
    }

    if ($null -eq $sonuc) { $kusurlu += "$($k.id): sonuc YOK (satir donmedi)"; continue }
    $ilk = @($sonuc)[0]
    if ($null -eq $ilk) { $kusurlu += "$($k.id): sonuc YOK"; continue }
    $deger = $ilk[0]
    # NULL 0 SAYILMAZ - bu tam olarak 'hic olcmeden yesil' halidir.
    if ($null -eq $deger -or $deger -is [DBNull]) { $kusurlu += "$($k.id): sonuc NULL"; continue }

    $deger = [double] $deger
    $bek   = [double] $k.beklenen

    $ok = switch ($k.karsilastirma) {
        'esit'  { $deger -eq $bek }
        'enaz'  { $deger -ge $bek }
        'encok' { $deger -le $bek }
    }

    if ($ok) {
        $gecti++
        if ($Ayrintili) {
            Write-Host ("  GECTI    {0,-38} {1} {2} (olculen {3})" -f $k.id, $k.karsilastirma, $bek, $deger) -ForegroundColor Green
        } else {
            Write-Host ("  GECTI    {0}" -f $k.id) -ForegroundColor Green
        }
    } else {
        $kirik += [pscustomobject]@{ id = $k.id; beklenen = "$($k.karsilastirma) $bek"; olculen = $deger; neden = $k.neden; soru = $k.soru }
        Write-Host ("  KIRIK    {0,-38} beklenen {1} {2}, OLCULEN {3}" -f $k.id, $k.karsilastirma, $bek, $deger) -ForegroundColor Red
    }
}

Write-Host ("-" * 78)

if ($kusurlu.Count -gt 0) {
    Write-Host ""
    Write-Host "KUSURLU KAYIT / KOSAMADI:" -ForegroundColor Magenta
    $kusurlu | ForEach-Object { Write-Host "  ~ $_" -ForegroundColor Magenta }
    Write-Host ""
    Write-Host "Kosamamak YESIL degildir. Cikis 2." -ForegroundColor Magenta
    exit 2
}

if ($kirik.Count -gt 0) {
    Write-Host ""
    Write-Host "KIRIK DEGISMEZLER - ne anlama geliyor:" -ForegroundColor Red
    foreach ($x in $kirik) {
        Write-Host ""
        Write-Host "  [$($x.id)]" -ForegroundColor Red
        Write-Host "    soru     : $($x.soru)"
        Write-Host "    beklenen : $($x.beklenen) * olculen: $($x.olculen)"
        Write-Host "    neden    : $($x.neden)"
    }
    Write-Host ""
    Write-Host "$gecti gecti * $($kirik.Count) KIRIK" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "$gecti/$($kayitlar.Count) degismez GECTI." -ForegroundColor Green
exit 0
