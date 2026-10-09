# FIFO Doğrulama Defteri

> Tüm yazılan SQL kodunun arşiv envanteri + parça-parça mantık doğrulaması.
> Kaynak: `v2-production/` (deployed/authoritative). Eski referans: `yedek/`, `sql-alpha/`, kök `*.sql`.
> Durum: ✅ doğrulandı (kod okundu, mantık OK) · ⚠️ doğrulandı + bulgu · 🔲 bekliyor.
> Çalıştırma doğrulaması: LOKAL DB'de (canlı artık kullanılmayacak). Demo: 100 çok-satan ürün, devir 2025-12-31, yıl 2026.

## DOĞRULANMIŞ İŞ KURALI (kullanıcı, 2026-06-02)
**Maliyet mekan-bağımsız TEK ortak havuz; satışlar mekan-bazlı, ortak maliyetle maliyetlenir; karlılık mekan bazında.**
→ FIFO çıkış `PARTITION BY StkId` (mekan yok) = **tasarım gereği DOĞRU**. Havuz tüm mekanları (1,12,4477,4478)+altDepo=0 kapsamalı.
→ **BUG: 14_V2 açılış mekan-12 hariç** (havuz eksik, 12=en büyük stok 6.29M) ve **stokSonAltDepo_vw güncel stok kullanıyor, devir 2025-12-31 itibariyle değil**. FIX: mekan `IN(1,12,4477,4478)` + irsHrk as-of tarih.
→ **BUG: Ortalama (12) ay-sonu stok mekan/altDepo filtresiz.** FIX: 4-mekan+altDepo=0.

## Arşiv Envanteri (v2-production — 20 dosya)

| # | Dosya | Obje(ler) | Tip | Durum |
|---|-------|-----------|-----|-------|
| 01 | 01_V2_Tables.sql | FifoKatman, FifoAcilisEnvanter, FifoSorunluStoklar, FifoFallbackFiyatlari, FifoCikisDetay, MaliyetIslem, MaliyetIslemAdim | TABLE×7 | ✅ |
| 02 | 02_V2_CoreProcedures.sql | sp_Fifo_AcilisMaliyetlendir, sp_Fifo_AlisKatmanEkle, sp_Fifo_CikisMaliyetle, sp_MaliyetAdimYaz, sp_Fifo_Calistir, sp_Fifo_AcilisCalistir, sp_Fifo_AylikCalistir, sp_Fifo_AylikRutin | PROC×8 | ✅ |
| 03 | 03_V2_Views.sql | vw_Fifo_GunlukSMM, vw_Fifo_UrunBazliSMM, vw_Fifo_KatmanDurumu, vw_Fifo_SorunluStoklar, vw_Fifo_AySonuBirimMaliyet | VIEW×5 | ⚠️ |
| 04 | 04_V2_SentetikFallback.sql | sp_Fifo_SentetikKatmanOlustur | PROC | ✅ |
| 05 | 05_V2_AylikRutinFull.sql | sp_Fifo_AylikRutinFull | PROC | ✅ |
| 07 | 07_V2_HareketliUrunListesi.sql | sp_Fifo_HareketliUrunListesi | PROC | ✅ (16 ezer — ÖLÜ) |
| 09 | 09_V2_BatchOrchestration.sql | StkIdListType, FifoBatchRun, FifoBatchDetay, FifoBatchHata, sp_Fifo_BatchRunBaslat, sp_Fifo_BatchRunBitir, sp_Fifo_AylikCalistirBatch, vw_FifoBatchRunOzet | TYPE+TABLE×3+PROC×3+VIEW | ✅ |
| 12 | 12_V2_OrtalamaAylikMaliyet.sql | OrtalamaAylikMaliyet, sp_Ortalama_AylikHesapla | TABLE+PROC | ⚠️ |
| 13 | 13_V2_EksikViewlar.sql | vw_Ortalama_AySonuBirimMaliyet, vw_MaliyetKarsilastirma | VIEW×2 | ❌ |
| 14 | 14_V2_AcilisOptimize.sql | sp_Fifo_AcilisCalistir_V2 | PROC | ⚠️ |
| 15 | 15_V2_DevreDisiUrunler.sql | FifoDevreDisiUrunler, vw_Fifo_DevreDisiUrunler | TABLE+VIEW | ✅ |
| 16 | 16_V2_DevreDisiFiltre.sql | sp_Fifo_HareketliUrunListesi (re-create, devre dışı filtre) | PROC | ⚠️ |
| 17 | 17_V2_ManuelMaliyet.sql | FifoManuelMaliyet, vw_Fifo_ManuelMaliyet | TABLE+VIEW | ⚠️ ÖLÜ |
| 18 | 18_V2_DonemKontrol.sql | FifoDonemSnapshot, FifoDonemSnapshotDetay, sp_Fifo_DonemKontrol, sp_Fifo_DonemSnapshotAl, vw_Fifo_DonemDegisim | TABLE×2+PROC×2+VIEW | ✅ |
| 19 | 19_V2_CikisSatisTutar.sql | FifoCikisDetay.SatisTutar kolon + backfill | ALTER | ⚠️ |

