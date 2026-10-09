#!/usr/bin/env bash
# post-edit-antipattern.sh OZ-TESTI
#
# NEDEN VAR: bir kapinin kirilabildigi kanitlanmadan yazilmasi yasak
# (.claude/rules/semantic-layer.md, fifo-kapi-danismani). Bu betik iki yonu
# birden sinar:
#   kotu.sql -> 15 kuralin 15'i de ATESLENMELI (pozitif)
#   iyi.sql  -> SIFIR uyari cikmali          (negatif / yanlis-alarm regresyonu)
#
# NEGATIF FIXTURE ASIL ONEMLI OLANIDIR: yanlis alarm, uyariyi gormezden
# gelmeyi ogretir ve kapiyi olduren sey budur.
#
# Ayrica GERCEK istemci JSON bicimiyle beslenir (Windows ters bolulu yol).
# 2026-09-11'de olculdu: bu makinede `jq` YOK ve sed-yedegi JSON kacisini
# cozmuyordu -> kanca HIC KONUSMADAN oluyordu. Yalniz bu testle yakalanir.
#
# Cikis: 0 gecti · 1 KIRIK · 2 KOSAMADI (kosamamak YESIL degildir)
set -uo pipefail

KOK="$(cd "$(dirname "$0")/../.." && pwd)"
KANCA="$KOK/.claude/hooks/post-edit-antipattern.sh"
FIX="$KOK/tools/hook-selftest/v2-production"
BEKLENEN_KURAL=15

[ -f "$KANCA" ] || { echo "KOSAMADI: kanca yok: $KANCA" >&2; exit 2; }
command -v python >/dev/null 2>&1 || { echo "KOSAMADI: python yok" >&2; exit 2; }

gecici="$(mktemp -d)"; trap 'rm -rf "$gecici"' EXIT

json_uret() {  # $1 = fixture adi
  python - "$KOK" "$1" "$gecici" <<'PY'
import json, io, sys, os
kok, ad, hedef = sys.argv[1], sys.argv[2], sys.argv[3]
# MSYS yolunu GERCEK istemcinin yolladigi Windows bicimine cevir: /d/... -> D:\...
p = kok
if p.startswith("/") and len(p) > 2 and p[2] == "/":
    p = p[1].upper() + ":" + p[2:]
yol = (p + "/tools/hook-selftest/v2-production/" + ad + ".sql").replace("/", "\\")
io.open(os.path.join(hedef, ad + ".json"), "w").write(
    json.dumps({"tool_input": {"file_path": yol}}))
PY
}

hata=0

# ── POZITIF: kotu.sql tum kurallari atesLEMELI ──
json_uret kotu
cikti="$(bash "$KANCA" < "$gecici/kotu.json" 2>&1)"
n=$(printf '%s' "$cikti" | grep -c '^  ~ ' || true)
if printf '%s' "$cikti" | grep -q 'dosya cozulemedi'; then
  echo "KOSAMADI: kanca fixture yolunu cozemedi (jq/python/yol bicimi)" >&2
  printf '%s\n' "$cikti" >&2
  exit 2
fi
if [ "$n" -lt "$BEKLENEN_KURAL" ]; then
  echo "KIRIK: kotu.sql -> $n uyari, beklenen $BEKLENEN_KURAL" >&2
  printf '%s\n' "$cikti" >&2
  hata=1
else
  echo "GECTI  pozitif: kotu.sql -> $n uyari"
fi

# ── NEGATIF: iyi.sql HIC uyari vermemeli ──
json_uret iyi
cikti2="$(bash "$KANCA" < "$gecici/iyi.json" 2>&1)"
n2=$(printf '%s' "$cikti2" | grep -c '^  ~ ' || true)
if [ "$n2" -ne 0 ]; then
  echo "KIRIK: iyi.sql -> $n2 YANLIS ALARM (0 olmali)" >&2
  printf '%s\n' "$cikti2" >&2
  hata=1
else
  echo "GECTI  negatif: iyi.sql -> 0 yanlis alarm"
fi

[ "$hata" -eq 0 ] || exit 1
echo "kanca oz-testi GECTI (pozitif $n/$BEKLENEN_KURAL, negatif 0)"
exit 0
