# FIFO Stok Maliyet Sistemi - İyileştirmeler

## 📋 Yapılan İyileştirmeler

### 1. ✅ Transaction Yönetimi
- Tüm prosedürlere `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK` eklendi
- Hata durumunda otomatik rollback
- Hata detayları `fifo_StokMaliyetSorunlu` tablosuna loglanıyor

### 2. ✅ Parametre Validasyonu
- Null kontrolleri
- Tarih mantık kontrolleri (başlangıç < bitiş)
- Gelecek tarih kontrolleri

### 3. ✅ POS İade Mantığı
- Belge numarasında 'iade', 'İADE', 'IADE' kontrolü
- İadeler otomatik negatif miktar olarak işleniyor
- Net satış hesaplaması doğru çalışıyor

### 4. ✅ miktarKalan Güncelleme
- FIFO çıkışta katmanların kalan miktarı güncelleniyor
- Tüketilen katmanlar takip ediliyor

### 5. ✅ Yetersiz Stok Kontrolü
- Satış miktarı > mevcut katman kontrolü
- `STOK_YETERSIZ` sorun tipiyle loglama

### 6. ✅ fifo_StokMaliyetCikis Tablosuna Yazma
- Sonuçlar artık tabloya yazılıyor (sadece SELECT değil)
- İdempotent: Aynı tarih aralığı tekrar çalıştırılabilir

### 7. ✅ Ek İndeksler
- Filtered index (miktarKalan > 0)
- Raporlama için ek indeksler
- Performans iyileştirmeleri

### 8. ✅ Raporlama View'ları
- `fifo_vw_GunlukSMM` - Günlük maliyet raporu
- `fifo_vw_UrunBazliSMM` - Ürün bazlı rapor
- `fifo_vw_KatmanDurumu` - Katman durumu
- `fifo_vw_SorunluStoklar` - Sorun özeti

## 📁 Dosya Yapısı

```
00_MASTER_DEPLOY.sql          # Ana deployment scripti
01_tables_and_indexes.sql     # Tablolar ve indeksler
02_sp_fifo_StokMaliyetAcilis.sql   # Açılış prosedürü
03_sp_fifo_StokMaliyetAlisKatman.sql # Alış prosedürü
04_sp_fifo_StokMaliyetFIFOCikis.sql  # FIFO çıkış prosedürü
05_reporting_views.sql        # Raporlama view'ları
```

## 🚀 Kurulum

### Yöntem 1: Master Script ile
```sql
sqlcmd -S ServerName -d DatabaseName -i 00_MASTER_DEPLOY.sql
```

### Yöntem 2: Tek Tek
```sql
:r 01_tables_and_indexes.sql
:r 02_sp_fifo_StokMaliyetAcilis.sql
:r 03_sp_fifo_StokMaliyetAlisKatman.sql
:r 04_sp_fifo_StokMaliyetFIFOCikis.sql
:r 05_reporting_views.sql
```

## 📊 Kullanım Örnekleri

### Açılış Stoku Oluşturma
```sql
EXEC bkm.sp_fifo_StokMaliyetAcilis @envanterTarihi = '2024-09-30';
```

### Alış Katmanları Ekleme
```sql
EXEC bkm.sp_fifo_StokMaliyetAlisKatman 
    @baslangicTarihi = '2024-10-01', 
    @bitisTarihi = '2024-10-31';
```

### FIFO Çıkış Hesaplama
```sql
EXEC bkm.sp_fifo_StokMaliyetFIFOCikis 
    @satisBaslangic = '2024-10-01', 
    @satisBitis = '2024-10-31';
```

### Raporlar
```sql
-- Günlük SMM
SELECT * FROM bkm.fifo_vw_GunlukSMM 
WHERE hareketTarihi >= '2024-10-01';

-- Ürün bazlı
SELECT * FROM bkm.fifo_vw_UrunBazliSMM 
WHERE stkID = 12345;

-- Sorunlu stoklar
SELECT * FROM bkm.fifo_vw_SorunluStoklar;
```

## ⚠️ Önemli Notlar

1. **bkm şeması** zaten mevcut olduğu varsayılmıştır
2. **Transaction yönetimi** aktif - hata durumunda rollback
3. **İdempotent** - Aynı prosedürler tekrar çalıştırılabilir
4. **POS iade** - Belge numarasında 'iade' kelimesi aranıyor

## 🔍 Sorun Giderme

### Hataları Görüntüleme
```sql
SELECT * FROM bkm.fifo_StokMaliyetSorunlu 
ORDER BY kayitTarihi DESC;
```

### Katman Durumunu Kontrol
```sql
SELECT * FROM bkm.fifo_vw_KatmanDurumu 
WHERE kalanMiktar > 0;
```