> Çalıştırma/yardımcı dosyalar (obje üretmez): 00 Master_Deploy, 06 Verification, 08 IlkFaturaDogrulama, 10 Benchmark, 11 SmokeTest.

---

## Doğrulama Notları (parça parça)

### 02 — Core Procedures ✅
- **sp_Fifo_CikisMaliyetle** (FIFO çekirdek): set-based interval-intersection, cursor yok. Katman + satış kümülatif → `cikisMiktar = MIN(layerEnd,satisEnd) - MAX(layerStart,satisStart)`. FIFO sırası: `fifoSiraTarihi, fifoSiraBelgeNoNum, girisBelgeNo, KatmanId`. **PARTITION BY StkId (mekan YOK) → mekan-agnostik global tüketim.** Rerun-safe: eski dönem çıkışı önce KalanMiktar'a geri eklenir. KaynakTip filtresi: `ACILIS,ACILIS_TAMAMLA,ALIS,AYLIK_DEVIR,SENTETIK_ALIS`.
  - ⚠️ **IADE**: gün+mekan+stk netlenir; HareketTipi sadece işaret etiketi (`<0 SATIS else IADE`). IADE de KalanMiktar düşürür. Günler-arası iade over-consume riski.
  - 🔎 **DOĞRULA (lokal)**: C1 katman tüketim mutabakatı, C3 birim maliyet eşleşme.
- **sp_Fifo_AcilisMaliyetlendir** (orijinal açılış): envanter `irsHrk` kümülatif `ehMekan IN (1,12,4477,4478)` altDepo=0. Ters FIFO (en yeni alıştan geriye). 5 kademeli fallback: son alış → merkez(12) → son geçerli fiyat → aylık devir → sabit. **Mekan 12 envantere DAHİL.**
- **sp_Fifo_AlisKatmanEkle**: fat+fatAyr, eTip IN(0,2), eGC işaret. `Miktar<=0 OR netTutar<=0 OR BM<=0` satırları havuza yazılmaz. Tarih aralığı ALIS katmanı silinip yeniden yazılır (idempotent).
- **sp_Fifo_Calistir / AcilisCalistir / AylikCalistir / AylikRutin**: orkestratör wrapper'lar. AylikRutin = alış+çıkış (açılış yok).
- **sp_MaliyetAdimYaz**: log upsert + parent MaliyetIslem otomatik. Üst durum adımlardan türetilir (HATA>CALISIYOR>TAMAMLANDI).

### 04 — Sentetik Fallback ✅
- **sp_Fifo_SentetikKatmanOlustur**: STOK_YETERSIZ → SENTETIK_ALIS katman. Fiyat: FifoFallbackFiyatlari(şart) → sabit fallback. Durum: HAYALI_SART/HAYALI_SABIT/HAYALI_FIYAT_YOK. DryRun destekli. Fiyatsız (`BM<=0`) katman YAZILMAZ, SENTETIK_FIYAT_YOK loglanır. **FIFO çıkışı otomatik yeniden hesaplamaz** — ayrı çağrı gerekir.

