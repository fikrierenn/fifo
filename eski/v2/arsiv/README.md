# arsiv/ — Eski / Deprecated Dosyalar

2026-06-02'de `git mv` ile buraya taşındı (silinmedi, geçmiş korundu). **Aktif değil.**

## İçerik
- **Kök eski SQL** (19): `00_MASTER_DEPLOY*.sql`, `01_ACILIS_TEK_SEFERLIK.sql`, `01_sp_CreateTables.sql`, `02_AYLIK_RUTIN.sql`, `02_sp_RunStep.sql`, `analiz_*.sql`, `debug_*.sql`, `test_*.sql`, `redeploy.sql`, `schema_sorgulari.sql`, `irs_tip_sorgulari.sql`, `syntax_test.sql`, `ters_fifo_analiz.sql`, `yukle_erp_devir_fiyatlari.sql` — v2-production öncesi dağınık scriptler.
- **sql-alpha/** — alpha referans implementasyonu.
- **SQL-Improvements/** — Sprint1+2 (v2-production'a entegre edildi).
- **yedek/** — eski Razor Pages `src/App` referans kodu + eski SQL + test scriptleri.

## AKTİF (arşivde DEĞİL — dokunma)
`v2-production/` (deployed SQL 01..19) · `app/` (Razor UI) · `hangfire/` · `tests/` · `docs/` · `.claude/`

> Geri almak: `git mv arsiv/<x> <hedef>`.
