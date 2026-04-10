# BKMMaliyet - Veritabanı Şema Dokümanı

## Genel Bakış

BKMMaliyet veritabanı iki ana şemadan oluşur:
- **drn**: DerinSIS snapshot tabloları (kaynak veri kopyaları)
- **dbo**: Maliyet motoru, hesaplar, loglar, raporlar

## DerinSIS Hareket Tipleri (irsTip)

### Kaynak Tablo
```sql
SELECT * FROM DerinSISBkm.dbo.irsTip_vw
```

### Hareket Tipleri Listesi

| tipID | tipAD | Yön | Açıklama |
|-------|-------|-----|----------|
| 0 | Alış | Giriş | Tedarikçiden alış |
| 1 | Satış | Çıkış | Müşteriye satış |
| 2 | Alış İade | Çıkış | Tedarikçiye iade |
| 3 | Satış İade | Giriş | Müşteriden iade |
| 4 | Mağaza Satış | Çıkış | Mağaza satışı |
| 5 | Mağaza Satış İade | Giriş | Mağaza satış iadesi |
| 6 | Hizmet | - | Hizmet hareketi |
| 7 | Gider | Çıkış | Gider çıkışı |
| 8 | Mağaza Mağaza | Transfer | Mağazalar arası transfer |
| 9 | Mağaza Depo | Transfer | Mağaza-depo transfer |
| 10 | Yerel Alım | Giriş | Yerel alım |
| 11 | Depo Depo | Transfer | Depolar arası transfer |
| 12 | Alış Mağaza İade | - | Alış mağaza iadesi |
| 13 | Depo Mağaza | Transfer | Depo-mağaza transfer |
| 14 | İade ve İmha | Çıkış | İade ve imha |
| 15 | Örnek Alımı | Giriş | Örnek alımı |
| 16 | Stok EKLE | Giriş | Manuel stok ekleme |
| 17 | Merkezi Düzeltme | - | Merkezi düzeltme |
| 18 | Mağaza İçi İşlemler | - | Mağaza içi işlemler |
| 86 | Ürün Değişim | - | Ürün değişimi |
| 88 | Diğer Giriş | Giriş | Diğer giriş hareketleri |
| 89 | Diğer Çıkış | Çıkış | Diğer çıkış hareketleri |
| 90 | Ürün SAY | - | Sayım hareketi |
| 91 | Rakipten Ürün Alış | Giriş | Rakipten alış |
| 92 | Boş Paket Çıkışı | Çıkış | Boş paket çıkışı |
| 93 | Müşteriden Bozuk İade | Giriş | Müşteriden bozuk iade |
| 94 | SKT Nedeniyle | Çıkış | SKT nedeniyle çıkış |
| 95 | Dönüşüm | - | Dönüşüm hareketi |
| 96 | Bozuk Ürün | Çıkış | Bozuk ürün çıkışı |
| 97 | Devir | - | Devir hareketi |
| 98 | Şirket İçi Kullanım | Çıkış | Şirket içi kullanım |
| 99 | Sayım | - | Sayım hareketi |
| 100 | POS Satış | Çıkış | POS satışı |
| 101 | POS Satış İade | Giriş | POS satış iadesi |

### Maliyet Hesaplamasında Kullanılan Tipler

**Alış Hareketleri (Giriş - Pozitif Miktar):**
- 0: Alış
- 3: Satış İade
- 5: Mağaza Satış İade
- 10: Yerel Alım
- 15: Örnek Alımı
- 16: Stok EKLE
- 88: Diğer Giriş
- 91: Rakipten Ürün Alış
- 93: Müşteriden Bozuk İade
- 101: POS Satış İade

**Satış Hareketleri (Çıkış - Negatif Miktar):**
- 1: Satış
- 2: Alış İade
- 4: Mağaza Satış
- 7: Gider
- 14: İade ve İmha
- 89: Diğer Çıkış
- 92: Boş Paket Çıkışı
- 94: SKT Nedeniyle
- 96: Bozuk Ürün
- 98: Şirket İçi Kullanım
- 100: POS Satış

**Özel Tipler:**
- 99: Sayım / Devir (ERP devir fiyatları için kullanılır)

## DerinSIS Kaynak Tabloları

### irsHrk (Stok Hareket Detayları)
Tüm stok hareketlerinin detay kaydı

