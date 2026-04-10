# FIFO Projesi — Context Index

> **Mimari**: Hiyerarşik context. Bu dosya lean index, detaylar sub-file'larda.
> Agent göreve göre ilgili dosyayı okur, tamamını yüklemez.
> Session sonunda bu dosyadaki SON DURUM bölümünü güncelle.

## SON DURUM (2026-03-24)
- **Son çalışılan**: Dönem kontrol + cascade re-run + değişim raporu + Ürün Kartı tab revamp
- **Tamamlanan**: 14-18 SQL deploy + Test (27/27) + 27 sayfa + dönem kilidi + snapshot
- **Yeni sayfalar**: DonemDegisim, RunHistory, ManuelMaliyet
- **Revize**: UrunDetay (tab navigasyon, manuel maliyet, devir özeti), JobBaslat (dönem uyarı modal, cascade)
- **Sıradaki**: Production deploy (Kestrel self-hosted, sunucu henüz belirsiz — ertelendi)
- **Blokaj**: Deploy hedef sunucusu belirlenmedi

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
- Sub-agent kullan: uzun bağlam gerektiren görevleri böl
