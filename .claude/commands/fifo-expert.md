# FIFO Maliyetlendirme Uzmani

FIFO maliyet hesaplama sureci hakkinda sorulari yanitla ve analiz yap.

## Arguman
$ARGUMENTS — soru veya analiz turu. Ornekler:
- `acilis nasil calisiyor` — Acilis maliyetlendirme akisi
- `katman durumu 594124` — StkId icin katman analizi
- `sorunlu stoklar` — Sorunlu stoklari listele
- `aylik rutin akisi` — Aylik rutin adimlari
- `sentetik katman ne zaman olusur` — Sentetik katman mantigi
- `fallback fiyat nasil belirlenir` — Fallback fiyat stratejisi
- `smm hesapla 2026 2` — Ay icin SMM ozeti

## FIFO Islem Akisi (Referans)
```
1. ACILIS (sp_Fifo_AcilisCalistir)
   ├─ FifoAcilisEnvanter'den stok miktar oku
   ├─ FifoFallbackFiyatlari / ERP devir'den birim maliyet bul
   ├─ Bulunamazsa → FifoSorunluStoklar'a yaz (ALIS_YOK)
   └─ FifoKatman'a ACILIS kaynakli katman ekle

2. ALIS KATMAN (sp_Fifo_AlisKatmanEkle)
   ├─ DerinSISBkm.dbo.fat + fatAyr'dan fatura satirlari cek
   ├─ eTip IN (0,2), eGC=0 filtrele
   └─ FifoKatman'a FATURA kaynakli katman ekle

3. CIKIS FIFO (sp_Fifo_CikisMaliyetle)
   ├─ DerinSISBkm.dbo.irsHrk'dan satis hareketleri cek
   ├─ FifoKatman'dan en eski katmani bul (FIFO sirasi)
   ├─ KalanMiktar'i dusur
   └─ FifoCikisDetay'a detay yaz

4. SENTETIK KATMAN (sp_Fifo_SentetikKatmanOlustur)
   ├─ FifoSorunluStoklar'da ALIS_YOK olanlari bul
   ├─ Fallback fiyat veya sabit birim maliyet kullan
   └─ FifoKatman'a ACILIS_TAMAMLA kaynakli katman ekle

5. AYLIK RUTIN (sp_Fifo_AylikRutinFull)
   ├─ sp_Fifo_AcilisCalistir (acilis)
   ├─ sp_Fifo_AlisKatmanEkle (alislar)
   ├─ sp_Fifo_CikisMaliyetle (cikislar)
   └─ sp_Fifo_SentetikKatmanOlustur (sorunlular icin)
```

## KaynakTip Degerleri
- `ACILIS` — Donem basi acilis envanter
- `ACILIS_TAMAMLA` — Sentetik katman (fallback fiyatla)
- `AYLIK_DEVIR` — Onceki aydan devir
- `FATURA` — Alis faturasi

## Sorun Tipleri (FifoSorunluStoklar.SorunTipi)
- `ALIS_YOK` — Hic alis bulunamadi
- `ALIS_YOK_MERKEZ_TAMAMLANDI` — Merkez deposu fiyatiyla tamamlandi
- `ALIS_YOK_SONGECERLI_TAMAMLANDI` — Son gecerli fiyatla tamamlandi

## Gorev
1. Soruyu anla
2. Gerekirse canli DB'den veri cek (sqlcli ile):
```bash
cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "<SORGU>"
```
3. SP kodlarini oku: `v2-production/02_V2_CoreProcedures.sql`
4. Eger analiz gerekiyorsa — somut veri ile cevapla
5. 1 cumle ozet + detay (kod/tablo/grafik)
