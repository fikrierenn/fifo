# FIFO SQL Geliştirmeleri - README

**Versiyon**: 2.0  
**Tarih**: 2025-01-19  
**Durum**: Production-Ready  

---

## 📋 İçerik

Bu klasör FIFO (First In First Out) stok maliyetlendirme sistemi için üretim-ready SQL script'lerini içerir.

### Dosyalar

| # | Dosya | Açıklama | Efor | Risk |
|---|-------|----------|------|------|
| 1 | `01_SPRINT1_KRITIK_DUZELTMELER.sql` | FIFO algoritması stabilizasyonu | 2-3h | 🟢 Düşük |
| 2 | `02_SPRINT2_VIEWS_AUDIT.sql` | Muhasebe kontrol + audit trail | 2-3h | 🟢 Düşük |
| 3 | `03_TEST_DATA_SETUP.sql` | Complete test senaryosu | 1h | 🟡 Orta |

---

## 🚀 Hızlı Başlangıç

### Step 1: Backup Al
```sql
BACKUP DATABASE [BKMMaliyet] 
TO DISK = 'D:\backups\BKMMaliyet_20250119_before_sprint.bak'
WITH INIT, COMPRESSION;
```

### Step 2: Sprint 1'i Çalıştır
```sql
-- SSMS'te aç ve çalıştır
01_SPRINT1_KRITIK_DUZELTMELER.sql
```

✅ Başarı kriteri: Hiç error yok

### Step 3: Sprint 2'yi Çalıştır
```sql
-- SSMS'te aç ve çalıştır
02_SPRINT2_VIEWS_AUDIT.sql
```

✅ Başarı kriteri: 8 view + 3 SP + 2 trigger oluşturuldu

### Step 4: Test Veri Yükle
```sql
-- Test ortamında aç ve çalıştır
03_TEST_DATA_SETUP.sql
```

✅ Başarı kriteri: 6 rapor doğru şekilde gösteriliyor

---

## 📊 Her Script'in Detayları

### 01_SPRINT1_KRITIK_DUZELTMELER.sql (1,200+ satır)

**Yapılan Değişiklikler:**

1. **FIFO Sıralama Deterministic Yapılması**
   - Eski indeks: `IX_fifo_StokMaliyetHavuzu_stkID` (belirsiz sıra)
   - Yeni indeks: `IX_fifo_Havuz_FifoSira` (deterministic)
   - Yardımcı view: `bkm.vw_FifoKatmanlarSirali`

