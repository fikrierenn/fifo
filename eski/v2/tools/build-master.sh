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
    # 02'den superseded iki SP'yi ISIM ile disla.
    #   sp_Fifo_AcilisCalistir -> 14_V2 ..._V2 tarafindan devralindi
    #   sp_Fifo_AylikRutin     -> 05_V2 AylikRutinFull tarafindan devralindi
    # NOT: eskiden `sed -n '1,1502p;1533,1573p'` ile SATIR NUMARASI dilimleniyordu.
    # Kaynak dosyaya tek satir eklenince dilim kayiyor ve master yarim prosedurle
    # uretiliyordu (2026-09-10'da "Must declare the scalar variable" ile yakalandi).
    awk '
      /^CREATE OR ALTER PROCEDURE dbo\.sp_Fifo_AcilisCalistir[[:space:]]*$/ { skip=1 }
      /^CREATE OR ALTER PROCEDURE dbo\.sp_Fifo_AylikRutin[[:space:]]*$/     { skip=1 }
      skip==0 { print }
      /^PRINT '"'"'sp_Fifo_AcilisCalistir proseduru olusturuldu'"'"';[[:space:]]*$/ { skip=0 }
      /^PRINT '"'"'sp_Fifo_AylikRutin proseduru olusturuldu'"'"';[[:space:]]*$/     { skip=0 }
      END { if (skip) { print "HATA: 02 exclusion kapanmadi — bitis PRINT satiri degismis olabilir." > "/dev/stderr"; exit 2 } }
    ' 02_V2_CoreProcedures.sql | sed -E "$PARAM" >> "$OUT" || exit 2
  else
    sed -E "$PARAM" "$file" >> "$OUT"
  fi
done
printf '\nGO\nPRINT %s### FIFO V2 MASTER bitti%s;\nGO\n' "$q" "$q" >> "$OUT"

# ---------------------------------------------------------------------------
# URETIM SONRASI DOGRULAMA (fail-closed)
# Eksik SP veya sizmis yikici DDL "0 hata" ile deploy edilebilir; kirilma
# calisma zamaninda ortaya cikar. Bu yuzden master burada reddedilir.
# ---------------------------------------------------------------------------
fail() { echo "BUILD REDDEDILDI: $*" >&2; exit 1; }

EXPECTED_SP=16
ACTUAL_SP=$(grep -c "^CREATE OR ALTER PROCEDURE" "$OUT" || true)
[ "$ACTUAL_SP" -eq "$EXPECTED_SP" ] || fail "master $ACTUAL_SP SP iceriyor, beklenen $EXPECTED_SP"

for sp in sp_Fifo_AcilisMaliyetlendir sp_Fifo_AlisKatmanEkle sp_Fifo_CikisMaliyetle \
          sp_MaliyetAdimYaz sp_Fifo_Calistir sp_Fifo_AylikCalistir \
          sp_Fifo_AcilisCalistir_V2 sp_Fifo_AylikRutinFull sp_Ortalama_AylikHesapla; do
  grep -q "^CREATE OR ALTER PROCEDURE dbo\.$sp\b" "$OUT" || fail "$sp master'da yok"
done

# Superseded SP'ler sizmamali (tam eslesme: _V2 / Full sonekli olanlari yakalamaz)
# NOT: `grep -q ... && fail` YAZMA — `set -e` altinda grep'in bulamamasi (istenen
# durum) betigi sessizce 1 ile dusurur. if/then kullan.
if grep -qE '^CREATE OR ALTER PROCEDURE dbo\.sp_Fifo_AcilisCalistir[[:space:]]*$' "$OUT"; then
  fail "superseded sp_Fifo_AcilisCalistir master'a sizdi"
fi
if grep -qE '^CREATE OR ALTER PROCEDURE dbo\.sp_Fifo_AylikRutin[[:space:]]*$' "$OUT"; then
  fail "superseded sp_Fifo_AylikRutin master'a sizdi"
fi

# ── YIKICI DDL KAPISI (plans/01) ───────────────────────────────────────────
#
# Eski hali: grep -cE '^[[:space:]]*DROP TABLE dbo\.'
# UC bicimi birden kaciriyordu:
#   IF OBJECT_ID('dbo.X','U') IS NOT NULL DROP TABLE dbo.X;   <- satir basi degil
#   DROP TABLE FifoKatman                                      <- sema oneki yok
#   DROP TABLE [dbo].[FifoKatman]                              <- koseli parantez
# Ayni aileden bir desen 2026-09-10'da OrtalamaAylikMaliyet'i KACIRDI ve
# "yikici DROP temizlendi" sanildi (yama-hedefi-dogrulama.md).
#
# TARAMA KOPYASI: yalniz `--` satir yorumlari ayiklanir.
#
# BLOK YORUM (/* */) AYIKLAMA DENENDI VE KALDIRILDI (2026-09-11, olculdu):
# awk tabanli durum makinesi master'da 842 DOLU SATIR yutuyor ve 16
# prosedurden 2'sini kaybediyordu. Blok acilis/kapanis sayilari dengeli
# (86/86) oldugu halde bozuluyordu — muhtemelen dize icindeki `/*`/`*/`
# dizileri yuzunden. Sonuc: gate SAKATLANMIS bir kopyayi tariyor ve her sey
# yesil gorunuyordu. Bu, kapinin kendisini yalanci-yesil yapan en kotu hal.
#
# Blok yorumda `DROP TABLE` gecerse gate GURULTULU sekilde reddeder ve
# yorumu yeniden yazmak gerekir. Bilincli tercih: gurultulu hata sessiz
# hatadan iyidir (dogrulama-siniri.md). Kaynak dosyalardaki aciklama
# yorumlari bu yuzden `DROP TABLE` ifadesini LITERAL yazmaz.
CLEAN="$(mktemp)"; trap 'rm -f "$CLEAN"' EXIT
sed -E 's@--.*$@@' "$OUT" > "$CLEAN"

