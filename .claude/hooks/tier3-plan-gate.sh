#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# TIER 3 PLAN KAPISI — PreToolUse (matcher: Edit|Write|MultiEdit)
#
# Kural: `.claude/rules/plan-first.md`
#
# NE YAPAR: Tier 3 yuzeyine (deploy scripti, katman yazan SP, constraint,
# build uretici, cutover) BU OTURUMDA ILK dokunusta, `plans/` altinda ACIK
# bir plan yoksa exit 2 ile BLOKLAR.
#
# ACIK PLAN = plans/NN-*.md var ve icinde `**Durum:**` satiri
# `Onaylandi`/`Onaylandı`/`Uygulamada` diyor.
#
# NEDEN COMMIT KANCASI DEGIL: fifo bir git reposu (bel degildi) ama buradaki
# tehlike commit aninda degil YAZMA aninda dogar — bir deploy scripti
# calistirildiktan sonra commit edilip edilmemesi maliyet defterini geri
# getirmez. Tek zorlama noktasi DOSYAYA YAZMA anidir.
#
# KAPININ KENDI HATASI GORUNUR OLMALI (bel dersi: bir kapi 11 gun sessizce
# acik kaldi cunku hatasi 2>/dev/null ile yutuluyordu). Burada python
# stderr'i yutulmaz; kapi calisamazsa SOYLER ama calismayi durdurmaz.
#
# Bypass: FIFO_TIER3_SKIP=1 -- kural ihlalidir, session_log'a yazilir.
# ─────────────────────────────────────────────────────────────────────
set -u

[ "${FIFO_TIER3_SKIP:-0}" = "1" ] && exit 0

KOK="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
GIRDI="$(cat 2>/dev/null)" || exit 0
[ -n "$GIRDI" ] || exit 0

HATA_DOSYA="$(mktemp 2>/dev/null || echo /tmp/tier3-gate-$$)"

# Yol cozumleme TEK python cagrisinda.
# Ters bolu sayisi KRITIK: JSON'dan gelen Windows yolu tek ters bolu tasir;
# yanlisi kapiyi SESSIZCE ACIK birakir — bir kapinin en kotu hali budur.
YOL="$(printf '%s' "$GIRDI" | python -c '
import sys, json, os
try:
    d = json.load(sys.stdin)
except Exception as e:
    # SESSIZ CIKMA. Bozuk girdi kapiyi ACIK birakir ve bunu kimse gormez —
    # bel deposunda ayni arıza kipi bir kapiyi 11 GUN olu tuttu.
    # Calismayi durdurmuyoruz (exit 0) ama SUSMUYORUZ da.
    print("girdi JSON parse edilemedi: %s" % e, file=sys.stderr)
    sys.exit(0)
ti = d.get("tool_input") or {}
p = ti.get("file_path") or ti.get("filePath") or ""
if not p:
    sys.exit(0)
print(os.path.normpath(p).replace(os.sep, "/"))
' 2>"$HATA_DOSYA")" || YOL=""

if [ -s "$HATA_DOSYA" ]; then
  echo "uyari tier3 kapisi CALISAMADI (kapi acik kaldi):" >&2
  head -3 "$HATA_DOSYA" >&2
fi
rm -f "$HATA_DOSYA" 2>/dev/null
[ -n "$YOL" ] || exit 0

