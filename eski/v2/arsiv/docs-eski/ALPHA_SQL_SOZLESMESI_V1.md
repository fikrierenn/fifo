# Alpha SQL Sozlesmesi v1

## Amac

- `31.12.2025` tarihi icin tum urunlerde baslangic FIFO maliyet havuzu olusturmak.
- Sonraki aylarda gercek girisleri havuza ekleyip satislari FIFO ile maliyetlemek.
- Maliyetsiz urun/satis birakmamak; gerekiyorsa sentetik/hayali giris katmani ile fiyatlamak.
- Tum fallback ve sentetik katmanlari denetlenebilir sekilde isaretlemek.

## Temel Ilkeler

- Havuz yasayan yapidir: `Acilis + Aylik Girisler - FIFO Tuketim`.
- Oncelik gercek veridir; fallback sadece zorunlu durumda kullanilir.
- "Maliyetsiz birakma" yerine "isaretli sentetik maliyet" tercih edilir.
- Alpha asamasinda dogruluk ve izlenebilirlik, performanstan once gelir.

## Ana Tablolar (Source of Truth)

- `bkm.fifo_StokMaliyetHavuzu`: FIFO katmanlari ve kalan miktarlar
- `bkm.fifo_StokMaliyetCikis`: FIFO maliyetlenmis cikis/satislar
- `bkm.fifo_StokMaliyetSorunlu`: sorun/fallback kayitlari
- `bkm.fifo_ErpDevirFiyatlari`: satinalma sarti bazli fiyat kaynagi
- `bkm.fifo_StokEnvanter`: acilis snapshot referansi
- `bkm.fifo_Calistirma`, `bkm.fifo_CalistirmaAdim`: islem takibi

## Katman Tipleri (Mutabik Mantik)

- `ACILIS`: gercek gecmis alislardan turetilmis acilis katmani
- `ALIS`: aylik gercek alis katmani
- `ACILIS_TAMAMLA`: acilista eksik kalan miktari tamamlayan katman
- `AYLIK_DEVIR`: acilis fallback'i icin gecmis ay devir mantigiyla uretilen katman
- `SENTETIK_ALIS` (onerilen): aylik surecte maliyet olusmayan urun icin hayali giris katmani
- `SABIT_FIYAT_TAMAMLAMA` (onerilen): son care sabit fiyat fallback katmani

Not:
- Mevcut kodda `ACILIS_TAMAMLA` ve `AYLIK_DEVIR` kullanimi vardir.
- `SENTETIK_ALIS` ve `SABIT_FIYAT_TAMAMLAMA` isimleri alpha cleanup asamasinda standardize edilecektir.

## Fiyatlama Oncelik Sirasi (Acilis + Aylik Ortak)

1. Gercek alis verisi (`fat` + `fatAyr`)
2. Son gecerli gercek fiyat (uygun fonksiyon/kaynak)
3. Satinalma sarti bazli fiyat (`bkm.fifo_ErpDevirFiyatlari`)
4. Sentetik/hayali evrak fiyati (sart bazli)
5. Tek seferlik sabit fiyat (son care fallback)

## Acilis Akisi (31.12.2025)

1. Envanter snapshot al (`irsHrk` tabanli)
2. Gecmis alislari topla
3. Ters FIFO ile acilis katmanlarini uret (`ACILIS`)
4. Eksik miktarlari fallback zinciri ile tamamla (`ACILIS_TAMAMLA` / `AYLIK_DEVIR` / sabit fiyat)
5. Sorun/fallback kayitlarini `bkm.fifo_StokMaliyetSorunlu` tablosuna yaz
6. Sonuc: Her urun icin mumkun oldugunca maliyetli acilis havuzu

## Aylik Akis (Her Ay)

1. Ay ici gercek alislari `ALIS` katmani olarak havuza ekle
2. Satislari FIFO ile maliyetle (`bkm.fifo_StokMaliyetCikis`)
3. Gerekirse maliyetsiz kalan urunler icin sentetik giris katmani olustur (`SENTETIK_ALIS`)
4. FIFO cikisi yeniden/tekrar hesapla (alpha asamasinda kabul edilebilir)
5. Sorun/fallback kayitlarini logla
6. Kontrol view'lari ile dogrula

## Maliyetsiz Urun Politikasi (Net Karar)

- Maliyetsiz urun/satis birakilmayacak.
- Fallback ile fiyatlanan her kayit:
- katman tipinden anlasilacak
- sorun/audit tablosuna iz birakacak
- raporlarda ayristirilabilecek

## Alpha Kabul Kriterleri

- Acilis havuzu `31.12.2025` icin uretilebiliyor
- Aylik rutin calisiyor (`ALIS + FIFO CIKIS`)
- `bkm.fifo_StokMaliyetCikis` beklenen urunlerde bos kalmiyor
- Fallback kullanilan kayitlar gorunur
- `bkm.vw_KatmanTuketimRaporu` ile temel tutarlilik kontrolu yapilabiliyor
- Kritik hatalarda islem rollback oluyor

## Prosedur Sorumluluklari (Mevcut Kodla Eslesme)

- `bkm.sp_fifo_StokMaliyetAcilis`: acilis havuzu uretimi + fallback tamamlama
- `bkm.sp_fifo_StokMaliyetAlisKatman`: aylik gercek alis katmanlari
- `bkm.sp_fifo_StokMaliyetFIFOCikis`: FIFO satis maliyetleme
- `bkm.sp_fifo_AylikRutin`: aylik wrapper
- `bkm.sp_fifo_AcilisCalistir`: acilis orkestrasyon wrapper (onerilen)
- `bkm.sp_fifo_AylikCalistir`: aylik alis+cikis orkestrasyon wrapper (onerilen)
- `bkm.sp_fifo_AylikRutinAlpha`: aylik + sentetik fallback wrapper (onerilen alpha akis)
- `bkm.sp_fifo_StokMaliyetCalistir`: legacy/uyumluluk orkestrasyon wrapper

## Acik Kararlar / Sonraki Teknik Netlestirmeler

- `Mekan bagimsiz maliyet` yaklasimi kalici mi, gecici mi...
- `SENTETIK_ALIS` ve `SABIT_FIYAT_TAMAMLAMA` icin kesin `kaynakTip`/`durum` standardi
- Aylik sentetik katman ekleme adiminin hangi prosedure alinacagi
- Raporlarda sentetik maliyet etkisinin nasil gosterilecegi