# Tarama kopyasi gercekten dolu mu? Bos/kirpik CLEAN tum kapilari sessizce
# yesil yapar — kapinin en tehlikeli ariza kipi budur.
CLEAN_DOLU=$(grep -c '[^[:space:]]' "$CLEAN" || true)
OUT_DOLU=$(grep -c '[^[:space:]]' "$OUT" || true)
[ "$CLEAN_DOLU" -ge $(( OUT_DOLU * 90 / 100 )) ] \
  || fail "tarama kopyasi kirpilmis ($CLEAN_DOLU / $OUT_DOLU dolu satir) — kapilar guvenilmez"

# DISLAMA DEGIL, KALINTI SAYIMI: once temp (#) formlarini sil, KALAN her
# DROP TABLE kalicidir. Dislama listesi dar desen uretir: `DROP TABLE IF
# EXISTS #tmp` bicimi opsiyonel grup bos eslesince `I` harfini yakalayip
# temp tabloyu "kalici" sanardi.
DROPS=$(sed -E 's/DROP[[:space:]]+TABLE[[:space:]]+(IF[[:space:]]+EXISTS[[:space:]]+)?#[A-Za-z0-9_#$]*//gI' "$CLEAN" \
        | grep -ciE 'DROP[[:space:]]+TABLE' || true)
[ "$DROPS" -eq 0 ] || fail "master $DROPS satirda kalici DROP TABLE iceriyor (veri kaybi riski)"

# TRUNCATE en az DROP kadar yikici; fifo-domain.md §2 FifoDevreDisiUrunler
# icin TRUNCATE/DELETE'i ACIKCA yasakliyor.
TRUNCS=$(grep -ciE 'TRUNCATE[[:space:]]+TABLE' "$CLEAN" || true)
[ "$TRUNCS" -eq 0 ] || fail "master $TRUNCS adet TRUNCATE TABLE iceriyor (fifo-domain §2)"

# ── §6 KAPISININ KENDISI DURUYOR MU ──
# Denge TEK BASINA yetmez: ADD ve DROP birlikte silinirse `0 <= 0` gecer ve
# CHECK master'dan SESSIZCE kaybolur. Denge "kayip yok" der; varlik "kapi
# duruyor" der. Asil istenen ikincisidir.
CKADD=$(grep -ciE 'ADD[[:space:]]+CONSTRAINT[[:space:]]+CK_'  "$CLEAN" || true)
CKDROP=$(grep -ciE 'DROP[[:space:]]+CONSTRAINT[[:space:]]+CK_' "$CLEAN" || true)
[ "$CKDROP" -le "$CKADD" ] || fail "CK_ DROP ($CKDROP) > ADD ($CKADD) — net constraint kaybi"
for ck in CK_FifoKatman_BirimMaliyet CK_FifoCikisDetay_BirimMaliyet; do
  grep -qE "ADD[[:space:]]+CONSTRAINT[[:space:]]+$ck[[:space:]]+CHECK[[:space:]]*\([[:space:]]*BirimMaliyet[[:space:]]*>[[:space:]]*0" "$CLEAN" \
    || fail "$ck (>0) master'da YOK — §6 kapisi kayboldu"
done

# Lokal ERP adi uretime sizmamali
LEAK=$(grep -c 'DerinSIS_Local' "$OUT" || true)
[ "$LEAK" -eq 0 ] || fail "master $LEAK adet DerinSIS_Local referansi iceriyor ($(basename "$0") PARAM kurali)"

# Proje kurali: SELECT * yasak
STAR=$(grep -cE 'SELECT \* INTO' "$OUT" || true)
[ "$STAR" -eq 0 ] || fail "master $STAR adet 'SELECT * INTO' iceriyor"

# ── KANCA OZ-TESTI ──
# Bir oz-test "ne zaman kosacagi" belirlenmeden yazilirsa KENDISI atesLENMEYEN
# bir kapi olur (fifo-kapi-danismani, 2026-09-11). Buraya baglandi.
if [ -x tools/hook-selftest/kos.sh ] || [ -f tools/hook-selftest/kos.sh ]; then
  if ! bash tools/hook-selftest/kos.sh >/dev/null 2>&1; then
    echo "UYARI: post-edit kanca oz-testi KIRIK (bash tools/hook-selftest/kos.sh ile bak)" >&2
  fi
fi

echo "master uretildi: $(wc -l < "$OUT") satir — $ACTUAL_SP SP, dogrulama GECTI"