### 12 — Ortalama ⚠️
- **sp_Ortalama_AylikHesapla**: `(AyBasiTutar+GirisTutar)/(AyBasiMiktar+GirisMiktar)`. Ay başı = önceki ay AySonu, yoksa FIFO açılış katmanı ağırlıklı ort. Giriş: fat+fatAyr eTip(0,2).
  - ⚠️ **ADIM 3 ay sonu stok (satır 186-190): `irsHrk` mekan filtresi YOK, altDepo filtresi YOK** → tüm depo+altdepo sayar. FIFO 4 mekan+altDepo=0. Karşılaştırma (vw_MaliyetKarsilastirma) elma-armut.
  - 🔎 **DOĞRULA (lokal)**: C8 kapsam farkı.

### 14 — Açılış V2 (Hangfire kullanır) ⚠️
- **sp_Fifo_AcilisCalistir_V2**: 3 faz (lock bırak), EOMONTH pre-aggregate + window SUM (55x), bulk TVF.
  - ⚠️ **Envanter `stokSonAltDepo_vw.stok`, `ehMekan IN (1,4477,4478)` — MEKAN 12 HARİÇ** (12 yalnız merkez-tamamlama). Orijinal 02 ise irsHrk + mekan 12 dahil. Alış `irs+irsAyr+fatAyr`, eTip genişletilmiş `(2,0,10,3,6,102,103)`, eMekan IN(1,4477,4478).
  - ⚠️ **Çıkış (02) mekan-12 satışı yapar ama V2 açılış mekan-12 katmanı yazmaz → mekan-12 STOK_YETERSIZ/uyumsuzluk garantisi.**
  - 🔎 **DOĞRULA (lokal)**: C7 mekan-12 boşluğu.

### KATMAN YAŞAM DÖNGÜSÜ — koddan doğrulanmış (2026-06-02)
Şüpheyle: memory `schema.md` ve eski `/fifo-expert` skill'i **YANLIŞ** KaynakTip içeriyordu (`FATURA` — kodda HİÇ YOK). Grep ile tüm INSERT literal'leri tarandı, gerçek set:
- **KaynakTip (5):** `ACILIS` (02/14, Durum NORMAL), `ACILIS_TAMAMLA` (02/14, Durum TAMAMLAMA/MERKEZ_TAMAMLAMA/SART_TAMAMLAMA), `ALIS` (02 AlisKatmanEkle [02:772], Durum NORMAL), `AYLIK_DEVIR` (02/14, Durum AYLIK_DEVIR/FIYAT_YOK/SABIT_FIYAT_TAMAMLAMA), `SENTETIK_ALIS` (04, Durum HAYALI_SART/HAYALI_SABIT/HAYALI_FIYAT_YOK).
- **`FATURA` = hayalet** (eski skill + schema.md hatası → ikisi de düzeltildi).
- Çıkış tüketim filtresi [02:865] tam bu 5'i içerir.
- **GirisMiktar sabit, KalanMiktar çıkışla düşer**, CHECK `0<=Kalan<=Giris` [01:39]. Tüketim mekan-agnostik (`PARTITION BY StkId` [02:900]).
- ✅ `/fifo-expert` skill'i koddan doğrulanmış halde yeniden yazıldı + `memory/schema.md` düzeltildi.

### 09 — Batch Orchestration ✅
- **sp_Fifo_AylikCalistirBatch**: TVP (StkIdListType) alır, cursor ile ürün başına `sp_Fifo_AylikCalistir` çağırır. Ürün hatası batch'i durdurmaz → `FifoBatchHata`'ya yazar (izole TRY/CATCH per ürün) — silent-failure değil, kasıtlı izolasyon. Batch sonu Durum: 0 hata→TAMAMLANDI, else KISMEN_HATA.
- **sp_Fifo_BatchRunBaslat**: aynı dönem CALISIYOR run varsa RAISERROR (çakışma koruması). **sp_Fifo_BatchRunBitir**: TamamlananBatch = COUNT(Durum='TAMAMLANDI').
  - ⚠️ Batch SP'sinde dış BEGIN TRAN yok — her ürün kendi SP transaction'ında. Bir ürün rollback'i diğerlerini etkilemez (istenen). Ama batch-seviye atomiklik yok (kabul edilebilir tasarım).
  - ⚠️ `@IslemId = @RunId` geçiliyor: batch log ile MaliyetIslem log aynı GUID'i paylaşıyor — kasıtlı mı doğrulanmalı.