# MUAF: planin KENDISI, kurallar, dokuman, hafiza, raporlar.
# Yoksa plan yazmak planin varligini gerektirirdi (atesLENEMEZ dongu).
case "$YOL" in
  */plans/*|*/.claude/rules/*|*/.claude/agents/*|*/.claude/skills/*|*/docs/*|*/raporlar/*|*.md)
      exit 0 ;;
esac

# ── TIER 3 YUZEYLERI — her biri plan-first.md'deki numarali sinyal ──
SINYAL=""
case "$YOL" in
  # sinyal 1: deploy scripti / master / build uretici
  */v2-production/00_V2_MASTER_FULL.sql)
      SINYAL="1 · uretim master (re-deploy tum maliyet defterini etkiler)" ;;
  */v2-production/01_V2_Tables.sql|*/v2-production/01a_V2_Tables_RESET.sql)
      SINYAL="1 · tablo DDL / yikici reset" ;;
  */tools/build-master.sh)
      SINYAL="1 · master uretici (sessiz eksik master uretebilir)" ;;

  # sinyal 2: FifoKatman / FifoCikisDetay'a yazan SP'ler
  */v2-production/02_V2_CoreProcedures.sql)
      SINYAL="2 · cekirdek SP (acilis + alis katmani + FIFO cikis)" ;;
  */v2-production/14_V2_AcilisOptimize.sql)
      SINYAL="2 · acilis SP + GARANTI final-tier" ;;
  */v2-production/04_V2_SentetikFallback.sql)
      SINYAL="4 · sentetik katman / fallback kademesi" ;;
  */v2-production/12_V2_OrtalamaAylikMaliyet.sql)
      SINYAL="2 · ortalama aylik maliyet tablosu + SP" ;;
  */v2-production/05_V2_AylikRutinFull.sql|*/v2-production/09_V2_BatchOrchestration.sql)
      SINYAL="5 · uzun pipeline orkestrasyonu" ;;

  # sinyal 4: devre-disi / manuel maliyet / fallback seed = fiyat kaynagi
  */v2-production/15_V2_DevreDisiUrunler.sql|*/v2-production/16_V2_DevreDisiFiltre.sql|\
  */v2-production/17_V2_ManuelMaliyet.sql|*/v2-production/19_V2_DevreDisi_Fallback_Seed.sql)
      SINYAL="4 · devre-disi politikasi / manuel maliyet / fallback seed" ;;

  # Hangfire = pipeline tetikleyici
  */hangfire/Fifo*Job.cs)
      SINYAL="5 · pipeline job (uzun kosu tetikler)" ;;
esac
[ -n "$SINYAL" ] || exit 0

# ── ACIK PLAN VAR MI ──
# DESEN SATIR BASINA CAPALANMAZ.
# Ilk surum `^\*\*Durum:\*\*` ariyordu; gercek plan basligi soyle yaziliyor:
#   **Tarih:** 2026-09-11 * **Tier:** 3 * **Durum:** Uygulamada
# Capa yuzunden kapi ACIK PLANI GORMEDI ve kendi yazdigi plani reddetti
# (2026-09-11'de yakalandi). Bugun ayni sinifin ucuncu tekrari:
# build-master DROP deseni, antipattern kancasi kural 1, ve bu.
# Ders yazili: yama-hedefi-dogrulama.md — dar desen yalanci yesil/kirmizi uretir.
ACIK=""
for f in "$KOK"/plans/[0-9]*.md; do
  [ -e "$f" ] || continue
  if grep -qiE '\*\*Durum:\*\*[[:space:]]*(Onaylandı|Onaylandi|Uygulamada)' "$f" 2>/dev/null; then
    ACIK="$(basename "$f")"
    break
  fi
done
[ -n "$ACIK" ] && exit 0

cat >&2 <<MSG

TIER 3 KAPISI — acik plan yok.

  dosya  : ${YOL#$KOK/}
  sinyal : $SINYAL

\`.claude/rules/plan-first.md\`: Tier 3 iste plan ZORUNLU ve plan
ONAYLANMADAN uygulanmaz. \`plans/\` altinda durumu "Onaylandı" ya da
"Uygulamada" olan bir plan bulunamadi.

Yapilacak:
  ls plans/[0-9]*.md 2>/dev/null | tail -1
  cp plans/plan-sablonu.md plans/NN-<slug>.md
  # doldur -> KULLANICIYA GOSTER -> onay -> **Durum:** Onaylandı

Gercekten Tier 2 mi? Kullaniciya sor: "Tier 2 mi 3 mu, plan yazayim mi?"
Acil bypass (kural ihlali, session_log'a yaz): FIFO_TIER3_SKIP=1
MSG
exit 2
