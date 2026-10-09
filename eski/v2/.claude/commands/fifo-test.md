# FIFO Test SQL Üret

Belirli bir ürün veya senaryo için test SQL'i oluştur.

## Argüman
$ARGUMENTS — test türü ve parametreler. Örnekler:
- `tek-urun 594124` — StkId 594124 için FIFO test
- `aylik 2026 2` — 2026 Şubat ayı için aylık test
- `acilis 2025-12-31` — Açılış envanter testi
- `ortalama 2026 1` — Ortalama maliyet testi
- `karsilastirma 2026 1` — FIFO vs Ortalama karşılaştırma

## Kurallar
- `SELECT *` yasak
- Test sonunda ROLLBACK (veri değişikliği bırakma)
- PRINT ile adım adım çıktı
- Linked server: DerinSISBkm
- Mekanlar: 1, 12, 4477, 4478

## Bağlam
SP imzalarını oku: memory/schema.md
SP kodlarını oku: v2-production/02_V2_CoreProcedures.sql (gerekirse)

## Çıktı
Çalıştırılabilir SQL script. SSMS'te doğrudan çalıştırılabilir.