### 05 / 13 / 15 / 16 / 17 (2026-06-02, koddan)
- **05 sp_Fifo_AylikRutinFull** ✅: AylikCalistir → sentetik dry-run → gerekirse sentetik + çıkış re-run. INSERT-EXEC kolonları 04 DryRun çıktısıyla eşleşiyor ✅. ⚠️ İç içe transaction: iç SP (CikisMaliyetle) kendi BEGIN TRAN/ROLLBACK'ine sahip → hata iç ROLLBACK dış transaction'ı da geri alır; CATCH `THROW` yerine `RAISERROR('...%s')` → orijinal hata no/satır kaybolur. Düşük.
- **07** ✅ ÖLÜ: 16 aynı SP'yi yeniden tanımlıyor (sonra deploy) → 07 etkisiz.
- **13 vw_MaliyetKarsilastirma** ❌ **CORRECTNESS BUG**: `LEFT JOIN vw_Fifo_AySonuBirimMaliyet f ON f.StkId=o.StkId` — YilAy/tarih hizalaması YOK. `vw_Fifo_AySonuBirimMaliyet` (GirisTarihi,StkId) grupladığı için StkId başına N satır → **kartezyen çarpım**: her Ortalama satırı tüm FIFO katman-tarihi satırlarıyla eşleşir, Fifo_Miktar/Tutar yanlış/çoğaltılmış. Yorum "YilAy türetilir" diyor, kod yapmıyor. + mekan kapsam farkı (ortalama filtresiz). FIX: FIFO tarafı StkId'ye toplanmalı + YilAy hizalanmalı.
- **vw_Ortalama_AySonuBirimMaliyet** ✅ düz passthrough.
- **15 FifoDevreDisiUrunler** ✅: tablo+view, 16'da NOT EXISTS ile tüketiliyor.
- **16 devre-dışı filtre** ⚠️ GAP: filtre yalnız HareketliUrunListesi + app'te. **Açılış SQL'inde (02/14) devre-dışı filtre YOK** (kod yorumu "App tarafında" diyor). Açılış job/direkt çağrılırsa devre-dışı ürün dahil olur. Batch monthly OK (HareketliUrunListesi filtreli liste verir).
- **17 FifoManuelMaliyet** ⚠️ **ÖLÜ ÖZELLİK**: hiçbir SP/rapor view'i `FifoManuelMaliyet`'i tüketmiyor. Kod yorumu "raporlarda override" → app-side'dı, app arşivlendi. Veri girilebilir ama SQL FIFO/rapor katmanında kullanılmıyor. Karar: ya rapor view'ine entegre et ya kaldır.

### C# KATMANI — hangfire/ + app/ (adversarial inceleme, 2026-06-02, koddan)
Şüpheyle: memory'de "opening job V2 kullanır" deniyordu — **YANLIŞ**, koddan doğrulandı.

**A1 (KRİTİK, doğruluk): İki ayrı açılış yolu, farklı SP, farklı sonuç.**
- `hangfire/FifoOpeningJob.cs:59` → `sp_Fifo_AcilisMaliyetlendir` (orijinal 02, mekan-12 DAHİL, irsHrk as-of tarih) = **kurala uygun**.
- `app/Features/Fifo/Wizard.cshtml.cs:172` → `sp_Fifo_AcilisCalistir_V2` (14_V2, mekan-12 HARİÇ + stokSonAltDepo_vw güncel stok) = **kurala AYKIRI** (havuz eksik, en büyük depo yok, devir tarihi yok sayılır).
- → Açılışı kim yaparsa (UI Wizard vs job) farklı maliyet. FIX: ikisi de aynı doğru SP'yi çağırmalı; V2 düzeltilene dek Wizard 02'yi çağırmalı.

**H1 (KRİTİK, operasyonel): Takılı CALISIYOR run dönemi sonsuza kilitler.** `sp_Fifo_BatchRunBaslat` (09) aynı dönemde CALISIYOR run varsa RAISERROR. Job crash/reboot ile Durum='CALISIYOR' kalırsa o dönem için yeni run **kalıcı bloklu** — stale-run temizliği/timeout yok. FIX: stale run tespiti (RunBaslangic eski + süreç yok) → otomatik HATA'ya çek.