```sql
CREATE TABLE DerinSISBkm.dbo.irsHrk (
    ehID        INT             NOT NULL,  -- Hareket detay ID
    ehstkID     INT             NOT NULL,  -- Stok ID
    ehMekan     INT             NOT NULL,  -- Mekan ID (mağaza/depo)
    ehTrhS      DATETIME        NOT NULL,  -- Hareket tarihi (string format)
    ehAdetN     DECIMAL(18,4)   NOT NULL,  -- Miktar (pozitif=giriş, negatif=çıkış)
    ehTutarN    DECIMAL(18,4)   NOT NULL,  -- Tutar
    ehMlyt      DECIMAL(18,6)   NOT NULL,  -- Maliyet
    ehAltDepo   INT             NOT NULL,  -- Alt depo ID
    hrkID       INT             NOT NULL,  -- Hareket ID (unique)
    ehTip       INT             NOT NULL,  -- Hareket tipi (irsTip_vw'den)
    ehTutarOzl  DECIMAL(18,4)   NOT NULL,  -- Özel tutar
    hrkTarih    DATETIME        NOT NULL,  -- Kayıt tarihi
    CONSTRAINT PK_irsHrk PRIMARY KEY (ehID)
);
```

**Önemli Notlar:**
- `ehTrhS`: Muhasebe evrak tarihi (DATETIME formatında, örn: '2021-05-31 00:00:00')
- `hrkTarih`: Hareketin gerçekleştiği tarih (fiili işlem tarihi) - **BU TARİH KULLANILIR**
- `ehAdetN > 0`: Giriş hareketi (alış, iade, vb.)
- `ehAdetN < 0`: Çıkış hareketi (satış, fire, vb.)
- `ehTip = 99`: Devir/Sayım hareketi (ERP devir fiyatları)
- `hrkID`: Benzersiz hareket numarası

**Kullanım Örnekleri:**
```sql
-- ERP devir fiyatları (31.05.2021 muhasebe tarihi)
SELECT * FROM DerinSISBkm.dbo.irsHrk 
WHERE ehTip = 99 
  AND ehTrhS = '2021-05-31'
  AND ehMekan IN (1, 12, 4477, 4478);

-- Belirli bir ürünün tüm hareketleri (fiili tarih bazında)
SELECT * FROM DerinSISBkm.dbo.irsHrk
WHERE ehstkID = 101
  AND hrkTarih BETWEEN '2021-06-01' AND '2021-12-31'
  AND ehTip <> 99  -- Devir hariç
ORDER BY hrkTarih, hrkID;

-- Alış hareketleri (pozitif miktar, fiili tarih)
SELECT * FROM DerinSISBkm.dbo.irsHrk
WHERE ehAdetN > 0
  AND ehTip NOT IN (99)  -- Devir hariç
  AND hrkTarih >= '2021-06-01';

-- Satış hareketleri (negatif miktar, fiili tarih)
SELECT * FROM DerinSISBkm.dbo.irsHrk
WHERE ehAdetN < 0
  AND ehTip NOT IN (99)  -- Devir hariç
  AND hrkTarih >= '2021-06-01';
```

## drn Şeması (Anlık Görüntü Tabloları)

### drn.GecmisStokMekan
DerinSIS stok bakiyesi anlık görüntüsü
```sql
CREATE TABLE drn.GecmisStokMekan (
    EnvanterTarihi DATE          NOT NULL,  -- Envanter tarihi
    MekanId        INT           NOT NULL,  -- Mağaza/depo ID
    StkId          INT           NOT NULL,  -- Stok ID
    StokMiktar     INT           NOT NULL,  -- Stok miktarı
    CONSTRAINT PK_drn_GecmisStokMekan PRIMARY KEY (EnvanterTarihi, MekanId, StkId)
);
```

### drn.Fat
Fatura başlık anlık görüntüsü (tüm tipler)
```sql
CREATE TABLE drn.Fat (
    FatId     INT            NOT NULL,  -- Fatura ID (DerinSIS eID)
    FatNo     NVARCHAR(50)   NULL,      -- Fatura numarası
    MekanId   INT            NULL,      -- Mağaza/depo ID
    FirmaId   INT            NULL,      -- Firma ID
    Tarih     DATETIME       NOT NULL,  -- Fatura tarihi
    TipId     INT            NULL,      -- Fatura tipi (DerinSIS eTip)
    CONSTRAINT PK_drn_Fat PRIMARY KEY (FatId)
);
```

