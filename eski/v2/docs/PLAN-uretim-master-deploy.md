# PLAN — Üretim Tek-Master Deploy (0→Canlı) + Açılış SP Final-Tier

**Tarih:** 2026-06-19 · **Repo:** `D:\Dev\fifo` · **Tier:** 3 (üretim-kritik, geri-alınması zor) · **Durum:** Taslak

## 1. Problem
BKMMaliyet'i sıfırdan canlıya (192.168.40.201) alacağız. Eldeki ~23 incremental script (00–21 + iki 19_V2) dağınık: tekrarlanan `USE/SET` boilerplate, superseded SP tanımları (07→16, 02→19 ALTER), lokal-stale veri-fix scriptleri (20/21) ve `DerinSIS_Local` repoint (98 ref) karışık. Üretimde ERP kaynağı `DerinSISBkm`. Ayrıca açılış SP'si "fiyat 0 olamaz"ı garanti etmiyor (619 katmansız + 13 sıfır-maliyet bu yüzden oluştu — sonradan 20/21 ile elle düzeltildi). Tek, doğru, dedup, parametrik, kendi-kendini-doğru-kuran master gerek.

## 2. Scope
### Dahil
- **Açılış SP'ye GARANTİ final-tier** (root fix): tüm mevcut tier'lardan (NORMAL→TAMAMLAMA→MERKEZ→SART→AYLIK_DEVIR→SABIT) sonra, hâlâ katmansız açılış stoğunu **kategori-marj imputation (SatisFiyat × KatAna AVG(cost/satış)) → kalan sabit(>0)** ile fiyatlar. Sonuç: temiz çalıştırmada `BirimMaliyet<=0` = 0. Mevcut tier akışına dokunma; SP sonuna eklenir.
- **ERP-db parametrik:** `:setvar ErpDb DerinSISBkm` (lokal override `DerinSIS_Local`). 98 `DerinSIS_Local` → `$(ErpDb)`.
- **Temiz tek master** (`00_V2_MASTER_FULL.sql` yeniden): canlı DB'den scriptlenmiş **final** obje gövdeleri (dedup garantili — sys.sql_modules) + tablo (PK/FK/computed SatisTutar/default/check) + trigger (`tr_fifo_*`) + view, **her obje TEK kez final halinde**.
- **Curated seed** (referans iş-bilgisi): `FifoDevreDisiUrunler` (non-inventory listesi), `FifoFallbackFiyatlari`, `FifoManuelMaliyet` (cost-anomali override) — idempotent `WHERE NOT EXISTS`.
- **Doğrulama ortamı:** irs + irsAyr (alış+satış, 2021+, ~290K/4.6M) 201'den lokale re-seed → boş test-DB'ye master deploy + açılış re-run + `maliyetsiz=0` + bütünlük (C1-C7).

### Hariç
- `20_V2` reprice + `21_V2` açılış-eksik: lokal-stale veri fix'i; temiz fresh run'da gereksiz (SP final-tier zaten garanti eder). Arşivde kalır, master'a girmez.
- `06/08/10/11` verification/benchmark/smoke: diagnostik, deploy değil.
- Hangfire job orkestrasyon (ayrı proje).
- Pipeline'ı (açılış+aylık) master içinde otomatik çalıştırma — deploy ≠ pipeline; ayrı tetiklenir.

### Etkilenen
- `v2-production/14_V2_AcilisOptimize.sql` — final-tier eklenir (kaynak güncel kalır).
- `v2-production/00_V2_MASTER_FULL.sql` — sıfırdan temiz üretilir.
- (geçici) `DerinSIS_Local.dbo.irs/irsAyr` — re-seed (test için).

## 3. Adımlar
1. [ ] **S1** irs + irsAyr re-seed (201→lokal, alış+satış eTip, 2021-05-31+). `sqlcli copy`. Doğrula: satır sayısı 201 ile mutabık.
2. [ ] **S2** Açılış SP final-tier yaz (`14_V2`): kategori-oran CTE (NORMAL katmanlardan) → katmansız stok imputation → kalan sabit>0. Lokal deploy.
3. [ ] **S3** Boş `BKMMaliyet_Test` DB'de açılış re-run (fixed SP) → **GATE: `SELECT COUNT(*) FROM FifoKatman WHERE BirimMaliyet<=0` = 0** + C1-C7 yeşil.
4. [ ] **S4** ERP-db `$(ErpDb)` parametrik dönüşüm (tüm scriptler/SP).
5. [ ] **S5** Temiz master üret: canlı→script (final SP/view/trigger) + tablo DDL + curated seed. Dedup doğrula (her obje 1 kez).
6. [ ] **S6** Master'ı boş `BKMMaliyet_Test2`'ye deploy (DDL+seed) → syntax+obje sayısı doğrula; sonra açılış+aylık pipeline → maliyetsiz=0.
7. [ ] **S7** Commit (fifo repo). Eski incremental dosyalar: arşivle veya `legacy/` (master canonical).

## 4. Riskler
| Risk | Etki | Mitigation |
|---|---|---|
| Enhanced SP üretim costing'i yanlış | yüksek | S3 GATE + S6 pipeline doğrulama (maliyetsiz=0, marj mutabakat) |
| irsAyr re-seed disk/süre | düşük | irsHrk zaten 58M; 4.6M filtreli alt-küme küçük |
| $(ErpDb) bir yerde atlanır → DerinSIS_Local prod'a sızar | orta | `grep DerinSIS_Local` final master'da 0 dönmeli (S5 kontrol) |
| Trigger/FK script eksik → deploy kırık | orta | sys'ten tam scriptle; boş-DB deploy testi (S6) |
| Superseded tanım kaçar (07+16 ikisi) | orta | canlı sys.sql_modules tek gövde verir → otomatik dedup |

## 5. Done Criteria
- [ ] Boş DB'ye master tek-deploy temiz geçer (DDL+seed).
- [ ] Açılış+aylık pipeline sonrası `maliyetsiz katman=0`, `maliyetsiz çıkış=0`, C1-C7 yeşil.
- [ ] Marj mutabakat (Ocak rev2: brüt ~25.58M / %35.40) tutar.
- [ ] Master'da `DerinSIS_Local` geçmez (hep `$(ErpDb)`), her obje 1 kez.
- [ ] Curated seed yüklü, idempotent (2. deploy fark üretmez).

## 6. Rollback
- Master DDL idempotent (CREATE OR ALTER) → re-deploy güvenli. Yanlışsa eski incremental + `git revert`.
- Test DB'ler (`BKMMaliyet_Test*`) at-bırak — prod'a dokunmadan doğrulama.
- Prod cutover ayrı karar (bu plan master'ı ÜRETİR + doğrular; prod'a basmak ayrı onay).

## 7. İlişkili
- `fifo-domain.md §6` (fiyat 0 olamaz), `21_V2` (imputation mantığı kaynağı), `19_V2_DevreDisi_Fallback_Seed` (curated seed), `pusula/plans/23` (sema tarafı — ayrı).
