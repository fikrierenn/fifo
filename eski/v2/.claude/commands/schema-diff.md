# Schema Fark Analizi

SQL dosyaları ile dokümantasyon arasındaki farkları bul.

## Görev
1. `v2-production/01_V2_Tables.sql` → gerçek tablo tanımları
2. `v2-production/02_V2_CoreProcedures.sql` → SP parametreleri
3. `v2-production/03_V2_Views.sql` → view tanımları
4. `v2-production/09_V2_BatchOrchestration.sql` → batch tabloları
5. `v2-production/12_V2_OrtalamaAylikMaliyet.sql` → ortalama tablosu

Karşılaştır:
- `docs/SCHEMA.md`
- Memory: `schema.md`
- `CLAUDE.md` içindeki tablo listesi

## Çıktı
| Obje | SQL Dosyası | SCHEMA.md | CLAUDE.md | Memory | Fark |
|------|-------------|-----------|-----------|--------|------|

Sonunda tutarsızlıkları listele ve düzeltme öner.
