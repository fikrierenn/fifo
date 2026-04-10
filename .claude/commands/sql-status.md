# SQL Durum Raporu

Projedeki tum SQL objelerinin canli DB ile karsilastirmali durumunu raporla.

## Gorev
1. **Canli DB'den obje envanteri cek (sqlcli kullan):**
```bash
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- tablolar
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- satir-sayisi
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "SELECT name, type_desc FROM sys.objects WHERE type IN ('P','V','U','TF','IF','FN') ORDER BY type_desc, name"
```

2. **v2-production/ altindaki dosyalari oku** — her dosyadan beklenen objeleri cikar

3. **Karsilastirma tablosu olustur:**

| Obje | Tip | v2-production Dosyasi | DB'de Var? | Satir | Durum |
|------|-----|----------------------|-----------|-------|-------|

4. **Eksik objeleri listele** — DB'de olmayan ama SQL dosyalarinda tanimlanan objeler

5. **Memory guncelle** — sonuclari `db_live_state.md`'ye yaz

## Ozel Kontroller
- `OrtalamaAylikMaliyet` tablosu var mi? (12_V2)
- `StkIdListType` TVP var mi? (09_V2)
- `FifoBatchRun/Detay/Hata` tablolari var mi? (09_V2)
- `sp_Fifo_HareketliUrunListesi` var mi? (07_V2)
- `sp_Fifo_AylikCalistirBatch` var mi? (09_V2)

## Cikti
- Markdown tablo: tum objeler ve durumlari
- Eksik/Bekleyen listesi
- Sonraki deploy onerisi
