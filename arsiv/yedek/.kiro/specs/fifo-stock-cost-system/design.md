# Tasarım Dokümanı

## Genel Bakış

FIFO Stok Maliyet Havuzu Sistemi, perakende ortamlarında (fiziksel mağazalar ve e-ticaret) stok maliyetlerini İlk Giren İlk Çıkar (FIFO) metodolojisi ile yöneten kapsamlı bir SQL Server tabanlı sistemdir. Sistem, açılış stok katmanlarını, dönem içi alış katmanlarını ve satış/iade hareketlerini yöneterek muhasebe standartlarına uygun Satılan Malın Maliyeti (SMM/COGS) hesaplaması yapar.

Sistem üç ana prosedür etrafında yapılandırılmıştır:
1. **sp_StokMaliyetAcilis** - Açılış stok katmanlarını başlatır
2. **sp_StokMaliyetAlisKatman** - Dönem içi alış katmanlarını yönetir
3. **sp_StokMaliyetFIFOCikis** - FIFO metodolojisi ile satış/iade maliyetlendirmesi yapar

## Mimari

### Katmanlı Yapı

```
┌─────────────────────────────────────────────────────────┐
│              Raporlama Katmanı                          │
│  (Günlük SMM, Ürün Bazlı Maliyet Raporları)            │
└─────────────────────────────────────────────────────────┘
                          ↑
┌─────────────────────────────────────────────────────────┐
│              İş Mantığı Katmanı                         │
│  (sp_StokMaliyetAcilis, sp_StokMaliyetAlisKatman,      │
│   sp_StokMaliyetFIFOCikis)                             │
└─────────────────────────────────────────────────────────┘
                          ↑
┌─────────────────────────────────────────────────────────┐
│              Veri Katmanı                               │
│  (StokMaliyetHavuzu, StokEnvanter,                     │
│   StokMaliyetCikis, StokMaliyetSorunlu)                │
└─────────────────────────────────────────────────────────┘
                          ↑
┌─────────────────────────────────────────────────────────┐
│              Kaynak Veri Katmanı                        │
│  (irs, irsAyr, fat, fatAyr, stokSonAltDepo_vw)         │
└─────────────────────────────────────────────────────────┘
```

### Veri Akışı

1. **Açılış Akışı**: stokSonAltDepo_vw → Ters-FIFO Hesaplama → StokMaliyetHavuzu (ACILIS/ACILIS_TAMAMLA)
2. **Alış Akışı**: irs/irsAyr/fat/fatAyr → Birim Maliyet Hesaplama → StokMaliyetHavuzu (ALIS)
3. **Satış Akışı**: irs/irsAyr → Net Satış Hesaplama → FIFO Eşleştirme → StokMaliyetCikis

## Bileşenler ve Arayüzler

### 1. Veri Tabloları

#### 1.1 bkm.StokMaliyetHavuzu
**Amaç**: Tüm maliyet katmanlarını (açılış, alış, iade) merkezi olarak saklar.

**Alanlar**:
- `ID` (INT, PK): Benzersiz katman tanımlayıcı
- `stkID` (INT): Ürün ID
- `girisTarihi` (DATE): Katman giriş tarihi
- `kaynakTip` (VARCHAR(20)): 'ACILIS', 'ACILIS_TAMAMLA', 'ALIS', 'IADE'
- `belgeNo` (VARCHAR(50)): Kaynak belge numarası
- `miktarToplam` (DECIMAL(18,4)): Katmanın toplam miktarı
- `miktarKalan` (DECIMAL(18,4)): Katmanın kalan miktarı
- `birimMaliyet` (DECIMAL(18,6)): Birim maliyet
- `durum` (VARCHAR(20)): 'NORMAL', 'TAMAMLAMA'
- `kayitTarihi` (DATETIME): Kayıt oluşturma zamanı

**İndeksler**:
- `IX_StokMaliyetHavuzu_stkID` (stkID, girisTarihi, kaynakTip)

#### 1.2 bkm.StokEnvanter
**Amaç**: Envanter tarihindeki stok anlık görüntüsünü saklar.

**Alanlar**:
- `ID` (INT, PK): Benzersiz kayıt tanımlayıcı
- `envanterTarihi` (DATE): Envanter tarihi
- `stkID` (INT): Ürün ID
- `stokMiktar` (DECIMAL(18,4)): Stok miktarı
- `kayitTarihi` (DATETIME): Kayıt oluşturma zamanı

