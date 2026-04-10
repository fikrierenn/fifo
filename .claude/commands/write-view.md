# Eksik View Oluştur

Belirtilen view'ı proje kurallarına uygun şekilde yaz.

## Argüman
$ARGUMENTS — view adı (ör: `vw_MaliyetKarsilastirma`, `vw_Ortalama_AySonuBirimMaliyet`)

## Kurallar (ZORUNLU)
- `SELECT *` yasak — kolon isimlerini explicit yaz
- SARGable sorgular
- `CREATE OR ALTER VIEW` kullan (idempotent)
- View sonuna `GO` ekle
- Dosya başına `USE BKMMaliyet; GO` + SET options

## Bağlam
Mevcut view'ları oku: `v2-production/03_V2_Views.sql`
Tablo şemalarını oku: `v2-production/01_V2_Tables.sql`, `v2-production/12_V2_OrtalamaAylikMaliyet.sql`
Schema doku: `docs/SCHEMA.md`

## Bilinen Eksik View'lar
1. `vw_Ortalama_AySonuBirimMaliyet` — OrtalamaAylikMaliyet tablosundan ay sonu birim maliyet
2. `vw_MaliyetKarsilastirma` — FIFO (vw_Fifo_AySonuBirimMaliyet veya FifoKatman) vs Ortalama (OrtalamaAylikMaliyet) yan yana karşılaştırma

## Çıktı
- View SQL kodunu yaz
- Uygun dosyaya ekle veya yeni dosya oluştur
- Test sorgusu öner
