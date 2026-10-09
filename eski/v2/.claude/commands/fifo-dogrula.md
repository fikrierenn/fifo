# FIFO Doğrulama (Reconciliation)

FIFO çıktısını otomatik denetle: katman tüketim mutabakatı, kalan sınırları, birim maliyet eşleşmesi, sorunlu stok özeti, mekan kapsam tutarsızlıkları. Salt-okunur — veriyi DEĞİŞTİRMEZ.

## Argüman
`$ARGUMENTS` — opsiyonel kapsam:
- (boş) — tüm ürünler, tüm dönemler
- `urun 594124` — sadece StkId 594124
- `donem 2026 2` — sadece 2026 Şubat hareketleri (HareketTarihi filtresi)

## Çalışma Ortamı
- **LOKAL DB** kullan (canlı 192.168.40.201 sıkıntılı). sqlcli bağlantısı `D:/Dev/fifo/sqlcli.json`.
- sqlcli ile çalıştır: `cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "<SQL>"`
- DerinSISBkm cross-DB gerektiren kontroller (C8) lokal'de yoksa ATLA, raporda "atlandı (DerinSISBkm yok)" yaz.

## Kontroller (her biri ayrı sorgu — salt SELECT)
Aşağıdaki `@stk` / dönem filtresini argümana göre uygula. Filtre yoksa `@stk` koşullarını çıkar.

### C1 — Katman tüketim mutabakatı (EN KRİTİK)
Her katmanın tükettiği = çıkış detayına yazılan olmalı: `GirisMiktar - KalanMiktar = SUM(cikis.Miktar)`.
```sql
SELECT TOP 50 k.KatmanId, k.StkId, k.KaynakTip,
       k.GirisMiktar, k.KalanMiktar,
       (k.GirisMiktar - k.KalanMiktar) AS beklenenCikis,
       ISNULL(c.toplamCikis, 0) AS gercekCikis,
       (k.GirisMiktar - k.KalanMiktar) - ISNULL(c.toplamCikis, 0) AS fark
FROM dbo.FifoKatman k
LEFT JOIN (SELECT KatmanId, SUM(Miktar) AS toplamCikis
           FROM dbo.FifoCikisDetay GROUP BY KatmanId) c ON c.KatmanId = k.KatmanId
WHERE ABS((k.GirisMiktar - k.KalanMiktar) - ISNULL(c.toplamCikis, 0)) > 0.01
ORDER BY ABS((k.GirisMiktar - k.KalanMiktar) - ISNULL(c.toplamCikis, 0)) DESC;
```

### C2 — Kalan miktar sınırları
`0 <= KalanMiktar <= GirisMiktar` (CHECK olmalı, yine de kontrol).
```sql
SELECT KatmanId, StkId, KaynakTip, GirisMiktar, KalanMiktar
FROM dbo.FifoKatman
WHERE KalanMiktar < 0 OR KalanMiktar > GirisMiktar + 0.01;
```

### C3 — Çıkış birim maliyet = katman birim maliyet
```sql
SELECT TOP 50 c.CikisId, c.StkId, c.KatmanId,
       c.BirimMaliyet AS cikisBM, k.BirimMaliyet AS katmanBM
FROM dbo.FifoCikisDetay c
JOIN dbo.FifoKatman k ON k.KatmanId = c.KatmanId
WHERE ABS(c.BirimMaliyet - k.BirimMaliyet) > 0.000001;
```

### C4 — Orphan çıkış (katmansız)
```sql
SELECT TOP 50 c.CikisId, c.StkId, c.KatmanId
FROM dbo.FifoCikisDetay c
WHERE NOT EXISTS (SELECT 1 FROM dbo.FifoKatman k WHERE k.KatmanId = c.KatmanId);
```

### C5 — STOK_YETERSIZ özeti
```sql
SELECT EnvanterTarihi, COUNT(DISTINCT StkId) AS urunSayisi,
       SUM(StokMiktar) AS toplamEksikMiktar
FROM dbo.FifoSorunluStoklar
WHERE SorunTipi = 'STOK_YETERSIZ'
GROUP BY EnvanterTarihi ORDER BY EnvanterTarihi DESC;
```