**İndeksler**:
- `IX_StokEnvanter_TarihStok` (envanterTarihi, stkID)

#### 1.3 bkm.StokMaliyetSorunlu
**Amaç**: Açılış veya işleme sırasında tespit edilen sorunları loglar.

**Alanlar**:
- `ID` (INT, PK): Benzersiz kayıt tanımlayıcı
- `stkID` (INT): Ürün ID
- `envanterTarihi` (DATE): İlgili envanter tarihi
- `stokMiktar` (DECIMAL(18,4)): Sorunlu stok miktarı
- `sorunTip` (VARCHAR(50)): 'ALIS_YOK', 'ALIS_EKSIK_TAMAMLANDI', 'STOK_YETERSIZ'
- `aciklama` (VARCHAR(500)): Sorun açıklaması
- `kayitTarihi` (DATETIME): Kayıt oluşturma zamanı

**İndeksler**:
- `IX_StokMaliyetSorunlu_TarihStok` (envanterTarihi, stkID)

#### 1.4 bkm.StokMaliyetCikis
**Amaç**: FIFO ile maliyetlendirilmiş satış/iade detaylarını saklar.

**Alanlar**:
- `ID` (INT, PK): Benzersiz kayıt tanımlayıcı
- `stkID` (INT): Ürün ID
- `hareketTarihi` (DATE): Satış/iade tarihi
- `hareketTipi` (VARCHAR(10)): 'SATIS', 'IADE'
- `satisBelgeNo` (VARCHAR(50)): Satış belge numarası (opsiyonel)
- `katmanID` (INT): İlgili StokMaliyetHavuzu.ID
- `katmanTarihi` (DATE): Katman giriş tarihi
- `katmanBelgeNo` (VARCHAR(50)): Katman belge numarası
- `miktar` (DECIMAL(18,4)): Çıkış miktarı
- `birimMaliyet` (DECIMAL(18,6)): Birim maliyet
- `cikisTutar` (COMPUTED): miktar * birimMaliyet
- `kayitTarihi` (DATETIME): Kayıt oluşturma zamanı

**İndeksler**:
- `IX_StokMaliyetCikis_StokTarih` (stkID, hareketTarihi)

### 2. Saklı Prosedürler

#### 2.1 bkm.sp_StokMaliyetAcilis
**Amaç**: Belirtilen envanter tarihi için açılış stok katmanlarını oluşturur.

**Parametreler**:
- `@envanterTarihi` (DATE): Açılış stoku oluşturulacak tarih

**İş Akışı**:
1. Envanter tarihindeki stok miktarlarını `stokSonAltDepo_vw`'den okur
2. Stok snapshot'ını `bkm.StokEnvanter`'e kaydeder
3. 31.05.2021 - envanter tarihi arası alışları toplar
4. Ters-FIFO algoritması ile açılış katmanlarını hesaplar
5. Açılış katmanlarını 'ACILIS' tipiyle `StokMaliyetHavuzu`'na yazar
6. Yetersiz alış olan ürünler için son alış fiyatıyla 'ACILIS_TAMAMLA' katmanı oluşturur
7. Hiç alış bulunamayan ürünleri 'ALIS_YOK' sorun tipiyle `StokMaliyetSorunlu`'ya kaydeder

**Ters-FIFO Algoritması**:
```sql
-- Alışları ters kronolojik sırada kümülatif topla
kumTers = SUM(miktar) OVER (
    PARTITION BY stkID
    ORDER BY girisTarihi DESC, belgeNo DESC
    ROWS UNBOUNDED PRECEDING
)

-- Her alış için açılış miktarını hesapla
acilisMiktar = CASE 
    WHEN kumTers - miktar >= stokMiktar THEN 0
    WHEN kumTers <= stokMiktar THEN miktar
    ELSE stokMiktar - (kumTers - miktar)
END
```

#### 2.2 bkm.sp_StokMaliyetAlisKatman
**Amaç**: Belirtilen tarih aralığındaki alış işlemlerini maliyet katmanları olarak ekler.

**Parametreler**:
- `@baslangicTarihi` (DATE): Başlangıç tarihi
- `@bitisTarihi` (DATE): Bitiş tarihi

