# SQL Deploy Et

v2-production altindaki SQL dosyasini canli DB'ye deploy et.

## Arguman
$ARGUMENTS — dosya numarasi veya adi. Ornekler:
- `07` — 07_V2_HareketliUrunListesi.sql
- `09` — 09_V2_BatchOrchestration.sql
- `12` — 12_V2_OrtalamaAylikMaliyet.sql
- `dosya.sql` — belirli dosya

## Deploy Adimlari
1. Dosyayi oku: `v2-production/<dosya>.sql`
2. /deploy-check skill'ini calistir (dogrulama)
3. Dogrulama gecerse → kullanicidan onay iste
4. Deploy komutu (sqlcli kullan):
```bash
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- script v2-production/<dosya>.sql
```
5. Deploy sonrasi dogrulama:
```bash
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- tablolar
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- satir-sayisi
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "SELECT name FROM sys.objects WHERE name = '<beklenen_obje>'"
```
6. Sonucu raporla

## Deploy Sirasi (bagimliliklara gore)
1. `07_V2_HareketliUrunListesi.sql` — bagimsilik yok
2. `09_V2_BatchOrchestration.sql` — 07'ye bagimli (sp_Fifo_HareketliUrunListesi)
3. `12_V2_OrtalamaAylikMaliyet.sql` — bagimsilik yok

## Kurallar
- KULLANICIDAN ONAY ALMADAN DEPLOY ETME
- Hata olursa hata mesajini goster
- Deploy sonrasi mutlaka dogrulama yap
- Basarili deploy'u project_status.md ve db_live_state.md'ye yaz