### drn.FatAyr
Fatura satır anlık görüntüsü (tüm tipler)
```sql
CREATE TABLE drn.FatAyr (
    FatId     INT            NOT NULL,  -- Fatura ID
    SatirNo   INT            NOT NULL,  -- Satır numarası
    StkId     INT            NOT NULL,  -- Stok ID
    Miktar    INT            NOT NULL,  -- Miktar (işlem yönü ile)
    Tutar     DECIMAL(18,4)  NOT NULL,  -- Tutar (işlem yönü ile)
    CONSTRAINT PK_drn_FatAyr PRIMARY KEY (FatId, SatirNo)
);
```

**Maliyet Hesaplamasında Kullanılan Alış Tipleri:**
- 0: Alış
- 2: Alış İade

## dbo Şeması (İşleme Tabloları)

### Loglama Tabloları

#### dbo.MaliyetIslem
Maliyet işlemlerinin üst kaydı
```sql
CREATE TABLE dbo.MaliyetIslem (
    IslemId        UNIQUEIDENTIFIER NOT NULL,  -- Benzersiz işlem ID
    IslemAdi       NVARCHAR(200)    NULL,      -- İşlem adı
    Baslangic      DATETIME2(3)     NOT NULL,  -- Başlangıç zamanı (UTC)
    Bitis          DATETIME2(3)     NULL,      -- Bitiş zamanı (UTC)
    Durum          NVARCHAR(30)     NOT NULL,  -- RUNNING/DONE/ERROR
    Aciklama       NVARCHAR(500)    NULL,      -- Açıklama
    EnvanterTarihi DATE             NULL,      -- İlgili envanter tarihi
    MekanId        INT              NULL,      -- İlgili mağaza ID
    StkId          INT              NULL,      -- İlgili stok ID (opsiyonel)
    CONSTRAINT PK_MaliyetIslem PRIMARY KEY (IslemId)
);
```

#### dbo.MaliyetIslemAdim
İşlem adımlarının detay kaydı
```sql
CREATE TABLE dbo.MaliyetIslemAdim (
    IslemId    UNIQUEIDENTIFIER NOT NULL,  -- Ana işlem ID
    SiraNo     INT              NOT NULL,  -- Adım sıra numarası
    AdimKodu   NVARCHAR(50)     NOT NULL,  -- Adım kodu
    AdimAdi    NVARCHAR(200)    NOT NULL,  -- Adım adı
    Durum      NVARCHAR(30)     NOT NULL,  -- RUNNING/DONE/ERROR
    Mesaj      NVARCHAR(500)    NULL,      -- Detay mesajı
    Baslangic  DATETIME2(3)     NOT NULL,  -- Başlangıç zamanı (UTC)
    Bitis      DATETIME2(3)     NULL,      -- Bitiş zamanı (UTC)
    CONSTRAINT PK_MaliyetIslemAdim PRIMARY KEY (IslemId, SiraNo),
    CONSTRAINT FK_MaliyetIslemAdim_Islem FOREIGN KEY (IslemId) REFERENCES dbo.MaliyetIslem(IslemId)
);
```

### FIFO Tabloları

#### dbo.FifoKatman
FIFO maliyet katmanları
```sql
CREATE TABLE dbo.FifoKatman (
    KatmanId       BIGINT IDENTITY(1,1) NOT NULL,  -- Otomatik katman ID
    EnvanterTarihi DATE          NOT NULL,         -- Envanter tarihi
    MekanId        INT           NOT NULL,         -- Mağaza/depo ID
    StkId          INT           NOT NULL,         -- Stok ID
    GirisTarihi    DATE          NOT NULL,         -- Katman giriş tarihi
    BelgeNo        NVARCHAR(50)  NULL,             -- Kaynak belge numarası
    FirmaId        INT           NULL,             -- Tedarikçi firma ID
    GirisMiktar    INT           NOT NULL,         -- İlk giriş miktarı
    KalanMiktar    INT           NOT NULL,         -- Kalan miktar
    BirimMaliyet   DECIMAL(18,6) NOT NULL,         -- Birim maliyet
    Durum          NVARCHAR(50)  NOT NULL,         -- Katman durumu
    CONSTRAINT PK_FifoKatman PRIMARY KEY (KatmanId)
);
```

**Durum Değerleri:**
- `ACILIS_TEK_KATMAN`: Açılış stoku tek katman
- `AKTIF`: Aktif katman
- `TUKETILDI`: Tamamen tüketilmiş katman