**İş Akışı**:
1. Tarih aralığındaki alış belgelerini (irs, irsAyr, fat, fatAyr) okur
2. Ürün + tarih + belge bazında net miktar ve net tutar hesaplar
3. Birim maliyet = netTutar / miktar hesabını yapar
4. Aynı tarih aralığındaki eski 'ALIS' katmanlarını siler (idempotency)
5. Yeni 'ALIS' katmanlarını `StokMaliyetHavuzu`'na ekler

**Birim Maliyet Hesaplama**:
```sql
birimMaliyet = CASE 
    WHEN miktar = 0 THEN 0 
    ELSE netTutar / miktar 
END
```

#### 2.3 bkm.sp_StokMaliyetFIFOCikis
**Amaç**: Satış ve iade işlemlerini FIFO metodolojisi ile maliyetlendirir.

**Parametreler**:
- `@satisBaslangic` (DATE): Satış başlangıç tarihi
- `@satisBitis` (DATE): Satış bitiş tarihi

**İş Akışı**:
1. Maliyet havuzundan tüm katmanları (ACILIS, ACILIS_TAMAMLA, ALIS) okur
2. Satış hareketlerini gün + ürün bazında net miktar olarak toplar
3. Katmanlar için kümülatif eksen oluşturur (layerCumStart, layerCumEnd)
4. Satışlar için kümülatif eksen oluşturur (satisCumStart, satisCumEnd)
5. Kesişim mantığı ile FIFO dağılımını hesaplar
6. Sonuçları döndürür (veya `StokMaliyetCikis`'e yazar)

**FIFO Kesişim Algoritması**:
```sql
cikisMiktar = CASE 
    WHEN layerCumEnd <= satisCumStart 
      OR satisCumEnd <= layerCumStart THEN 0
    ELSE
        MIN(layerCumEnd, satisCumEnd) - MAX(layerCumStart, satisCumStart)
END
```

## Veri Modelleri

### Maliyet Katmanı Yaşam Döngüsü

```
┌──────────────┐
│   OLUŞTUR    │
│  (INSERT)    │
└──────┬───────┘
       │
       ↓
┌──────────────────────────────┐
│  miktarToplam = X            │
│  miktarKalan = X             │
│  kaynakTip = ACILIS/ALIS     │
└──────┬───────────────────────┘
       │
       ↓
┌──────────────┐
│   TÜKET      │
│  (FIFO)      │
└──────┬───────┘
       │
       ↓
┌──────────────────────────────┐
│  miktarToplam = X            │
│  miktarKalan = X - tüketim   │
└──────┬───────────────────────┘
       │
       ↓
┌──────────────┐
│  miktarKalan │
│     = 0?     │
└──────┬───────┘
       │
       ├─── Evet ──→ Katman Tükendi
       │
       └─── Hayır ──→ Katman Aktif
```

### Kümülatif Eksen Modeli

FIFO eşleştirmesi için hem katmanlar hem de satışlar kümülatif eksene dönüştürülür:

**Katman Ekseni**:
```
Katman 1: [0, 100)    - 100 adet, 10 TL
Katman 2: [100, 250)  - 150 adet, 12 TL
Katman 3: [250, 300)  - 50 adet, 11 TL
```

**Satış Ekseni**:
```
Satış 1: [0, 80)      - 80 adet, 01.01.2024
Satış 2: [80, 200)    - 120 adet, 02.01.2024
```

**Kesişim Hesaplama**:
- Satış 1 [0, 80) ∩ Katman 1 [0, 100) = [0, 80) → 80 adet @ 10 TL
- Satış 2 [80, 200) ∩ Katman 1 [0, 100) = [80, 100) → 20 adet @ 10 TL
- Satış 2 [80, 200) ∩ Katman 2 [100, 250) = [100, 200) → 100 adet @ 12 TL


## Doğruluk Özellikleri (Correctness Properties)

*Bir özellik (property), bir sistemin tüm geçerli çalıştırmalarında doğru olması gereken bir karakteristik veya davranıştır - esasen, sistemin ne yapması gerektiği hakkında resmi bir ifadedir. Özellikler, insan tarafından okunabilir spesifikasyonlar ile makine tarafından doğrulanabilir doğruluk garantileri arasında köprü görevi görür.*

### Özellik 1: Envanter Okuma Doğruluğu
*Herhangi bir* envanter tarihi için, açılış prosedürü çalıştırıldığında, StokEnvanter tablosuna yazılan stok miktarları kaynak görünümden (stokSonAltDepo_vw) okunan miktarlarla eşit olmalıdır.
**Doğrular: Gereksinim 1.1**

### Özellik 2: Ters-FIFO Katman Toplamı
*Herhangi bir* ürün için, ters-FIFO ile oluşturulan tüm ACILIS katmanlarının toplam miktarı, o ürünün envanter miktarını aşmamalı ve mümkün olduğunca yakın olmalıdır.
**Doğrular: Gereksinim 1.2**

### Özellik 3: Tamamlama Katmanı Oluşturma
*Herhangi bir* ürün için, eğer alış geçmişi envanter miktarını karşılamıyorsa, eksik miktar için ACILIS_TAMAMLA katmanı oluşturulmalı ve bu katmanın birim maliyeti son alış birim maliyetine eşit olmalıdır.
**Doğrular: Gereksinim 1.3**

### Özellik 4: Alış Bulunamama Kaydı
*Herhangi bir* ürün için, eğer belirtilen tarih aralığında hiç alış bulunamazsa, StokMaliyetSorunlu tablosuna 'ALIS_YOK' sorun tipiyle kayıt eklenmelidir.
**Doğrular: Gereksinim 1.4**

### Özellik 5: Açılış Katman Alanları
*Herhangi bir* açılış katmanı için, kaynakTip 'ACILIS' veya 'ACILIS_TAMAMLA' olmalı, durum 'NORMAL' veya 'TAMAMLAMA' olmalı ve miktarKalan miktarToplam'a eşit olmalıdır.
**Doğrular: Gereksinim 1.5**

### Özellik 6: Alış Belge Filtreleme
*Herhangi bir* tarih aralığı için, alış katman prosedürü sadece eTip IN (2,0,10) olan belgeleri okumalı ve işlemelidir.
**Doğrular: Gereksinim 2.1**

### Özellik 7: Birim Maliyet Hesaplama Doğruluğu
*Herhangi bir* alış işlemi için, eğer miktar sıfırdan farklıysa, birim maliyet netTutar / miktar formülüne eşit olmalıdır.
**Doğrular: Gereksinim 2.2**

### Özellik 8: Net Alış Hesaplama
*Herhangi bir* ürün ve tarih kombinasyonu için, hem borç hem de alacak girişleri içeren alışlarda, net miktar ve net tutar doğru hesaplanmalı (alacaklar negatif işaretli).
**Doğrular: Gereksinim 2.3**

### Özellik 9: Alış Katman İdempotency
*Herhangi bir* tarih aralığı için, alış katman prosedürü aynı parametrelerle birden fazla kez çalıştırıldığında, aynı sonucu üretmelidir (eski kayıtlar silinip yenileri eklenir).
**Doğrular: Gereksinim 2.4**

### Özellik 10: Yeni Alış Katman Alanları
*Herhangi bir* yeni alış katmanı için, kaynakTip 'ALIS' olmalı, miktarKalan miktarToplam'a eşit olmalı ve durum 'NORMAL' olmalıdır.
**Doğrular: Gereksinim 2.5**

### Özellik 11: Satış Belge Filtreleme
*Herhangi bir* tarih aralığı için, satış prosedürü sadece eTip IN (1,4,5,100,101) ve eMekan IN (1,4477,4478) olan belgeleri okumalı ve işlemelidir.
**Doğrular: Gereksinim 3.1**

### Özellik 12: Günlük Net Satış Hesaplama
*Herhangi bir* ürün ve gün kombinasyonu için, net miktar o güne ait tüm satış ve iade işlemlerinin toplamı olmalıdır (iadeler negatif).
**Doğrular: Gereksinim 3.2**

### Özellik 13: POS İade İşareti
*Herhangi bir* POS iade işlemi için, net satış hesaplamasında negatif miktar olarak işlenmelidir.
**Doğrular: Gereksinim 3.3**

### Özellik 14: Pozitif Net Miktar İşleme
*Herhangi bir* günlük net miktar pozitif olduğunda, sistem bunu satış işlemi olarak kabul etmeli ve stoğu azaltmalıdır.
**Doğrular: Gereksinim 3.4**

### Özellik 15: Negatif Net Miktar İşleme
*Herhangi bir* günlük net miktar negatif olduğunda, sistem bunu iade işlemi olarak kabul etmeli ve stoğu artırmalıdır.
**Doğrular: Gereksinim 3.5**

### Özellik 16: Katman Kronolojik Sıralama
*Herhangi bir* ürün için, FIFO eşleştirmesinde kullanılan katmanlar girisTarihi ve ID'ye göre artan sırada olmalıdır.
**Doğrular: Gereksinim 4.1**

### Özellik 17: Katman Kümülatif Eksen Tutarlılığı
*Herhangi bir* ürün için, katman kümülatif ekseninde her katmanın layerCumEnd değeri, bir önceki katmanın layerCumEnd değerine o katmanın miktarToplam değeri eklenmiş olmalıdır.
**Doğrular: Gereksinim 4.2**

### Özellik 18: Satış Kümülatif Eksen Tutarlılığı
*Herhangi bir* ürün için, satış kümülatif ekseninde her satışın satisCumEnd değeri, bir önceki satışın satisCumEnd değerine o satışın netMiktar değeri eklenmiş olmalıdır.
**Doğrular: Gereksinim 4.3**

### Özellik 19: FIFO Kesişim Doğruluğu
*Herhangi bir* satış ve katman çifti için, kesişim miktarı MIN(layerCumEnd, satisCumEnd) - MAX(layerCumStart, satisCumStart) formülüne eşit olmalı ve negatif olmamalıdır.
**Doğrular: Gereksinim 4.4**

### Özellik 20: Kısmi Katman Tüketimi
*Herhangi bir* satış bir katmanı kısmen tükettiğinde, o katmanın miktarKalan değeri azaltılmalı ve kalan satış miktarı bir sonraki katmandan karşılanmalıdır.
**Doğrular: Gereksinim 4.5**

### Özellik 21: Tam Katman Tüketimi
*Herhangi bir* satış bir katmanı tamamen tükettiğinde, o katmanın miktarKalan değeri sıfır olmalı ve kalan satış miktarı bir sonraki katmandan karşılanmalıdır.
**Doğrular: Gereksinim 4.6**

### Özellik 22: İade FIFO Eşleştirmesi
*Herhangi bir* iade işlemi için, iade miktarı FIFO mantığı ile katmanlara geri eklenmelidir.
**Doğrular: Gereksinim 4.7**

### Özellik 23: Çıkış Kaydı Yazma
*Herhangi bir* FIFO eşleştirme sonucu için, her kesişim StokMaliyetCikis tablosuna bir satır olarak yazılmalıdır.
**Doğrular: Gereksinim 5.1**

### Özellik 24: Çıkış Kaydı Alan Bütünlüğü
*Herhangi bir* çıkış kaydı için, stkID, hareketTarihi, hareketTipi, katmanID, katmanTarihi, miktar, birimMaliyet ve cikisTutar alanları dolu olmalıdır.
**Doğrular: Gereksinim 5.2**

### Özellik 25: Satış Kaydı Format
*Herhangi bir* satış çıkış kaydı için, hareketTipi 'SATIS' olmalı ve miktar pozitif olmalıdır.
**Doğrular: Gereksinim 5.3**

### Özellik 26: İade Kaydı Format
*Herhangi bir* iade çıkış kaydı için, hareketTipi 'IADE' olmalı ve SMM'ye negatif etki yapmalıdır.
**Doğrular: Gereksinim 5.4**

### Özellik 27: Katman Kalan Miktar Güncelleme
*Herhangi bir* katman tüketimi için, StokMaliyetHavuzu'ndaki miktarKalan değeri tüketilen miktar kadar azaltılmalıdır.
**Doğrular: Gereksinim 5.5**

### Özellik 28: Günlük SMM Toplama
*Herhangi bir* tarih için, günlük SMM raporu o tarihteki tüm çıkış kayıtlarının toplamı olmalıdır.
**Doğrular: Gereksinim 6.1**

### Özellik 29: Ürün Bazlı SMM Toplama
*Herhangi bir* ürün ve tarih kombinasyonu için, ürün bazlı SMM raporu o ürün ve tarihe ait tüm çıkış kayıtlarının toplamı olmalıdır.
**Doğrular: Gereksinim 6.2**

### Özellik 30: Dönem SMM Hesaplama
*Herhangi bir* dönem için, toplam SMM hareketTipi 'SATIS' olan tüm kayıtların cikisTutar toplamı olmalıdır.
**Doğrular: Gereksinim 6.3**

### Özellik 31: İade SMM Etkisi
*Herhangi bir* dönem için, iade etkisi hareketTipi 'IADE' olan tüm kayıtların cikisTutar toplamı olmalı ve SMM'yi azaltmalıdır.
**Doğrular: Gereksinim 6.4**

### Özellik 32: SMM Rapor İçeriği
*Herhangi bir* SMM raporu için, ürün detayları, işlem tarihleri, miktarlar, birim maliyetler ve toplam maliyet tutarları içerilmelidir.
**Doğrular: Gereksinim 6.5**

### Özellik 33: Yetersiz Stok Kaydı
*Herhangi bir* satış için, eğer satış miktarı mevcut katman miktarlarını aşıyorsa, 'STOK_YETERSIZ' sorun tipiyle StokMaliyetSorunlu tablosuna kayıt eklenmelidir.
**Doğrular: Gereksinim 7.3**

### Özellik 34: Prosedür İdempotency
*Herhangi bir* prosedür için, aynı parametrelerle birden fazla kez çalıştırıldığında, aynı sonucu üretmelidir (önceki kayıtlar temizlenip yenileri eklenir).
**Doğrular: Gereksinim 7.4**

## Hata Yönetimi

### Validasyon Kuralları

1. **Sıfır/Null Miktar**: Miktar sıfır veya null olan işlemler atlanır ve uyarı loglanır
2. **Sıfıra Bölme**: Birim maliyet hesaplamasında miktar sıfırsa, işlem atlanır ve hata loglanır
3. **Yetersiz Stok**: Satış miktarı mevcut katmanları aşarsa, sorun tablosuna kaydedilir
4. **Transaction Rollback**: Herhangi bir veritabanı hatası durumunda işlem geri alınır

### Hata Tipleri

| Sorun Tipi | Açıklama | Çözüm |
|------------|----------|-------|
| ALIS_YOK | Ürün için hiç alış bulunamadı | Manuel maliyet belirleme gerekli |
| ALIS_EKSIK_TAMAMLANDI | Alış yetersiz, son fiyatla tamamlandı | Bilgilendirme amaçlı |
| STOK_YETERSIZ | Satış miktarı mevcut stoğu aşıyor | Stok sayımı veya veri düzeltme gerekli |

## Test Stratejisi

### Birim Testleri

Birim testler belirli senaryoları ve edge case'leri doğrular:

1. **Açılış Prosedürü Testleri**:
   - Boş envanter durumu
   - Tek ürün tek alış senaryosu
   - Çoklu alış katmanları senaryosu
   - Alış bulunamayan ürün senaryosu
   - Yetersiz alış senaryosu

2. **Alış Katman Testleri**:
   - Tek alış belgesi
   - Borç-alacak karışık belgeler
   - Sıfır miktar filtreleme
   - İdempotency testi (aynı prosedürü iki kez çalıştırma)

3. **FIFO Çıkış Testleri**:
   - Tek katman tek satış
   - Çoklu katman tek satış
   - Tek katman çoklu satış
   - Kısmi katman tüketimi
   - Tam katman tüketimi
   - İade senaryosu

### Property-Based Testleri

Property-based testler, rastgele üretilen verilerle özelliklerin tüm girdi uzayında doğruluğunu test eder. SQL Server için [tSQLt](https://tsqlt.org/) framework'ü kullanılabilir.

**Test Framework**: tSQLt (SQL Server için birim test framework'ü)

**Minimum İterasyon Sayısı**: Her property-based test en az 100 iterasyon çalıştırılmalıdır.

**Property Test Örnekleri**:

1. **Özellik 2 Testi - Ters-FIFO Katman Toplamı**:
```sql
-- Feature: fifo-stock-cost-system, Property 2: Ters-FIFO Katman Toplamı
CREATE PROCEDURE test_TersFIFO_KatmanToplami
AS
BEGIN
    -- 100 iterasyon için rastgele ürün ve alış verileri üret
    -- Her iterasyonda:
    -- 1. Rastgele envanter miktarı oluştur
    -- 2. Rastgele alış katmanları oluştur
    -- 3. sp_StokMaliyetAcilis çalıştır
    -- 4. ACILIS katmanlarının toplamının envanter miktarını aşmadığını doğrula
    
    DECLARE @iteration INT = 0;
    WHILE @iteration < 100
    BEGIN
        -- Test mantığı
        SET @iteration = @iteration + 1;
    END
END
```

2. **Özellik 19 Testi - FIFO Kesişim Doğruluğu**:
```sql
-- Feature: fifo-stock-cost-system, Property 19: FIFO Kesişim Doğruluğu
CREATE PROCEDURE test_FIFO_KesisimDogrulugu
AS
BEGIN
    -- 100 iterasyon için rastgele katman ve satış verileri üret
    -- Her iterasyonda:
    -- 1. Rastgele katmanlar oluştur
    -- 2. Rastgele satışlar oluştur
    -- 3. Kümülatif eksen hesapla
    -- 4. Kesişim miktarlarının formüle uygun ve negatif olmadığını doğrula
    
    DECLARE @iteration INT = 0;
    WHILE @iteration < 100
    BEGIN
        -- Test mantığı
        SET @iteration = @iteration + 1;
    END
END
```

3. **Özellik 9 Testi - Alış Katman İdempotency**:
```sql
-- Feature: fifo-stock-cost-system, Property 9: Alış Katman İdempotency
CREATE PROCEDURE test_AlisKatman_Idempotency
AS
BEGIN
    -- 100 iterasyon için rastgele tarih aralıkları ve alış verileri üret
    -- Her iterasyonda:
    -- 1. Rastgele alış verileri oluştur
    -- 2. sp_StokMaliyetAlisKatman'ı çalıştır
    -- 3. Sonuçları kaydet
    -- 4. Aynı prosedürü tekrar çalıştır
    -- 5. Sonuçların aynı olduğunu doğrula
    
    DECLARE @iteration INT = 0;
    WHILE @iteration < 100
    BEGIN
        -- Test mantığı
        SET @iteration = @iteration + 1;
    END
END
```

### Entegrasyon Testleri

Entegrasyon testleri, prosedürlerin birlikte çalışmasını test eder:

1. **Tam Akış Testi**: Açılış → Alış → Satış → Rapor
2. **Çoklu Dönem Testi**: Birden fazla dönem için ardışık işlemler
3. **Performans Testi**: 10,000 ürün ile 5 dakika hedefi

## Performans ve Optimizasyon

### İndeksleme Stratejisi

1. **StokMaliyetHavuzu**: (stkID, girisTarihi, kaynakTip) - FIFO sıralama için kritik
2. **StokEnvanter**: (envanterTarihi, stkID) - Envanter sorguları için
3. **StokMaliyetCikis**: (stkID, hareketTarihi) - Raporlama için
4. **StokMaliyetSorunlu**: (envanterTarihi, stkID) - Sorun takibi için

### Küme Tabanlı İşlemler

Tüm prosedürler cursor kullanmadan, set-based SQL ile yazılmıştır:
- Window functions (SUM OVER, ROW_NUMBER OVER)
- Common Table Expressions (CTE)
- Temporary tables with indexes
- Bulk INSERT operations

### Geçici Tablo Kullanımı

Her prosedür ara sonuçlar için indeksli geçici tablolar kullanır:
- `#stoklar` - Envanter verileri
- `#alislar` - Alış verileri
- `#katman` - Katman hesaplamaları
- `#katmanCum` - Katman kümülatif eksen
- `#satisCum` - Satış kümülatif eksen
- `#cikisDetay` - FIFO kesişim sonuçları

### Performans Hedefleri

- **Açılış Prosedürü**: 10,000 ürün için maksimum 5 dakika
- **Alış Katman**: 1,000 belge için maksimum 1 dakika
- **FIFO Çıkış**: 1 aylık satış için maksimum 2 dakika

## Dağıtım ve Bakım

### Dağıtım Adımları

1. Tabloları oluştur (bkm.StokMaliyetHavuzu, StokEnvanter, StokMaliyetSorunlu, StokMaliyetCikis)
2. İndeksleri oluştur
3. Prosedürleri oluştur (sp_StokMaliyetAcilis, sp_StokMaliyetAlisKatman, sp_StokMaliyetFIFOCikis)
4. İlk açılış stokunu çalıştır
5. Geçmiş alışları yükle
6. Test senaryolarını çalıştır

### Bakım Prosedürleri

1. **Günlük**: Yeni alışları yükle, satışları maliyetlendir
2. **Haftalık**: Sorunlu kayıtları gözden geçir
3. **Aylık**: Performans metriklerini kontrol et, indeksleri yeniden oluştur
4. **Yıllık**: Eski çıkış kayıtlarını arşivle

### Veri Arşivleme

Performansı korumak için eski veriler arşivlenebilir:
- 2 yıldan eski StokMaliyetCikis kayıtları
- Çözülmüş StokMaliyetSorunlu kayıtları
- Tüketilmiş (miktarKalan = 0) eski katmanlar