**H2 (ORTA): Batch timeout = 120 × batch.Count** (`FifoMonthlyJob.cs:92`) = 60.000s (~16.6 saat). Takılı batch run'ı ~17 saat bloklar. Çarpım mantığı hatalı görünüyor.

**H3 (ORTA): Açılış Phase-2 tek ürün uygulama hatası TÜM açılışı durdurur.** `FifoOpeningJob.cs:122` `when (!IsApplicationError(ex))` → THROW≥50000 catch'lenmez, dışarı sızar, job ölür. MonthlyJob SQL'de izole ediyor; burada izolasyon yok.

**A2 (ORTA, silent failure): `app/Lib/Db.cs` her yerde `catch {}` / `catch { return null/new() }`** (satır 54,95,125,197,214,233,247,260). DB hatası sessizce boş sonuca dönüşür, log YOK (Db'de ILogger yok). DB düşse kullanıcı eksik veri görür, hata sinyali yok. Mekan cache fallback hardcoded isimlere sessiz düşer.

**A3 (ORTA, doğruluk): Mekan kimliği çelişkisi.** Db.cs fallback: `12 = "Merkez Depo" (Tip 3 depo)`, `1 = "FSM Mgz" (Tip 2 mağaza)`. Memory "1=Merkez, 12=Şube2" diyordu → **memory yanlış**. Canlı veri (mekan 12 = en büyük 6.29M stok) Db.cs ile uyumlu: 12 = ana depo. semantic_layer mekan tablosu düzeltilmeli.

**A4 (DÜŞÜK): Static mutable cache thread-safe değil.** `_mekanCache/_urunCache/_devreDisiCache` static, kilitsiz, eşzamanlı istekte race + `_urunCache` sınırsız büyür (bellek sızıntısı).

**H5/güvenlik: `/hangfire` dashboard `Authorization=[]`** → kimlik doğrulama yok, herkese açık (bilinen).

### RERUN/FK BUG — lokal demo'da bulundu + DÜZELTİLDİ (2026-06-02)
**Bulgu (canlı demo, 100 ürün, Jan 2026 re-run):** Aylık dönem 2. kez koşulunca 13/86 ürün hata: `DELETE conflicted with FK_FifoCikisDetay_FifoKatman`.
- **Kök neden:** `sp_Fifo_Calistir` sırası AlisKatmanEkle → CikisMaliyetle. `sp_Fifo_AlisKatmanEkle` dönemin ALIS katmanlarını `DELETE FROM FifoKatman WHERE KaynakTip='ALIS'` ile siler. Rerun'da önceki çıkışın `FifoCikisDetay` satırları o katmanları FK ile referans ediyor → DELETE patlar → ürün atlanır. Rerun-safe rollback CikisMaliyetle İÇİNDE ve SONRA çalışıyordu → çok geç.
- **İkincil:** Batch "13 hatalı" raporladı ama `FifoBatchHata` BOŞ — doomed transaction rollback, FifoBatchHata INSERT'ini de geri alıyor (hata logu kaybı). Table-var ile yakalandı.
- **FIX (02 `sp_Fifo_Calistir`):** rerun-rollback (dönem FifoCikisDetay'ı KalanMiktar'a geri yükle + sil) **AlisKatmanEkle'den ÖNCE** eklendi. Alış(+)→Satış(−) sırası korundu.
- **Doğrulama:** Jan 2026 re-run → 86/86 başarılı, 0 hata, C1 invariant 0 ihlal. ✅

### 18 — Dönem Kontrol ✅
- **sp_Fifo_DonemKontrol**: sonraki aylarda ALIS/CIKIS/ORTALAMA var mı (cascade re-run uyarısı).
- **sp_Fifo_DonemSnapshotAl**: mevcut FifoKatman+CikisDetay özetini snapshot'a yazar. Ağırlıklı maliyet = `SUM(Kalan*BM)/SUM(Kalan)`.
- **vw_Fifo_DonemDegisim**: snapshot vs mevcut fark.
  - ⚠️ Snapshot özet `WHERE GirisTarihi <= @donemBitis` ama vw_Fifo_DonemDegisim "mevcut" tarafı tarih filtresiz tüm katmanı toplar → snapshot ile karşılaştırma dönem-asimetrik olabilir. (düşük öncelik, doğrulanacak)
