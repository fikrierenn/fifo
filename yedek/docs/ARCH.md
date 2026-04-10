# FIFO Ops Panel - ARCH

## Stack
- .NET 10
- ASP.NET Core Razor Pages
- Dapper + Microsoft.Data.SqlClient
- SQL Server

## Mimari
- Monolith + feature-based Razor Pages
- Transaction script yaklasimi
- Controller yok, API yok

## Moduller
- Features/Home: ozet metrikler
- Features/Run: calistirma formu ve sonuc listesi
- Features/Issues: sorunlu stoklar
- Lib/Db: baglanti yonetimi

## Veri Akisi
1) UI formu -> sp_fifo_StokMaliyetCalistir
2) Sonuc okumasi -> bkm.fifo_StokMaliyetCikis
3) Sorunlar -> bkm.fifo_StokMaliyetSorunlu

## Riskler
- Buyuk tarih araliklarinda performans
- Kayit sayisi artisi (Cikis tablosu)
- Connection string yanlisligi