### C6 — Sıfır maliyetli aktif katman (FIYAT_YOK riski)
```sql
SELECT Durum, COUNT(*) AS katmanSayisi, SUM(KalanMiktar) AS aktifMiktar
FROM dbo.FifoKatman
WHERE KalanMiktar > 0 AND BirimMaliyet = 0
GROUP BY Durum;
```

### C7 — Mekan-12 açılış boşluğu (V2 açılış bulgusu)
V2 açılış mekan 12'yi snapshot'a yazmaz; çıkış mekan-12 satışı yapar. Boşluk varsa flag.
```sql
SELECT
  (SELECT COUNT(*) FROM dbo.FifoAcilisEnvanter WHERE MekanId = 12) AS acilis_mekan12_satir,
  (SELECT COUNT(*) FROM dbo.FifoCikisDetay     WHERE MekanId = 12) AS cikis_mekan12_satir,
  (SELECT ISNULL(SUM(Miktar),0) FROM dbo.FifoCikisDetay WHERE MekanId = 12) AS cikis_mekan12_miktar;
```
`acilis_mekan12_satir = 0` ve `cikis_mekan12_satir > 0` ise → mekan-12 stoku açılışsız tüketilmiş (uyumsuzluk).

### C8 — ERP stok mutabakatı (DerinSISBkm gerektirir — lokal'de yoksa ATLA)
FIFO eldeki stok (SUM KalanMiktar) vs ERP irsHrk kümülatif (4 mekan, altDepo=0).
```sql
SELECT TOP 50 f.StkId, f.fifoKalan, e.erpStok, f.fifoKalan - e.erpStok AS fark
FROM (SELECT StkId, SUM(KalanMiktar) AS fifoKalan FROM dbo.FifoKatman GROUP BY StkId) f
JOIN (SELECT ehStkId AS StkId, SUM(CONVERT(DECIMAL(18,4),ehAdetN)) AS erpStok
      FROM DerinSISBkm.dbo.irsHrk
      WHERE ehAltDepo = 0 AND ehMekan IN (1,12,4477,4478)
      GROUP BY ehStkId) e ON e.StkId = f.StkId
WHERE ABS(f.fifoKalan - e.erpStok) > 0.01
ORDER BY ABS(f.fifoKalan - e.erpStok) DESC;
```

## Çıktı Formatı
Her kontrol için tek satır: **✅ GEÇTİ** (0 satır) / **⚠️ UYARI** (sınır durum) / **❌ HATA** (mutabakat bozuk), bulunan satır sayısı ve ilk birkaç örnek.

```
FIFO Doğrulama Raporu — <kapsam> — <tarih>
─────────────────────────────────────────
C1 Katman tüketim mutabakatı   ❌ HATA   12 katman uyumsuz (max fark 340.5)
C2 Kalan sınırları             ✅ GEÇTİ
C3 Birim maliyet eşleşme       ✅ GEÇTİ
C4 Orphan çıkış                ✅ GEÇTİ
C5 STOK_YETERSIZ               ⚠️ 47 ürün / 2026-02
C6 Sıfır maliyet aktif katman  ⚠️ 8 katman (HAYALI_FIYAT_YOK)
C7 Mekan-12 açılış boşluğu     ❌ açılış=0, çıkış=15.230 adet
C8 ERP stok mutabakatı         (atlandı — DerinSISBkm yok)
─────────────────────────────────────────
Özet: 2 HATA, 2 UYARI → düzeltme gerekli
```

## Kurallar
- `SELECT *` yasak, `NOLOCK` yasak, salt SELECT (INSERT/UPDATE/DELETE YOK).
- Kolon adları: FifoCikisDetay → CikisId, StkId, HareketTarihi, HareketTipi, MekanId, KatmanId, Miktar, BirimMaliyet, CikisTutar (computed), SatisTutar. FifoKatman → KatmanId, StkId, GirisTarihi, KaynakTip, GirisMiktar, KalanMiktar, BirimMaliyet, Durum.
- Bulgu çıkarsa kök neden `memory/fifo_logic_findings.md`'de — oradaki tabloyla eşleştir.
- Rapor sonunda her ❌/⚠️ için 1 satır öneri ver.
