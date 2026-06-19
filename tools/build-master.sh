#!/usr/bin/env bash
# Master uretici — v2-production CURATED kaynaklardan 00_V2_MASTER_FULL.sql derler.
# SADECE kullanilan objeler; superseded/test/local-fix HARIC; $(ErpDb)/$(MaliyetDb) parametrik.
set -euo pipefail
cd "$(dirname "$0")/../v2-production"
OUT="00_V2_MASTER_FULL.sql"; q="'"
cat > "$OUT" <<'HDR'
/* ============================================================================
   00_V2_MASTER_FULL.sql — BKMMaliyet FIFO V2 — TEK MASTER (portable, 0→canli)
   tools/build-master.sh tarafindan uretilir (elle duzenleme). Kaynak: v2-production CURATED.
   SADECE KULLANILAN: test/benchmark(06/08/10/11), superseded(07→16,
   AcilisCalistir/AylikRutin eski→_V2/Full), local-fix(20/21) HARIC. Her obje 1 kez.
   PARAMETRIK (sqlcmd): $(MaliyetDb) hedef DB, $(ErpDb) ERP kaynak.
   Deploy: Invoke-Sqlcmd -InputFile bu -Variable "MaliyetDb=X","ErpDb=Y"
   YAPI: tablolar → SatisTutar kolonu → SP'ler → view'lar → curated seed.
   Pipeline (acilis+aylik) deploy SONRASI ayri tetiklenir (master'a dahil DEGIL).
   ============================================================================ */
-- :setvar MaliyetDb "BKMMaliyet"   (SSMS SQLCMD-modu icin yorum-disi birak)
-- :setvar ErpDb "DerinSISBkm"
GO
USE [$(MaliyetDb)];
GO
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;
GO
HDR
PARAM='s/USE[[:space:]]+BKMMaliyet/USE [$(MaliyetDb)]/g; s/DerinSIS_Local/$(ErpDb)/g'
SECTIONS=(
"01 Tablolar|01_V2_Tables.sql"
"19 Cikis SatisTutar (computed col, SP ONCESI)|19_V2_CikisSatisTutar.sql"
"12 Ortalama Aylik Maliyet|12_V2_OrtalamaAylikMaliyet.sql"
"02 Core SP (eski AcilisCalistir+AylikRutin HARIC, AylikCalistir TUTULDU)|@02"
"04 Sentetik Fallback|04_V2_SentetikFallback.sql"
"05 Aylik Rutin Full|05_V2_AylikRutinFull.sql"
"09 Batch Orchestration|09_V2_BatchOrchestration.sql"
"14 Acilis Optimize + GARANTI final-tier (FIYAT 0 OLAMAZ)|14_V2_AcilisOptimize.sql"
"16 HareketliUrunListesi FINAL (07 yerine)|16_V2_DevreDisiFiltre.sql"
"15 Devre Disi Urunler|15_V2_DevreDisiUrunler.sql"
"17 Manuel Maliyet|17_V2_ManuelMaliyet.sql"
"18 Donem Kontrol + Snapshot|18_V2_DonemKontrol.sql"
"03 Temel Viewlar|03_V2_Views.sql"
"13 Eksik Viewlar|13_V2_EksikViewlar.sql"
"SEED Devre-disi + Fallback + ManuelMaliyet|19_V2_DevreDisi_Fallback_Seed.sql"
)
for s in "${SECTIONS[@]}"; do
  label="${s%%|*}"; file="${s##*|}"
  printf '\nGO\nPRINT %s======== %s ========%s;\nGO\n' "$q" "$label" "$q" >> "$OUT"
  if [ "$file" = "@02" ]; then
    sed -n '1,1502p;1533,1573p' 02_V2_CoreProcedures.sql | sed -E "$PARAM" >> "$OUT"
  else
    sed -E "$PARAM" "$file" >> "$OUT"
  fi
done
printf '\nGO\nPRINT %s### FIFO V2 MASTER bitti%s;\nGO\n' "$q" "$q" >> "$OUT"
echo "master uretildi: $(wc -l < "$OUT") satir"