#### dbo.FifoSorunluStoklar
Maliyet bulunamayan sorunlu stoklar
```sql
CREATE TABLE dbo.FifoSorunluStoklar (
    EnvanterTarihi DATE          NOT NULL,  -- Envanter tarihi
    MekanId        INT           NOT NULL,  -- Mağaza/depo ID
    StkId          INT           NOT NULL,  -- Stok ID
    StokMiktar     INT           NOT NULL,  -- Sorunlu stok miktarı
    SorunTipi      NVARCHAR(50)  NOT NULL,  -- Sorun tipi
    Aciklama       NVARCHAR(400) NULL,      -- Sorun açıklaması
    CONSTRAINT PK_FifoSorunlu PRIMARY KEY (EnvanterTarihi, MekanId, StkId, SorunTipi)
);
```

**Sorun Tipleri:**
- `MALIYET_YOK`: Son alış maliyeti bulunamadı

### Ortalama Maliyet Tabloları

#### dbo.OrtalamaAylikMaliyet
Aylık ortalama maliyet hesaplamaları
```sql
CREATE TABLE dbo.OrtalamaAylikMaliyet (
    YilAy              INT           NOT NULL,  -- YYYYMM formatında (202501)
    MekanId            INT           NOT NULL,  -- Mağaza/depo ID
    StkId              INT           NOT NULL,  -- Stok ID
    GirisMiktar        INT           NOT NULL,  -- Dönem giriş miktarı
    GirisTutar         DECIMAL(18,4) NOT NULL,  -- Dönem giriş tutarı
    CikisMiktar        INT           NOT NULL,  -- Dönem çıkış miktarı
    AySonuMiktar       INT           NOT NULL,  -- Ay sonu stok miktarı
    AySonuBirimMaliyet DECIMAL(18,6) NOT NULL,  -- Ay sonu birim maliyet
    AySonuTutar        DECIMAL(18,4) NOT NULL,  -- Ay sonu toplam tutar
    CONSTRAINT PK_OrtalamaAylik PRIMARY KEY (YilAy, MekanId, StkId)
);
```

## İndeksler

### drn Şeması İndeksleri
```sql
-- Fat tablosu
CREATE INDEX IX_drn_Fat_Tarih ON drn.Fat(Tarih) INCLUDE(MekanId, FirmaId, TipId);

-- FatAyr tablosu  
CREATE INDEX IX_drn_FatAyr_Stk ON drn.FatAyr(StkId) INCLUDE(FatId, Miktar, Tutar);
```

### dbo Şeması İndeksleri
```sql
-- MaliyetIslemAdim tablosu
CREATE INDEX IX_MaliyetIslemAdim_AdimKodu ON dbo.MaliyetIslemAdim(AdimKodu) INCLUDE(Durum, Baslangic, Bitis);

-- FifoKatman tablosu
CREATE INDEX IX_FifoKatman_EnvMekStk ON dbo.FifoKatman(EnvanterTarihi, MekanId, StkId) INCLUDE(KalanMiktar, BirimMaliyet);
```

## View'lar

### dbo.vw_Fifo_AySonuBirimMaliyet
FIFO katmanlarından türetilen ay sonu birim maliyet raporu
```sql
CREATE VIEW dbo.vw_Fifo_AySonuBirimMaliyet AS
SELECT
    EnvanterTarihi,
    MekanId,
    StkId,
    SUM(KalanMiktar) AS StokMiktar,
    CASE WHEN SUM(KalanMiktar)=0 THEN 0
         ELSE CAST(SUM(KalanMiktar * BirimMaliyet) / SUM(KalanMiktar) AS DECIMAL(18,6))
    END AS BirimMaliyet,
    CAST(SUM(KalanMiktar * BirimMaliyet) AS DECIMAL(18,4)) AS Tutar
FROM dbo.FifoKatman
GROUP BY EnvanterTarihi, MekanId, StkId;
```

## Stored Procedure'lar

### Anlık Görüntü SP'leri
- `drn.sp_StokMekanAnlikGoruntuOlustur`: Stok anlık görüntüsü oluşturur
- `drn.sp_FaturaAnlikGoruntuOlustur`: Fatura anlık görüntüsü oluşturur (tüm tipler)

### FIFO SP'leri  
- `dbo.sp_Fifo_AcilisStoklariniMaliyetlendir`: Açılış stoklarını maliyetlendirir

