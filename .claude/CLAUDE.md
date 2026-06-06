# FIFO Projesi — Context Index

> **Mimari**: Hiyerarşik context. Bu dosya lean index, detaylar sub-file'larda.
> Agent göreve göre ilgili dosyayı okur, tamamını yüklemez.
> Session sonunda bu dosyadaki SON DURUM bölümünü güncelle.

## SON DURUM (2026-06-06 #7)
- **OCAK 2026 TAM TEMIZLIK + KARLILIK rev2.** Son commit `fd1ace4`. 10 commit bu oturum.
- **Karlilik rev2**: Gelir 72.27M · Maliyet 46.69M · **Brut kar 25.58M · marj %35.40**. Rapor `raporlar/Ocak2026_Karlilik_Raporu.md` (rev2) + CSV 89.197 satir (isim kolonlu). Magaza 4477 %37.4 / 1 %38.2 / 4478 %38.1 / depo-12 %6.9.
- **SP BUG FIX (CRIT-1) — acilis sessiz veri kaybi**: acilis envanteri olan urun, aylik-devir atlanir/kenar durumda NE katman NE FIYAT_YOK aliyordu (sessiz kayip). COMMIT oncesi invariant net guvenlik agi eklendi (02 `385eb44` + 14 `34fea7a`). Re-run: FIYAT_YOK 251→619 = net ~368 GIZLI urunu gorunur yapti.
- **FIYAT_YOK 1395→619**: fytOzl seed (6.6M) + 605 fallback fiyat (FifoFallbackFiyatlari 'DEVIR_FALLBACK': SonAlis veya SatisFiyat*0.65 tahmin) + net fix. Kalan 619 kaynakta fiyatsiz.
- **31 non-inventory devre-disi** (6+8+ekler; gelir/gider kalemi, hediye ceki, demirbas/sabit kiymet, posetler). DERS §3: isim-pattern + KatAna='Tanımsız' ikisi de tek basina gercek urunu yanlis yakalar — gozle dogrula.
- **14 cost-anomali ManuelMaliyet override** (`b8cafa9`): Okapi×4 (2936→194) + 10. ManuelMaliyet eskiden ORPHAN'di → acilis SP'ye en yuksek oncelikli kaynak olarak baglandi (CROSS APPLY). Negatif marj 73→58. Karne Hediyesi HARIC (geliri 0.01 kasitli promo).
- **02↔14 tarih-penceresi hizalandi** (`bec5bb7`, karar 02→14): stale fiyat KABUL.
- **2 yeni ajan**: `maliyet-stok-uzman` + `sorunlu-urun-dedektif` (her ikisi opus, salt-okuma). `19_V2_DevreDisi_Fallback_Seed.sql` idempotent seed (devre-disi + fallback + manuel maliyet).
- **Siradaki (fatura verisi bekliyor — otonom YOK)**: (1) 58 B-grubu negatif marj tek tek fatura teyidi, (2) 565 fallback + 14 override TAHMIN degerleri gercek fatura koli adediyle guncelle, (3) C1-C4 ✅ stabil.
- ---- onceki #6/#5 (referans) ----
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
