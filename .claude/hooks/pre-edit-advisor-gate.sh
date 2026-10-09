#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# DANISMAN KAPISI — PreToolUse (matcher: Edit|Write|MultiEdit)
# Belinza `pre-edit-advisor-gate.sh`den uyarlandi.
#
# NEDEN VAR: "danis, sonra yaz" kurali metin olarak YETMEZ.
# 2026-09-10'da olculdu: master duzeltmesi `Yap` ile basladi, `Danis`
# atlandi. Sonuc uc kusur — ikinci yikici DROP, constraint/SP catismasi,
# reset dosyasindaki canli-DB silme tuzagi. Ucunu de SONRADAN kosturulan
# danismanlar buldu.
#
# NE YAPAR: bir alana BU OTURUMDA ILK dokunusta exit 2 ile BLOKLAR ve
# hangi danismana gidilecegini soyler. Danisildiktan sonra:
#     touch .claude/.advisor-marks/<alan>
#
# TASARIM NOTU (bel'den tasindi): yol cozumleme + esleme TEK python
# cagrisinda. Ters bolu sayisi KRITIK — JSON'dan gelen Windows yolu tek
# ters bolu tasir, python govdesinde IKI karakter yazilir. Yanlisi kapiyi
# SESSIZCE ACIK birakir; bir kapinin en kotu hali budur.
#
# BEL'IN ODEDIGI DERS: onceki surumde python hatasi `2>/dev/null` ile
# yutuluyordu ve kapi kuruldugu gunden beri 11 GUN HIC ATESLENMEDI.
# Burada hata GORUNUR (stderr'e yazilir) ama calismayi DURDURMAZ.
#
# Bypass: FIFO_ADVISOR_SKIP=1 -- kural ihlali, session_log'a yaz.
# ─────────────────────────────────────────────────────────────────────
set -u

[ "${FIFO_ADVISOR_SKIP:-0}" = "1" ] && exit 0

# KOK — WINDOWS bicimi SART (govde Windows python ile kosuyor; MSYS yolu
# `/d/Dev/fifo` acilamaz -> FileNotFoundError -> kapi sessizce acik kalir).
KOK="$(cd "$(dirname "$0")/../.." 2>/dev/null && { pwd -W 2>/dev/null || pwd; })" || exit 0
ESLEME="$KOK/.claude/advisor-map.conf"
[ -f "$ESLEME" ] || exit 0

HATA_DOSYA="$(mktemp 2>/dev/null || echo /tmp/adv-gate-$$)"

# Girdi yoksa kapi sessizce gecer: kapinin kendi hatasi yuzunden calismayi
# durdurmasi kabul edilemez.
GIRDI="$(cat 2>/dev/null)" || GIRDI=""
[ -z "$GIRDI" ] && { rm -f "$HATA_DOSYA" 2>/dev/null; exit 0; }

SONUC="$(printf '%s' "$GIRDI" | python -c '
import json, re, sys, pathlib

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = d.get("tool_input") or {}
yol = ti.get("file_path") or ti.get("filePath") or ""
if not yol:
    sys.exit(0)

# Bicimden bagimsiz: tek ters bolu -> ileri bolu (govdede IKI karakter).
yol = yol.replace("\\", "/")

# KAPSAM: kod yuzeyleri. docs/ raporlar/ plans/ *.md DISARIDA (bel dersi:
# gate-lemek surtunme uretir, ciktiyi degistirmez).
# NOT: bu govde python -c ile TEK TIRNAK icinde calisiyor --
# yorumlarda APOSTROF kullanilamaz, bash string-i kapatir.
m = re.search(r"((?:v2-production|tools|hangfire|\.claude/hooks|\.claude/commands)/.*)$", yol)
if not m:
    sys.exit(0)
rel = m.group(1)

conf = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
for satir in conf.splitlines():
    satir = satir.strip()
    if not satir or satir.startswith("#") or "|" not in satir:
        continue
    parcalar = [p.strip() for p in satir.split("|")]
    if len(parcalar) < 3:
        continue
    desen, danisman, alan = parcalar[0], parcalar[1], parcalar[2]
    try:
        if re.search(desen, rel):
            print(alan + "\t" + danisman + "\t" + rel)
            break
    except re.error:
        continue
' "$ESLEME" 2>"$HATA_DOSYA")"

# KAPININ KENDI HATASI GORUNUR OLSUN (bel: 11 gun sessiz kalmasinin sebebi).
if [ -s "$HATA_DOSYA" ]; then
  echo "uyari danisman kapisi CALISAMADI (kapi acik kaldi):" >&2
  head -3 "$HATA_DOSYA" >&2
fi
rm -f "$HATA_DOSYA" 2>/dev/null

[ -z "$SONUC" ] && exit 0

ALAN="$(printf '%s' "$SONUC" | cut -f1)"
DANISMAN="$(printf '%s' "$SONUC" | cut -f2)"
REL="$(printf '%s' "$SONUC" | cut -f3)"

# Yonlendirdigi ajan GERCEKTEN var mi (bel dersi 3: bos yere yonlendirme).
if [ ! -f "$KOK/.claude/agents/$DANISMAN.md" ]; then
  echo "uyari danisman kapisi: '$DANISMAN' ajani .claude/agents/ altinda YOK — esleme bozuk (advisor-map.conf)" >&2
  exit 0
fi

ISARET_DIZIN="$KOK/.claude/.advisor-marks"
mkdir -p "$ISARET_DIZIN" 2>/dev/null
[ -f "$ISARET_DIZIN/$ALAN" ] && exit 0

cat >&2 <<MSG

DANISMAN KAPISI — '$ALAN' alanina bu oturumda ilk dokunus
──────────────────────────────────────────────────────────
  Dosya: $REL

  Yazmadan ONCE danis:
    Agent(subagent_type: "$DANISMAN")

  Brifing 5 maddeyi tasisin (.claude/rules/danisman-brifingi.md):
    kapsam · erisim+tuzaklar · olcut · cikti bicimi · sinir

  Danistiktan sonra serbest birak:
    touch .claude/.advisor-marks/$ALAN

  Bu kapi, kuralin metin olarak YETMEDIGI icin var
  (.claude/rules/calisma-protokolu.md — 2026-09-10 dersi).

  Bypass (kural ihlali): FIFO_ADVISOR_SKIP=1
MSG

exit 2
