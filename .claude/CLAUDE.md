# FIFO Projesi — Context Index

> **Mimari**: Hiyerarşik context. Bu dosya lean index, detaylar sub-file'larda.
> Agent göreve göre ilgili dosyayı okur, tamamını yüklemez.
> Session sonunda bu dosyadaki SON DURUM bölümünü güncelle.

## SON DURUM (2026-06-06 #6)
- **OCAK 2026 KARLILIK HESAPLANDI + RAPORLANDI.** Commit `32f46ee`.
- **SatisTutar SP'ye eklendi**: `sp_Fifo_CikisMaliyetle` FifoCikisDetay.SatisTutar dolduruyor (irsHrk geliri ehTutarN, ehTip 1,4,5,100,101, miktar oranli dagitim). Deploy+re-run yapildi.
- **Ocak 2026**: Gelir 72.28M · Maliyet 46.88M · **Brut kar 25.40M · marj %35.14**. Magaza 4477/1/4478 ~%38, mekan-12 (ana depo) %4.47. Rapor: `raporlar/Ocak2026_Karlilik_Raporu.md` + `Ocak2026_UrunMagaza_Karlilik.csv` (89.189 satir).
- **FIYAT_YOK 1395→871**: lokal fytOzl seed (2022'de kesik) canlidan 6.6M satir tamamlandi → 524 urun fiyat kazandi. Kalan 871 = kaynakta da fiyatsiz.
- **UrunBilgi lokale cekildi**: `DerinSIS_Local.dbo.UrunBilgi` (853k satir, isim/kategori — artik canliya gitme).
- **9 non-inventory devre-disina eklendi** (gozle dogrulanmis §3; isim-pattern+KatAna ikisi de tek basina guvenilmez). Karne Hediyesi/Okapi TASINMADI (gercek urun).
- **COST ANOMALI**: Okapi Kalem Çantası BirimMaliyet 2936 vs satis 299 → ERP SonAlis hatasi (koli/qty), FIFO dogru. Fix beklemede (ManuelMaliyet override).
- **irs minimal seed**: disk temizliginde DROP edilen `DerinSIS_Local.dbo.irs` acilis SP'sini patlatti → eID+eMekan (eMekan=12, 6.9M) geri kuruldu.
- **sqlcli lokale kopyalandi** (`fifo/sqlcli/`, gitignore) + sqlcli.json BT-FIKRI'ye cekildi.
- **Siradaki**: (1) Okapi cost override (ManuelMaliyet), (2) eski 8 devre-disi sebep §2-aykiri gozden gecir, (3) 677 kalan FIYAT_YOK ayir.
- ---- onceki #5 (referans) ----
## SON DURUM (2026-06-03 #5)
- **HANDOFF (akşam)**: Sabah **FIFO'ya devam**. Diğer işler (commit/Express teardown) bekleyebilir. Bu oturum: migration + disk temizliği bitti.
- **DISK TEMİZLİĞİ**: C **0→35GB** (recycle 8.3GB + SQLEXPRESS tempdb 4.7GB shrink + temp). D **+6.8GB** (D:\blobs = orphan Ollama LLM modelleri silindi). Kalan büyükler dokunulmadı: Rapor.pst 13.5GB (email arşiv), SQLData ~10GB (DB), Belgelerim\Masaüstü 6GB. Yeni tool: `tools/disk-temizle.ps1` (dry-run default, `-Apply` siler; C+D + 3 instance tempdb; .NET enum hızlı).
- **Son çalışılan**: Developer Edition KURULDU + DB'ler TAŞINDI (BT-FIKRI). 10GB limit derdi BİTTİ. Devir+pipeline+dogrula zaten geçmişti (#4).
- **MIGRATION TAMAM**: `BT-FIKRI\SQLEXPRESS` (Express) → `BT-FIKRI` (default, **Developer 16.0**, limitsiz). Yöntem: detach → dosya C→D taşı → attach (backup/restore değil, ekstra yer yok). DB dosyaları **`D:\SQLData`**. Doğrulama: irsHrk 58.106.851 · Açılış 508.801 · Çıkış 267.484 · Katman 656.118 — tam. **C 0→20.85GB** boş, D 6.85GB.
- **Bağlantı**: artık `Invoke-Sqlcmd -ServerInstance 'BT-FIKRI'` (instance YOK). Docs güncellendi (CLAUDE.md, fifo-domain.md). sqlcli SQLCLI_CONN lokal için BT-FIKRI'ye ayarlanmalı.
- **Temizlik kaldı**: eski Express instance'ları (SQLEXPRESS, SQLEXPRESS01) + LIVE201 linked server (Express'teydi) — opsiyonel kaldır. DerinSIS_Hrk zaten DROP edildi. BKMMaliyet_D.ndf artık normal secondary file (migrated DB parçası, temizlik değil).
- **Git**: 02_V2_CoreProcedures.sql değişti (CikisMaliyetle irsHrk) — commit YOK.
- **Sıradaki**: (1) commit (SP irsHrk + .claude doc güncellemeleri), (2) eski Express + LIVE201 kaldır. **Ayrı sprint**: IADE fix (IMP-1).
- ---- önceki #4 detayı (referans) ----
- **DEVİR DÜZELTİLDİ + full pipeline re-run + /fifo-dogrula GEÇTİ.** Express 10GB kök neden bulundu.
- **DEVİR FIX**: eski açılış 2932 ürün (kısmi irsHrk yüzünden). Full irsHrk (58.1M) ile açılış re-run → **508.801 satır / 249.328 ürün / stok 9.184.370** (validation birebir). Açılış SP zaten doğruydu (`02:67-81` irsHrk kümülatif `ehTrhS<=devir`, altDepo=0, pool, HAVING SUM>0); sorun stale veriydi.
- **Pipeline re-run (Ocak 2026)**: açılış+alış+çıkış. Katman: ACILIS 567.682 / ACILIS_TAMAMLA 34.655. Çıkış: SATIS 266.693 satır/55.804 ürün/46.8M tutar, IADE 791 satır/759 ürün (iade KORUNDU → rewrite doğru).
- **/fifo-dogrula**: C1 katman-tüketim ✅0, C2✅ C3✅ C4✅, C5 STOK_YETERSIZ 550 ürün (beklenen), C6 13 sıfır-maliyet katman, **C7 mekan-12 boşluğu DÜZELDİ** (açılış12=26.442, eski V2 bug full devir ile çözüldü), C8 ERP katman-fark beklenen (devre-dışı+tüketim; envanter-seviye birebir). **Çekirdek invariant'lar geçti.**
- **fytOzl index**: lokalde `IX_fytOzl_SonKayit_Seek` eksikti → kuruldu (açılış pricing TVF hint'i). irsHrk'ye `IX_irsHrk_trh_mekan_tip(ehTrhS,ehMekan,ehTip)` eklendi (çıkış tarih-aralığı SARGable).
- **KÖK NEDEN — Express 10GB/DB limiti**: DerinSIS_Local full irsHrk ile tavana dayandı ("büyüme" sorunu buydu). İki instance da Express (SQLEXPRESS, SQLEXPRESS01). **Çözüm = SQL Server 2022 Developer Edition** (ücretsiz, limitsiz, aynı T-SQL, kod değişmez). SQLite/Postgres REDDEDILDI (T-SQL motoru komple rewrite gerektirir, prod paritesi bozulur).
- **Developer install**: bootstrapper indi `D:\Temp\SQL2022-SSEI-Dev.exe` (linkid=2215158). /Q sessiz çalışmadı → GUI. **Kullanıcı manuel indiriyor/kuruyor.** Kurulunca DerinSIS_Local (bütün, irsHrk dahil) + BKMMaliyet oraya restore → repoint GEREKMEZ (DerinSIS_Local adı korunur).
- **DerinSIS_Hrk** (D'de, compress'li irsHrk 58.1M) = geçici YEDEK. SP repoint İÇİN KULLANILMADI (prod-uyumsuz isim olur). Developer geçişi sonrası DROP.
- **Disk müdahaleleri**: irs/irsAyr DROP edildi (DerinSIS_Local); BKMMaliyet'e `BKMMaliyet_D.ndf` (D) eklendi; loglar+data shrink → C 12.97GB. BKM tabloları PAGE compress.
- **Git**: 02_V2_CoreProcedures.sql değişti (CikisMaliyetle irsHrk) — commit YOK.
- **Linked server `LIVE201`** + `D:\SQLData\BKMMaliyet_D.ndf` + `DerinSIS_Hrk` → Developer geçişi sonrası temizlik.
- **Sıradaki**: (1) Developer kurulsun → DB'leri taşı (no repoint), (2) DerinSIS_Hrk + LIVE201 + BKMMaliyet_D temizle, (3) commit. **Ayrı sprint**: IADE fix (IMP-1).
- **Eski bekleyen**: Hangfire dashboard auth, prod deploy (sunucu belirsiz), kök SQL temizliği

## CONTEXT INDEX — Görev tipine göre ilgili dosyayı oku

| Görev Tipi | Dosya | Ne Zaman Oku |
|------------|-------|--------------|
| Proje kuralları, dizin yapısı, teknoloji | [`CLAUDE.md`](../../CLAUDE.md) (proje kökü) | Her zaman okunur (otomatik) |
| Proje durumu, deploy geçmişi, sıradaki görevler | [`memory/project_status.md`] | Görev planlarken |
| İş mantığı, FIFO akışı, SP haritası, metrikler | [`memory/semantic_layer.md`] | FIFO mantığı soruları, yeni SP yazarken |
| DB şeması, tablo kolonları, index, SP parametreleri | [`memory/schema.md`] | SQL yazarken, tablo yapısı gerektiğinde |
| Canlı DB durumu, obje envanteri, sqlcli kullanım | [`memory/db_live_state.md`] | Deploy, DB sorgu, durum kontrolü |
| Kodlama kuralları, geri bildirimler | [`memory/feedback_coding.md`] | Kod yazarken |
| Kullanıcı profili, çalışma tercihleri | [`memory/user_profile.md`] | İlk etkileşimde |
| Performans stratejisi, batch optimizasyon | [`docs/PERFORMANCE_BATCH_STRATEGY_V1.md`] | Performans işlerinde |
| V2 refactor planı, pipeline mimarisi | [`docs/AI_REFACTOR_PROMPT_V2_PIPELINE.md`] | Mimari kararlarında |

> **memory/ yolu**: `C:\Users\fikri.eren\.claude\projects\d--Dev-fifo\memory\`

## KRİTİK KURALLAR (her zaman geçerli)
- Türkçe, kısa cevap (1 cümle gerekçe + çıktı)
- `sqlcli` kullan, `sqlcmd` KULLANMA: `cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- <komut>`
- `SELECT *` yasak, `NOLOCK` yasak, `MERGE` yerine `DELETE+INSERT`
- API endpoint yok — Razor Pages direkt DB (Dapper)
- Çalışmalar **LOKAL DB** üstünde (canlı 192.168.40.201 sıkıntılı) → `memory/feedback_local_db.md`
- Sub-agent kullan: delegasyon + model katmanı disiplini → `.claude/rules/agent-usage.md`

## .claude Altyapısı (Operax'tan adapte, 2026-06-02)
- **`.claude/rules/`** — `agent-usage.md` (model-tier + iş→agent matrisi), `memory-protocol.md` (oturum/hafıza disiplini, mevcut memory/ sistemine bağlı)
- **`.claude/agents/`** — 5 salt-okuma subagent: `sql-sp-reviewer` (opus, FIFO iş-doğruluğu), `code-explorer` (haiku), `build-validator` (haiku), `db-schema-checker` (haiku, lokal), `silent-failure-hunter` (opus)
- **`.claude/hooks/`** — `session-start.sh` (git+SON DURUM+session_log inject), `pre-compact.sh` (snapshot→memory/session_log.md). settings.local.json'da wire'lı. Caveman SessionStart (user-level) ile yan yana.
- **`.claude/commands/fifo-dogrula.md`** — FIFO invariant doğrulama (8 kontrol)

## FIFO DOMAIN KURALLARI (ZORUNLU — detay: `.claude/rules/fifo-domain.md`)
1. **Maliyet = mekan-bağımsız ortak havuz** (FIFO `PARTITION BY StkId` doğru); satış mekan-bazlı; karlılık mekan bazında. Havuz seti `1,12,4477,4478` + `ehAltDepo=0` — açılış/çıkış/ortalama AYNI. **Mekan 12 = ana depo, asla dışlama.**
2. **Devre-dışı (FifoDevreDisiUrunler) = İSİM/KATEGORİ bazlı** (poşet/ambalaj/hediye çeki/gider). **`SonAlis=0`/"alış yok" kriteri YASAK** (gerçek kırtasiyeyi dışlar — fiyatı fytOzl'den gelir). Tablo **kalıcı+additive**, truncate/delete yok.
3. **Sınıflandırma/dışlamadan ÖNCE gerçek veriye bak** — kaba heuristikle toplu işlem yok. Memory/eski-koda güvenme, doğrula.
4. **Rerun-safe**: katman silmeden önce dönem çıkışını geri-al+sil (FK). Açılış re-run → önce FIFO çıktı tablolarını temizle.
5. **Lokal demo**: `BT-FIKRI` (default instance, **Developer Edition**, DB dosyaları `D:\SQLData`), kaynak `DerinSIS_Local` (canlı kullanma). Eski Express terk. sqlcli `copy` ile ETL. Yıl 2026, devir 2025-12-31.
