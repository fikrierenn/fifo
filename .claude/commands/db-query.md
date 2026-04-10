# DB Sorgu Calistir

BKMMaliyet veritabaninda SQL sorgusu calistir ve sonuclari goster.

## Arguman
$ARGUMENTS — SQL sorgusu veya kisayol. Ornekler:
- `SELECT TOP 10 KatmanId, StkId FROM FifoKatman` — dogrudan SQL
- `katmanlar` — FifoKatman tablosunu goster
- `sorunlular` — FifoSorunluStoklar listele
- `islemler` — MaliyetIslem log'lari
- `envanter` — FifoAcilisEnvanter goster
- `view:smm` — vw_Fifo_GunlukSMM calistir
- `sp-list` — tum SP'leri listele
- `tablolar` — tablo listesi (sqlcli built-in)
- `satir-sayisi` — satir sayilari (sqlcli built-in)
- `indexler` — index listesi (sqlcli built-in)

## sqlcli Komutlari (ZORUNLU — sqlcmd KULLANMA)
```bash
# Fifo proje dizininde calistirilir:
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- <komut>
```

### Built-in Komutlar (dogrudan sqlcli)
- `tablolar` → `dotnet run --project D:/Dev/sqlcli -- tablolar`
- `satir-sayisi` → `dotnet run --project D:/Dev/sqlcli -- satir-sayisi`
- `indexler` → `dotnet run --project D:/Dev/sqlcli -- indexler`
- `status` → `dotnet run --project D:/Dev/sqlcli -- status`

### SQL Kisayollar (query komutu ile)
- `katmanlar` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT TOP 50 KatmanId, StkId, GirisTarihi, KaynakTip, BelgeNo, GirisMiktar, KalanMiktar, BirimMaliyet, Durum FROM FifoKatman ORDER BY KatmanId DESC"`
- `sorunlular` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT TOP 50 EnvanterTarihi, MekanId, StkId, SorunTipi, StokMiktar, Aciklama FROM FifoSorunluStoklar ORDER BY EnvanterTarihi DESC"`
- `islemler` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT IslemId, IslemAdi, Baslangic, Bitis, Durum, EnvanterTarihi, StkId FROM MaliyetIslem ORDER BY Baslangic DESC"`
- `envanter` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT EnvanterTarihi, MekanId, StkId, StokMiktar FROM FifoAcilisEnvanter ORDER BY EnvanterTarihi, MekanId"`
- `cikislar` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT TOP 50 CikisId, StkId, HareketTarihi, HareketTipi, KatmanId, Miktar, BirimMaliyet, CikisTutar FROM FifoCikisDetay ORDER BY CikisId DESC"`
- `sp-list` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT name, type_desc FROM sys.objects WHERE type = 'P' ORDER BY name"`
- `view-list` → `dotnet run --project D:/Dev/sqlcli -- query "SELECT name FROM sys.objects WHERE type = 'V' ORDER BY name"`

## Kurallar
- SELECT * YASAK — kisayollarda kolon isimleri explicit
- Kullanici dogrudan SQL yazarsa, SELECT * kontrolu yap ve uyar
- Sonuclari tablo formatinda goster
- Uzun sonuclarda TOP 50 ekle