2. **ERPDevir Mekanı Desteği**
   - Yeni sütun: `mekanID` (PK'ya eklendi)
   - Yeni PK: `(stkID, satinalmaSarti, mekanID)`
   - Yeni indeks: `IX_ErpDevir_SartiMekan`

3. **Check Constraints (5x)**
   - `CK_Havuz_Miktarlar_Gecerli` - Miktar doğrulama
   - `CK_Cikis_Miktar_Pozitif` - Çıkış miktarı > 0
   - `CK_ErpDevir_Pozitif` - ERP fiyatları > 0
   - `CK_Envanter_Pozitif` - Envanter >= 0
   - `CK_Run_Durum_Gecerli` - Run status validation

4. **Foreign Keys (1x)**
   - `FK_RunStep_Run` - RunStep → Run (DELETE CASCADE)

5. **Transaction Control**
   - `sp_fifo_StokMaliyetAlisKatman` → `SET XACT_ABORT ON`

**Çıktı:**
```
✓ 1 view
✓ 2 index
✓ 5 constraint
✓ 1 FK
✓ 1 SP update
```

**Rollback:**
- Kolay: Index'ler sil, constraint'ler sil, eski index'leri geri yükle

---

### 02_SPRINT2_VIEWS_AUDIT.sql (900+ satır)

**Yapılan Değişiklikler:**

1. **Audit Log Infrastructure**
   - Tablo: `bkm.fifo_AuditLog` (JSON storage)
   - Index: 3 tane (query optimization)
   - Trigger: 2 tane (Havuzu, Çıkış)

2. **Muhasebe Kontrol View'ları (6x)**
   - `vw_KatmanTuketimRaporu` - Katman uyumsuzluk kontrol
   - `vw_CikisDetayliRapor` - FIFO eşleştirme detayları
   - `vw_GunlukSMM_Ozeti` - Günlük stok maliyet özeti
   - `vw_UrunBazliSMM_Detay` - Ürün bazlı SMM
   - `vw_KatmanDurumuOzeti` - Katman durumu raporu
   - `vw_SorunluStoklar_Rapor` - Sorunlu stok özeti

3. **Audit Log View'ları (2x)**
   - `vw_SonDegisiklikler` - Son 1000 değişiklik
   - `vw_KullaniciAktiviteleri` - Kullanıcı aktivite özeti

4. **Yardımcı SP'ler (3x)**
   - `sp_KatmanDegisimTarihcesi` - Belirli katmanın tarihçesi
   - `sp_CikisTutarlillikKontrolu` - Çıkış doğrulama
   - `sp_VeriTasiymaKontrolu` - Veri taşıma raporu

**Çıktı:**
```
✓ 1 table + 3 index
✓ 2 trigger
✓ 6 view
✓ 2 view
✓ 3 SP
```

**Rollback:**
- Çok kolay: View'ları sil, SP'leri sil, trigger'ları sil, tablo sil

---

### 03_TEST_DATA_SETUP.sql (700+ satır)

**Senaryosu:**

```
31.12.2025 (Açılış)
├─ Ürün 594124: 1.000 birim @ 50.00 TL (3 şubede)
├─ Ürün 12345: 1.200 birim @ 120.00 TL (2 şubede)
└─ Ürün 67890: 2.000 birim @ 15.00 TL (1 şubede)
   Toplam: 4.200 birim, 221.200 TL

01.01.2026 - 31.01.2026 (Ocak İşletmesi)
├─ 9 alış faturası (594124, 12345, 67890)
└─ FIFO çıkış hesaplaması

Muhasebe Raporları:
├─ Açılış özeti
├─ Alış detayları
├─ FIFO çıkışlar
├─ Günlük SMM
├─ Katman tüketim kontrolü
└─ Kapaniş envanteri
```

**Test Ürünleri:**
- 594124: Tekstil (mekan farkı test)
- 12345: Elektronik
- 67890: Gıda

**Çıktı:**
- 6 kontrol raporu
- 2 muhasebe kontrol sonucu
- 1 kapaniş raporu

---

## 📈 Uygulama Tablosu

| Aşama | Script | Zaman | Önceki |
|-------|--------|-------|--------|
| 1 | 01_SPRINT1 | 2-3h | Backup |
| 2 | 02_SPRINT2 | 2-3h | Sprint 1 ✓ |
| 3 | 03_TEST_DATA | 1h | Sprint 2 ✓ |

**Toplam Efor**: 5-7 saat

---

## ✅ Kontrol Listeleri

### Sprint 1 Kontrol Noktaları

```sql
-- 1. FIFO indeksleri var mı?
SELECT name FROM sys.indexes 
WHERE object_id = OBJECT_ID('bkm.fifo_StokMaliyetHavuzu')
  AND name LIKE '%FifoSira%';
-- ✓ Sonuç: IX_fifo_Havuz_FifoSira

-- 2. ERPDevir mekanID var mı?
SELECT column_name FROM information_schema.columns
WHERE table_name = 'fifo_ErpDevirFiyatlari'
  AND column_name = 'mekanID';
-- ✓ Sonuç: mekanID

-- 3. Check constraint'ler çalışıyor mu?
INSERT INTO bkm.fifo_StokMaliyetHavuzu 
VALUES (1, 1, '2025-01-31', 'TEST', NULL, NULL, NULL, -100, -100, 50.00, 'NORMAL', GETDATE());
-- ❌ Beklenen: Constraint ihlali

-- 4. View oluşturuldu mu?
SELECT * FROM bkm.vw_FifoKatmanlarSirali LIMIT 1;
-- ✓ Sonuç: Katmanlar sıralanmış
```

### Sprint 2 Kontrol Noktaları

```sql
-- 1. Audit Log tablo var mı?
SELECT COUNT(*) FROM bkm.fifo_AuditLog;
-- ✓ Sonuç: 0 (temiz başlangıç)

-- 2. View'lar çalışıyor mu?
SELECT COUNT(*) FROM bkm.vw_KatmanTuketimRaporu;
-- ✓ Sonuç: > 0

-- 3. Trigger'lar çalışıyor mu?
UPDATE bkm.fifo_StokMaliyetHavuzu SET miktarKalan = 100 WHERE ID = 1;
SELECT COUNT(*) FROM bkm.fifo_AuditLog WHERE operation = 'UPDATE';
-- ✓ Sonuç: > 0
```

### Test Veri Kontrol Noktaları

```sql
-- 1. Açılış katmanları var mı?
SELECT COUNT(*) FROM bkm.fifo_StokMaliyetHavuzu 
WHERE girisTarihi = '2025-12-31';
-- ✓ Sonuç: 9 (3 ürün × 3 şube)

-- 2. FIFO hesaplaması başarılı mı?
SELECT COUNT(*) FROM bkm.fifo_StokMaliyetCikis 
WHERE hareketTarihi >= '2026-01-01';
-- ✓ Sonuç: > 0

-- 3. Sorunlu stoklar var mı?
SELECT COUNT(*) FROM bkm.fifo_StokMaliyetSorunlu;
-- ✓ Sonuç: 0 (temiz test)
```

---

## 🔧 Troubleshooting

### Problem: "PK constraint ihlali"
```
Sebep: ERPDevir'de aynı (stkID, satinalmaSarti, mekanID) için 2 kayıt
Çözüm: DELETE FROM bkm.fifo_ErpDevirFiyatlari; -- Temizle, yeniden yükle
```

### Problem: "Index creation timeout"
```
Sebep: Büyük tablo, lock contention
Çözüm: CREATE INDEX ... WITH (ONLINE=ON, MAXDOP=1);
```

### Problem: "View returns error"
```
Sebep: Join tablo eksik
Çözüm: SELECT * FROM bkm.fifo_StokMaliyetHavuzu; -- İlgili tablo kontrol
```

---

## 📞 Destek

### Sorular
1. **SQL Hataları**: Script output'ını oku (başında uyarı yazıldı)
2. **Kontrol Geçmiş mi?**: Kontrol listeleri çalıştır
3. **Rollback gerek?**: `RESTORE DATABASE ... FROM DISK = 'backup.bak'`

### Sonraki Adımlar
1. ✅ Sprint 1 + 2 + Test tamamlandı
2. 📝 C# entegrasyonunu yapılacak (RunWorker, validation)
3. 🚀 Go-Live hazırlığı (backup, training)

---

## 📚 Referans Dokümantlar

Aynı klasörde mevcuttur:
- `../00_MASTER_DEPLOY.sql` - Orijinal script (referans)
- `../../docs/SCHEMA.md` - Veritabanı şeması
- `../../yedek/` - Eski versiyonlar (arşiv)

---

## ⚖️ Lisans & Uyarılar

- **Production Kullanımı Öncesi**: Staging ortamda test edin
- **Backup**: Her script öncesi backup alın
- **Rollback**: Her script geri alınabilir durumda

---

**Yazarlar**: Code Review Team  
**Son Güncelleme**: 2025-01-19  
**Versiyon**: 2.0 (Production-Ready)
