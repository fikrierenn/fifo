# BKM FIFO Stok Maliyet Sistemi - Kullanıcı Kılavuzu

## 📖 İçerik Tablosu

1. [Sistem Nedir?](#sistem-nedir)
2. [Neden Kullanmalıyım?](#neden-kullanmalıyım)
3. [Sistem Nasıl Çalışır?](#sistem-nasıl-çalışır)
4. [Kurulum ve Başlangıç](#kurulum-ve-başlangıç)
5. [Web Arayüzü Kullanımı](#web-arayüzü-kullanımı)
6. [Manuel Çalıştırma](#manuel-çalıştırma)
7. [Raporlama ve Analiz](#raporlama-ve-analiz)
8. [Sorun Giderme](#sorun-giderme)
9. [Sıkça Sorulan Sorular](#sıkça-sorulan-sorular)

---

## 🔍 Sistem Nedir?

**BKM FIFO Stok Maliyet Sistemi**, perakende işletmeleriniz için **stok maliyetlerini doğru bir şekilde hesaplayan** modern bir yazılımdır. **FIFO (First-In,First-Out)** yöntemini kullanarak ürünlerinizin maliyetini takip eder ve finansal raporlarınız için güvenilir veriler sunar.

### 🎯 Temel Amaç
- **Doğru Maliyet Hesaplama**: Ürünlerinizin gerçek maliyetini hesaplayın
- **Finansal Şeffaflık**: Stok değerinizi ve COGS (Satılan Mal Maliyeti) tutarlı şekilde takip edin
- **Otomatik İşlem**: Manuel hataları ortadan kaldıran otomatik hesaplama
- **Entegrasyon**: Mevcut ERP sisteminizle sorunsuz çalışın

---

## 💡 Neden Kullanmalıyım?

### 📊 Finansal Faydalar
- **Kar Marjı Optimizasyonu**: Gerçek maliyet bilgisiyle doğru fiyatlandırma yapın
- **Vergi Avantajları**: Doğru stok değerlendirmesi ile vergi avantajları kazanın
- **Bütçe Planlama**: Gelecek dönemler için daha accurate bütçeler hazırlayın

### 🛠️ Operasyonel Faydalar
- **Zaman Tasarrufu**: Manuel hesaplamalara son verin
- **Hata Azaltma**: İnsan kaynaklı hataları önleyin
- **Gerçek Zamanlı Veri**: Anlık stok ve maliyet bilgisi alın
- **Esnek Raporlama**: İhtiyacınıza özel raporlar oluşturun

---

## ⚙️ Sistem Nasıl Çalışır?

### 📋 İş Akışı

Sistem **2 ana katmanda** çalışır:

#### 🗓️ 1. Açılış (Devir) Katmanı
```
ERP Geçiş Tarihi ──► Stok Alışları ──► Envanter Tarihi
      │                   │              │
      ▼                   ▼              ▼
  Ters FIFO          Fatura          Stok
  Yaslandırması      Eşleştirme      Değeri
```

**Ne yapar?**
- ERP geçiş tarihinizden envanter tarihinize kadar olan tüm alışları çeker
- Bu alışları **ters FIFO** mantığıyla stoklarınızla eşleştirir
- Eğer stok miktarınız alış miktarından fazlaysa, eksik kalan için **ACILIS_TAMAMLA** kaydı oluşturur

#### 🔄 2. Dönem FIFO Katmanı
```
Ay Başlangıç ──► Alış Katmanlama ──► FIFO Çıkış ──► Maliyet Hesaplama
      │                   │              │              │
      ▼                   ▼              ▼              ▼
  Yeni Alışlar      ALIS Kayıtları    Satışlarla     Satış
  (Faturalar)      (Tarih Sıralı)    Çeşitlendirme  Maliyeti
```

**Ne yapar?**
- Ay içindeki tüm alış faturalarınızı **ALIS** olarak katmanlar
- Satışlarınızı geldiği tarihte **FIFO** mantığıyla en eski katmanlardan düşer
- Her satış için doğru birim maliyet hesaplar

### 🔄 FIFO Mantığı Örneği

**Örnek Senaryo:**
```
Katman 1: 10 Ocak - 100 adet @ 50 TL = 5.000 TL
Katman 2: 15 Ocak - 50 adet @ 55 TL = 2.750 TL
Katman 3: 20 Ocak - 75 adet @ 52 TL = 3.900 TL
Toplam Stok: 225 adet, 11.650 TL değerinde

Satış: 18 Ocak'ta 120 adet satış yapıldı

FIFO Çıkış:
- 100 adet x 50 TL = 5.000 TL (Katman 1'den)
- 20 adet x 55 TL = 1.100 TL (Katman 2'den)
Toplam Maliyet: 6.100 TL
Ortalama Birim Maliyet: 50.83 TL
```

---

## 🚀 Kurulum ve Başlangıç

### 📋 Gereksinimler
- **SQL Server** (2019 ve üstü)
- **.NET 10 Runtime**
- **Windows Server** veya **Windows 10/11**

### 🔧 Kurulum Adımları

#### Adım 1: Veritabanı Kurulumu
```sql
-- SQLCMD ile kurulum (tavsiye edilen)
sqlcmd -S ServerName -d DatabaseName -i 00_MASTER_DEPLOY.sql

-- veya SSMS ile manuel kurulum
-- 1. SQLCMD modunu açın
-- 2. Aşağıdaki komutları sırayla çalıştırın:
:r 01_tables_and_indexes.sql
:r 02_sp_fifo_StokMaliyetAcilis.sql
:r 03_sp_fifo_StokMaliyetAlisKatman.sql
:r 04_sp_fifo_StokMaliyetFIFOCikis.sql
:r 06_sp_fifo_StokMaliyetCalistir.sql
:r 05_reporting_views.sql
```

#### Adım 2: Web Uygulaması Kurulumu
```bash
# Proje klasörüne gidin
cd src/App

# Connection string'i düzenleyin
# appsettings.json dosyasında FifoDb'yi güncelleyin

# Uygulamayı başlatın
dotnet run
```

#### Adım 3: Konfigürasyon
**appsettings.json dosyasını düzenleyin:**
```json
{
  "ConnectionStrings": {
    "FifoDb": "Server=YOUR_SERVER;Database=YOUR_DATABASE;Trusted_Connection=true;"
  }
}
```

### 🎯 İlk Çalıştırma

#### Test Verisi Kontrolü
```sql
-- Envanter verisi kontrolü
SELECT COUNT(*) as stok_sayisi 
FROM dbo.stokSonAltDepo_vw 
WHERE ehAltDepo = 0 AND stok > 0;

-- Alış verisi kontrolü
SELECT COUNT(*) as alis_sayisi 
FROM dbo.irs 
WHERE eTip IN (2,0,10,3,6,102,103);

-- Satış verisi kontrolü  
SELECT COUNT(*) as satis_sayisi
FROM dbo.irs 
WHERE eTip IN (1,4,5,100,101);
```

---

## 🖥️ Web Arayüzü Kullanımı

### 🏠 Ana Sayfa (Home)

Web arayüzüne `http://localhost:5000` adresinden erişebilirsiniz.

**Ana Sayfada göreceğiniz bilgiler:**
- Sistem durumu ve genel istatistikler
- Son çalıştırmaların özeti
- Hızlı başlatma butonları

### 🔄 Çalıştırma Ekranı (Run)

Sistemin en önemli ekranıdır. Buradan FIFO hesaplamalarını çalıştırabilirsiniz.

#### 📊 Parametreler

**Tarih Parametreleri:**
- **Alış Başlangıç**: Alış katmanlarının başlangıç tarihi
- **Alış Bitiş**: Alış katmanlarının bitiş tarihi  
- **Satış Başlangıç**: FIFO çıkış başlangıç tarihi
- **Satış Bitiş**: FIFO çıkış bitiş tarihi

**Diğer Parametreler:**
- **Stok ID**: Tek bir ürün için çalıştırma (isteğe bağlı)
- **Alış Çalıştır**: Alış katmanlarını oluştur
- **Çıkış Çalıştır**: FIFO çıkış hesapla

#### 🎯 Kullanım Senaryoları

**Senaryo 1: Tam Dönem Çalıştırma**
```
Alış Başlangıç: 01.01.2026
Alış Bitiş: 31.01.2026
Satış Başlangıç: 01.01.2026  
Satış Bitiş: 31.01.2026
Stok ID: (boş)
Alış Çalıştır: ✓
Çıkış Çalıştır: ✓
```

**Senaryo 2: Sadece Alış Katmanlama**
```
Alış Başlangıç: 01.01.2026
Alış Bitiş: 31.01.2026
Satış Başlangıç: (boş)
Satış Bitiş: (boş)
Stok ID: (boş)
Alış Çalıştır: ✓
Çıkış Çalıştır: ✗
```

**Senaryo 3: Tek Ürün Test**
```
Alış Başlangıç: 01.01.2026
Alış Bitiş: 31.01.2026
Satış Başlangıç: 01.01.2026
Satış Bitiş: 31.01.2026
Stok ID: 392
Alış Çalıştır: ✓
Çıkış Çalıştır: ✓
```

#### 🔄 Çalıştırma Seçenekleri

**1. Anında Çalıştır (Post Button)**
- Tıklayın ve sonuçları bekleyin
- Sonuçlar aynı sayfada gösterilir
- Küçük tarih aralıkları için ideal

**2. Arka Planda Çalıştır (Start Button)**
- Run ID alarak arka planda çalıştırın
- İlerlemeyi canlı olarak takip edin
- Büyük tarih aralıkları için ideal

#### 📈 Sonuçlar

**Özet Bilgiler:**
- **Satır Sayısı**: Oluşturulan çıkış kayıtları
- **Ürün Sayısı**: İşlenen farklı ürün sayısı
- **Toplam Maliyet**: Hesaplanan toplam COGS

**Detay Kayıtlar:**
- Stok kodu
- Hareket tarihi
- Hareket tipi (SATIS/IADE)
- Miktar ve birim maliyet
- Çıkış tutarı

### 🐛 Sorunlar Ekranı (Issues)

Bu ekran sistemin tespit ettiği sorunları gösterir:

**Sorun Tipleri:**
- **ALIS_YOK**: İlgili ürün için alış bulunamadı
- **ALIS_EKSIK_TAMAMLANDI**: Eksik miktar son alış fiyatından tamamlandı
- **STOK_YETERSIZ**: Satış miktarı katman miktarını aştı

**İşlem Adımları:**
1. Sorunlu ürünleri listeleyin
2. Detayları inceleyin
3. Gerekli düzeltmeleri yapın
4. Tekrar çalıştırın

---

## 🔧 Manuel Çalıştırma

### 📝 SQL Management Studio ile Çalıştırma

#### 1. Açılış Stoku Oluşturma
```sql
EXEC bkm.sp_fifo_StokMaliyetAcilis 
    @envanterTarihi = '2025-12-31';
```

#### 2. Dönem Alışları ve FIFO
```sql
-- Alış katmanları
EXEC bkm.sp_fifo_StokMaliyetAlisKatman 
    @baslangicTarihi = '2026-01-01',
    @bitisTarihi = '2026-01-31';

-- FIFO çıkış
EXEC bkm.sp_fifo_StokMaliyetFIFOCikis 
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31';
```

#### 3. Tek Prosedür ile Tümünü Çalıştırma
```sql
EXEC bkm.sp_fifo_StokMaliyetCalistir
    @envanterTarihi = '2025-12-31',
    @alisBaslangic = '2026-01-01',
    @alisBitis = '2026-01-31',
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31',
    @calistirAcilis = 0,  -- Gece job'ı için 0
    @calistirAlis = 1,
    @calistirCikis = 1;
```

### 🎯 Tek Ürün için Çalıştırma
```sql
EXEC bkm.sp_fifo_StokMaliyetCalistir
    @envanterTarihi = '2025-12-31',
    @alisBaslangic = '2026-01-01',
    @alisBitis = '2026-01-31',
    @satisBaslangic = '2026-01-01',
    @satisBitis = '2026-01-31',
    @stkID = 392,  -- Sadece 392 numaralı ürün
    @calistirAcilis = 0,
    @calistirAlis = 1,
    @calistirCikis = 1;
```

---

## 📊 Raporlama ve Analiz

### 📋 Temel Raporlar

#### 1. Günlük Stok Maliyet Raporu
```sql
SELECT * FROM bkm.fifo_vw_GunlukSMM
WHERE hareketTarihi >= '2026-01-01'
ORDER BY hareketTarihi DESC, stkID;
```

**Gösterdiği bilgiler:**
- Tarihe göre stok hareketleri
- Birim maliyet değişimleri
- Günlük COGS toplamları

#### 2. Ürün Bazlı Maliyet Raporu
```sql
SELECT * FROM bkm.fifo_vw_UrunBazliSMM
WHERE stkID = 392
ORDER BY hareketTarihi DESC;
```

**Gösterdiği bilgiler:**
- Tek ürünün tüm maliyet geçmişi
- Ortalama maliyet trendi
- Toplam maliyet dağılımı

#### 3. Katman Durumu Raporu
```sql
SELECT * FROM bkm.fifo_vw_KatmanDurumu
WHERE kalanMiktar > 0
ORDER BY stkID, girisTarihi;
```

**Gösterdiği bilgiler:**
- Mevcut stok katmanları
- Kalan miktarlar
- Katman bazında maliyetler

#### 4. Sorunlu Stoklar Raporu
```sql
SELECT * FROM bkm.fifo_vw_SorunluStoklar
ORDER BY envanterTarihi DESC, sorunTip;
```

**Gösterdiği bilgiler:**
- Tüm sistem sorunları
- Sorun tiplerine göre gruplama
- Çözüm önerileri

### 🔍 Analiz Sorguları

#### En Yüksek Maliyetli Ürünler
```sql
SELECT TOP 10
    stkID,
    SUM(miktar) AS toplamMiktar,
    SUM(cikisTutar) AS toplamMaliyet,
    AVG(birimMaliyet) AS ortalamaMaliyet
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= '2026-01-01'
GROUP BY stkID
ORDER BY SUM(cikisTutar) DESC;
```

#### Aylık COGS Analizi
```sql
SELECT 
    YEAR(hareketTarihi) AS yil,
    MONTH(hareketTarihi) AS ay,
    SUM(CASE WHEN hareketTipi = 'SATIS' THEN cikisTutar ELSE 0 END) AS satisCOGS,
    SUM(CASE WHEN hareketTipi = 'IADE' THEN cikisTutar ELSE 0 END) AS iadeCOGS,
    SUM(cikisTutar) AS netCOGS
FROM bkm.fifo_StokMaliyetCikis
WHERE hareketTarihi >= '2026-01-01'
GROUP BY YEAR(hareketTarihi), MONTH(hareketTarihi)
ORDER BY yil, ay;
```

---

## 🚨 Sorun Giderme

### 🔍 Yaygın Sorunlar ve Çözümleri

#### 1. **Connection String Hatası**
**Sorun:** "Missing ConnectionStrings:FifoDb"
**Çözüm:** `appsettings.json` dosyasında connection string'i kontrol edin

#### 2. **Veri Bulunamadı Hatası**
**Sorun:** "Alış bulunamadı" veya "Stok yetersiz"
**Çözüm:** 
```sql
-- Envanter kontrolü
SELECT * FROM dbo.stokSonAltDepo_vw 
WHERE ehAltDepo = 0 AND stok > 0 AND stkID = [PROBLEMATIC_ID];

-- Alış kontrolü
SELECT * FROM dbo.irs 
WHERE eTip IN (2,0,10,3,6,102,103) 
  AND stkID = [PROBLEMATIC_ID];
```

#### 3. **Performans Sorunları**
**Sorun:** Çalıştırma çok uzun sürüyor
**Çözüm:**
- Daha küçük tarih aralıkları kullanın
- Tek ürün testi yapın
- İndeksleri kontrol edin

#### 4. **FIFO Tutarlılığı**
**Sorun:** Maliyetler beklenmedik
**Çözüm:**
```sql
-- Katman kontrolü
SELECT * FROM bkm.fifo_StokMaliyetHavuzu 
WHERE stkID = [PROBLEMATIC_ID]
ORDER BY girisTarihi;

-- Çıkış kontrolü
SELECT * FROM bkm.fifo_StokMaliyetCikis 
WHERE stkID = [PROBLEMATIC_ID]
ORDER BY hareketTarihi;
```

### 🛠️ Bakım İşlemleri

#### Günlük Kontrol
```sql
-- Son çalıştırma kontrolü
SELECT TOP 5 * FROM bkm.fifo_Run 
ORDER BY requestedAt DESC;

-- Sorun kontrolü
SELECT COUNT(*) as sorun_sayisi 
FROM bkm.fifo_StokMaliyetSorunlu 
WHERE kayitTarihi >= DATEADD(day, -1, GETDATE());
```

#### Performans İzleme
```sql
-- Büyük tablolar
SELECT 
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    p.rows AS row_count
FROM sys.indexes i
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE OBJECT_NAME(i.object_id) LIKE 'fifo_%'
ORDER BY p.rows DESC;
```

---

## ❓ Sıkça Sorulan Sorular

### 🤔 Genel Sorular

**S: FIFO yöntemi ne anlama geliyor?**
C: First-In, First-Out (İlk Giren, İlk Çıkar) demektir. Stoklarınızı girdiği sırayla çıkararak en eski stokların önce satılmasını sağlar.

**S: Sistem hangi verileri kullanıyor?**
C: Mevcut ERP sisteminizden:
- Envanter verileri (`stokSonAltDepo_vw`)
- Alış faturaları (`irs`, `irsAyr`, `fatAyr`, `fat`)
- Satış faturaları (`irs`, `irsAyr`)

**S: Kaç ürün destekliyor?**
C: Testler 100.000+ ürün ile yapılmıştır. Sistem büyük ölçekte çalışabilir.

### 🔧 Teknik Sorular

**S: Sistem ne sıklıkla çalışmalı?**
C: 
- Açılış: Yıl/kapanışlarda bir kez
- Dönem: Aylık veya haftalık
- Tek ürün: İhtiyaç anında

**S: Geri alma (rollback) mümkün mü?**
C: Evet, tüm prosedürler idempotent'tir. Aynı tarih aralığı tekrar çalıştırılabilir.

**S: İade işlemleri nasıl ele alınıyor?**
C: Belge numarasında 'iade', 'İADE', 'IADE' kelimeleri varsa otomatik olarak negatif miktar olarak işlenir.

### 📊 Veri Soruları

**S: COGS nasıl hesaplanıyor?**
C: Satış miktarı × FIFO birim maliyeti = COGS. Her satış için kullanılan katmanın maliyeti kullanılır.

**S: Stok değeri nasıl takip ediliyor?**
C: `miktarKalan × birimMaliyet` formülü ile her katman için ayrı ayrı hesaplanır.

**S: Raporları dışa aktarabilir miyim?**
C: Evet, tüm raporlar SQL üzerinden CSV, Excel gibi formatlara aktarılabilir.

---

## 📞 Destek

### 🆘 Yardım Alın

**Teknik Destek için:**
1. **Sorunları Ekranı**nı kontrol edin
2. **LOG** kayıtlarını inceleyin
3. **Test senaryolarını** çalıştırın
4. **Gerekli bilgileri** toplayın

**Bildirilecek Bilgiler:**
- Hata mesajı
- Çalıştırılan parametreler
- Stok ID (varsa)
- Tarih aralığı
- Ekran görüntüsü

### 📚 Ek Kaynaklar

- **README.md**: Teknik detaylar ve kurulum
- **docs/** klasörü: Architecture ve algorithm docs
- **TEST_*.sql** dosyaları: Test senaryoları

---

## 🎯 Sonuç

BKM FIFO Stok Maliyet Sistemi, perakende işletmeleriniz için **güvenilir, hızlı ve modern** bir stok maliyet yönetimi çözümüdür. Doğru finansal raporlama, kar marjı optimizasyonu ve operasyonel verimlilik için ihtiyaçlarınızı karşılar.

**Unutmayın:**
- ✅ Düzenli çalıştırın (aylık/haftalık)
- ✅ Sorunları izleyin ve çözün
- ✅ Raporları analiz edin
- ✅ Veri doğruluğunu kontrol edin

Sorularınız için teknik dokümantasyonu inceleyebilir veya destek ekibimize ulaşabilirsiniz.

---

*BKM FIFO Stok Maliyet Sistemi - Kullanıcı Kılavuzu v1.0*
*Son Güncelleme: Ocak 2026*