### Ortalama SP'leri
- `dbo.sp_Ortalama_AySonuMaliyetHesapla`: Ay sonu ortalama maliyet hesaplar (iskelet)

### Yardımcı SP'ler
- `dbo.sp_MaliyetAdimYaz`: İşlem adımı loglama

## Veri Akışı

1. **Anlık Görüntü Alma**: DerinSIS'ten drn şemasına veri kopyalama (tüm fatura tipleri)
2. **FIFO İşleme**: drn verilerinden FIFO katmanları oluşturma (sadece alış tipleri: 0,2,8,9)
3. **Ortalama Hesaplama**: Dönemsel ortalama maliyet hesaplama
4. **Raporlama**: View'lar üzerinden rapor alma

## Notlar

- Tüm tarih alanları DATE tipinde (zaman bilgisi yok)
- Loglama zamanları DATETIME2(3) UTC formatında
- Miktar alanları INT, maliyet alanları DECIMAL(18,6), tutar alanları DECIMAL(18,4)
- FIFO ve Ortalama maliyet hesaplamaları bilinçli olarak ayrı tutulmuş
- Maliyet hesaplamalarında sadece alış tipleri kullanılır: 0 (Alış), 2 (Alış İade)
- Fatura verileri tüm tipler için saklanır, maliyet hesaplamasında filtrelenir
---

## V2 DBO Additions (2026-02)

This section documents the V2 production schema under `v2-production/`.

### New / Updated Tables

- `dbo.FifoKatman`
  - Added columns: `KaynakTip NVARCHAR(20) NOT NULL`, `BelgeTarihi DATE NULL`
  - Core columns: `KatmanId, StkId, GirisTarihi, BelgeNo, FirmaId, GirisMiktar, KalanMiktar, BirimMaliyet, Durum`

- `dbo.FifoAcilisEnvanter` (new)
  - Columns: `EnvanterTarihi, MekanId, StkId, StokMiktar, KayitTarihi`
  - PK: `(EnvanterTarihi, MekanId, StkId)`

- `dbo.FifoSorunluStoklar`
  - PK includes `MekanId`: `(EnvanterTarihi, MekanId, StkId, SorunTipi)`

- `dbo.FifoFallbackFiyatlari` (new)
  - Columns: `StkId, SatinalmaSarti, MekanId, BirimMaliyet, Miktar, ToplamTutar, Aciklama, KayitTarihi`
  - PK: `(StkId, SatinalmaSarti, MekanId)`

- `dbo.FifoCikisDetay` (new)
  - Columns: `CikisId, StkId, HareketTarihi, HareketTipi, MekanId, BelgeNo, KatmanId, KatmanTarihi, KatmanBelgeNo, Miktar, BirimMaliyet`
  - Computed: `CikisTutar AS (Miktar * BirimMaliyet) PERSISTED`

- `dbo.MaliyetIslem`
  - Process header table used by V2 procedures

- `dbo.MaliyetIslemAdim`
  - Step-level process log table used by V2 procedures

### V2 Procedures

- `dbo.sp_MaliyetAdimYaz`
- `dbo.sp_Fifo_AcilisMaliyetlendir`
- `dbo.sp_Fifo_AlisKatmanEkle`
- `dbo.sp_Fifo_CikisMaliyetle`
- `dbo.sp_Fifo_Calistir`
- `dbo.sp_Fifo_AcilisCalistir`
- `dbo.sp_Fifo_AylikCalistir`
- `dbo.sp_Fifo_AylikRutin`
- `dbo.sp_Fifo_SentetikKatmanOlustur`
- `dbo.sp_Fifo_AylikRutinFull`

### V2 Views

- `dbo.vw_Fifo_GunlukSMM`
- `dbo.vw_Fifo_UrunBazliSMM`
- `dbo.vw_Fifo_KatmanDurumu`
- `dbo.vw_Fifo_SorunluStoklar`
- `dbo.vw_Fifo_AySonuBirimMaliyet`

### Deploy Order

1. `v2-production/01_V2_Tables.sql`
2. `v2-production/02_V2_CoreProcedures.sql`
3. `v2-production/03_V2_Views.sql`
4. `v2-production/04_V2_SentetikFallback.sql`
5. `v2-production/05_V2_AylikRutinFull.sql`

Or run all with:

- `v2-production/00_V2_Master_Deploy.sql`
