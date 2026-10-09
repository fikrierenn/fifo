#!/usr/bin/env bash
# FIFO post-edit antipattern UYARISI — PostToolUse hook (Edit|Write|MultiEdit).
#
# ==== NEDEN VAR (2026-09-10'da OLCULDU) ====
#
# Tek oturumda asagidaki kusurlarin hepsi uretildi ya da yillardir kodda
# duruyordu; hicbirini derleme, hicbirini "master 0 hata ile deploy oldu"
# yakalamadi. Yakalayan sey: satir satir okuma ve DOLU veritabaninda kosum.
#
#   1. `00_V2_MASTER_FULL.sql` uretim deploy'unda 7 cekirdek tabloyu
#      kosulsuz DROP ediyordu (FifoKatman = maliyet defteri dahil).
#      Ikinci deploy tum SMM defterini silerdi. "Idempotent" saniliyordu.
#   2. AYNI kusurdan ikincisi `12_V2`de duruyordu (OrtalamaAylikMaliyet).
#      Tablo lokalde BOS oldugu icin ilk duzeltme turunda GOZDEN KACTI.
#   3. `14_V2`de uc CATCH blogu `GOTO` ile disari ciktiktan SONRA
#      ERROR_MESSAGE() cagiriyordu -> CATCH disinda NULL doner -> hata
#      metni komple kayboluyordu.
#   4. `'metin ' + @ErrorMessage` -> @ErrorMessage NULL ise TUM metin NULL.
#   5. `14_V2` aylik devir katmanini `ISNULL(...,0)` ile FILTRESIZ yaziyordu;
#      kardes SP `02_V2`de ayni yerde `WHERE BirimMaliyet > 0` VARDI.
#      Sikilastirilan CHECK ile bu satir 547 verip acilisi komple durdurur.
#   6. `02_V2`de son-alis ve merkez kademelerinde ayni koruma YOKTU.
#   7. `tools/build-master.sh` 02'yi SATIR NUMARASI ile dilimliyordu
#      (`sed -n '1,1502p;1533,1573p'`). Kaynaga 9 satir eklenince dilim
#      kaydi, master YARIM prosedurle uretildi.
#   8. `THROW`dan onceki ifade `;` ile bitmiyordu -> "Incorrect syntax
#      near 'THROW'". Deploy testinde yakalandi.
#   9. `set -e` altinda `grep -q ... && fail ...` yazildi; grep'in
#      BULAMAMASI (istenen durum) betigi sessizce 1 ile dusurdu.
#
# BLOKLAMAZ (daima exit 0). Gercek kapilar: `tools/build-master.sh`
# dogrulamalari, dolu-DB kosumu, `/fifo-dogrula` C1-C8.
#
# ==== YANLIS ALARM = KAPI YOK'TAN KOTUDUR ====
# Yanlis alarm, uyariyi gormezden gelmeyi ogretir. Bu yuzden:
#   * yorum satirlari ayiklanir (kuralin kendi aciklamasi bulgu sanilmasin),
#   * temp tablo DROP'lari (`#tablo`) kalici DROP sayilmaz,
#   * `RESET` adli dosyalar yikici olmaya YETKILIDIR, taranmaz.
#
# Env: CLAUDE_POSTEDIT_SKIP=1 -> atla.

[ "${CLAUDE_POSTEDIT_SKIP:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null)

# YOL COZUMLEME — python ile (tier3-plan-gate ve advisor-gate ile AYNI desen).
#
# OLCULDU 2026-09-11: bu makinede `jq` YOK ve sed-yedegi JSON kacislarini
# COZMUYOR. Gercek istemci Windows yolunu `D:\\Dev\\fifo\\...` diye yollar;
# sed onu `D:\\Dev\\...` olarak birakir, `-f` basarisiz olur ve kanca HIC
# KONUSMADAN olur. Bel deposunda ayni ariza kipi bir kapiyi 11 gun olu tuttu.
# Python hem kacisi cozer hem MSYS'in anlayacagi bicime cevirir.
f=""
if command -v python >/dev/null 2>&1; then
  f=$(printf '%s' "$input" | python -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("girdi JSON parse edilemedi: %s" % e, file=sys.stderr)
    sys.exit(0)
p = ((d.get("tool_input") or {}).get("file_path")
     or (d.get("tool_input") or {}).get("filePath") or "")
if not p:
    sys.exit(0)
p = p.replace("\\", "/")
# D:/... -> /d/...  (MSYS bicimi; `-f` testi boyle calisir)
if len(p) > 2 and p[1] == ":" and p[2] == "/":
    p = "/" + p[0].lower() + p[2:]
print(p)
' 2>/dev/null)
elif command -v jq >/dev/null 2>&1; then
  f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
fi

[ -z "$f" ] && exit 0
# SESSIZ CIKMA. `f` dolu ama dosya cozulemiyorsa (Windows ters bolu, jq yok,
# kacis cozulmedi) kanca hic konusmadan olur — bel deposunda ayni ariza kipi
# bir kapiyi 11 GUN olu tuttu. Calismayi durdurma, ama SUSMA.
if [ ! -f "$f" ]; then
  echo "uyari post-edit kancasi: dosya cozulemedi ($f) — tarama YAPILMADI" >&2
  exit 0
fi
case "$f" in
  *.sql|*.sh|*.cs|*.cshtml) ;;
  *) exit 0 ;;
esac

warns=()

# ============================================================== SQL ====
if [[ "$f" == *.sql ]]; then

  # Yorumsuz govde: kural metni kendi aciklamasini bulgu sanmasin.
  govde=$(sed -E 's|--.*||' "$f" 2>/dev/null)

  # ---- 1) KALICI TABLO DROP (olculdu: master maliyet defterini siliyordu)
  # `RESET` dosyalari yikici olmaya YETKILI; onlar haric.
  # MUAFIYET YALNIZ `*_RESET.sql` SONEKI (buyuk-kucuk duyarsiz).
  # Eski hali `*RESET*|*reset*` idi ve iki yonden de hataliydi:
  #   - `*Reset*` (karisik) muaf DEGILDI -> surekli yanlis alarm
  #   - `Preset`, `FiyatResetKontrol.sql` gibi YIKICI OLMAYAN isimleri muaf
  #     tutuyordu -> rastgele bir isimle kural susturulabiliyordu.
  case "$(basename "$f" | tr 'A-Z' 'a-z')" in
    *_reset.sql) ;;
    *)
      # KAPSAM: kural yalniz DEPLOY EDILEN agacta anlamli. Kapinin iddiasi
      # ("uretim deploy scriptine girmez") zaten YOLA dairdir.
      # `.demo/` (lokal ERP taklidi kuran scriptler, yikici olmak isleri) ve
      # `arsiv/` (olu kod) haric tutulur — olculdu: 6 mesru yikici script var,
      # kapsam daraltilmazsa ilk gun 6 yanlis alarm ve uyari korlugu.
      # NOT: `break` bir `case` icinde GECERSIZDIR (dongu ifadesidir) — ilk
      # yazimda oyle yazildi ve kapsam kontrolu SESSIZCE islevsizdi. Bayrak kullan.
      kapsamda=0
      case "$f" in
        */v2-production/*|*/SQL-Improvements/*) kapsamda=1 ;;
      esac
      # DESEN SATIR BASINA CAPALANMAZ, ONEK VARSAYMAZ.
      # Gercek bicimi: `IF OBJECT_ID('dbo.X','U') IS NOT NULL DROP TABLE dbo.X;`
      # DISLAMA DEGIL KALINTI SAYIMI: once temp (#) formlarini sil, kalan
      # her DROP TABLE kalicidir (build-master.sh ile ayni mantik).
      if [ "$kapsamda" = "1" ] && printf '%s' "$govde" \
         | sed -E 's/DROP[[:space:]]+TABLE[[:space:]]+(IF[[:space:]]+EXISTS[[:space:]]+)?#[A-Za-z0-9_#$]*//g' \
         | grep -qiE 'DROP[[:space:]]+TABLE' ; then
        warns+=('KALICI `DROP TABLE` -> uretim deploy scriptine GIRMEZ. Idempotent kalip: `IF OBJECT_ID(...) IS NULL CREATE TABLE`. Yikici sifirlama ayri `*_RESET.sql` dosyasinda ve onay degiskeniyle.')
      fi ;;
  esac

  # ---- 2) CATCH'ten GOTO ile cikis (olculdu: hata metni NULL oldu)
  if printf '%s' "$govde" | grep -qiE 'BEGIN[[:space:]]+CATCH' \
     && printf '%s' "$govde" | grep -qiE '^[[:space:]]*GOTO[[:space:]]+[A-Za-z_]'; then
    warns+=('CATCH blogunda `GOTO` var -> ERROR_MESSAGE()/ERROR_LINE()/ERROR_NUMBER() CATCH DISINDA **NULL** doner. Degerleri CATCH icinde degiskene AL, sonra atla.')
  fi

  # ---- 3) ERROR_*() ile DECLARE, bir GOTO etiketinden SONRA
  if awk 'BEGIN{IGNORECASE=1}
          /^[[:space:]]*[A-Za-z_]+:[[:space:]]*$/ { etiket=1 }
          etiket && /ERROR_(MESSAGE|LINE|SEVERITY|STATE|NUMBER)[[:space:]]*\(/ { bulundu=1 }
          END { exit !bulundu }' "$f" 2>/dev/null; then
    warns+=('GOTO etiketinden SONRA `ERROR_*()` cagriliyor -> CATCH disinda NULL doner, log bos yazilir.')
  fi

  # ---- 4) '+' ile hata metni birlestirme (olculdu: NULL tum metni yuttu)
  printf '%s' "$govde" | grep -qE "'[^']*'[[:space:]]*\+[[:space:]]*@Err" \
    && warns+=('`metin  + @ErrXxx` birlestirmesi -> degisken NULL ise TUM ifade NULL olur ve log BOS kaydedilir. CONCAT() ya da ISNULL(@x, N-isaret) kullan.')

  # ---- 5) FifoKatman'a maliyet yazarken sifir koruma yok (olculdu: CRIT-1/CRIT-3)
  if printf '%s' "$govde" | grep -qiE 'INSERT[[:space:]]+INTO[[:space:]]+dbo\.FifoKatman'; then
    printf '%s' "$govde" | grep -qiE 'ISNULL[[:space:]]*\([^,]*BirimMaliyet[^,]*,[[:space:]]*0[[:space:]]*\)' \
      && warns+=('FifoKatman INSERT icinde `ISNULL(BirimMaliyet, 0)` -> FIYAT 0 OLAMAZ (fifo-domain §6). CHECK constraint bunu 547 ile reddeder ve tum kosuyu durdurur. Fiyatsiz satiri YAZMA, sonraki kademeye birak.')
    printf '%s' "$govde" | grep -qiE 'BirimMaliyet[[:space:]]*>[[:space:]]*0' \
      || warns+=('FifoKatman INSERT var ama dosyada `BirimMaliyet > 0` korumasi GORUNMUYOR -> §6 kapisi. Kaynak kademeyi `WHERE ... BirimMaliyet > 0` ile suz.')
  fi

  # ---- 6) THROW oncesi `;` yok (olculdu: "Incorrect syntax near 'THROW'")
  if awk 'BEGIN{IGNORECASE=1}
          { satir=$0; sub(/--.*/,"",satir); gsub(/^[[:space:]]+|[[:space:]]+$/,"",satir)
            if (satir ~ /^THROW/) { if (onceki != "" && onceki !~ /;$/) { bulundu=1 } }
            if (satir != "") onceki=satir }
          END{ exit !bulundu }' "$f" 2>/dev/null; then
    warns+=('`THROW` oncesindeki ifade `;` ile bitmiyor -> "Incorrect syntax near ''THROW''". `END CATCH;` gibi noktali virgul ekle.')
  fi

  # ---- 7) RAISERROR (proje kurali: THROW)
  printf '%s' "$govde" | grep -qiE 'RAISERROR[[:space:]]*\(' \
    && warns+=('`RAISERROR` -> proje kurali `THROW`. RAISERROR orijinal hata numarasini 50000 yapar ve zinciri koparir.')

  # ---- 8) SELECT * (olculdu: 04 DryRun kolon uyusmazligi)
  printf '%s' "$govde" | grep -qiE 'SELECT[[:space:]]+\*[[:space:]]+INTO' \
    && warns+=('`SELECT * INTO` -> kolon eklenince INSERT-EXEC ve arayan taraf SESSIZCE kirilir. Kolonlari acik yaz.')

  # ---- 9) NOLOCK (yeni kodda yasak; mevcutlar bilincli korunuyor)
  printf '%s' "$govde" | grep -qiE 'WITH[[:space:]]*\([[:space:]]*NOLOCK' \
    && warns+=('`NOLOCK` -> yeni kodda yasak (kirli okuma maliyet defterini sessizce degistirir). Mevcut SP kullanimlari bilincli korunuyor.')

  # ---- 10) MERGE (proje kurali: DELETE + INSERT)
  printf '%s' "$govde" | grep -qiE '^[[:space:]]*MERGE[[:space:]]+' \
    && warns+=('`MERGE` -> proje kurali `DELETE` + `INSERT`.')

  # ---- 11) Yeni SP'de XACT_ABORT / TRY-CATCH eksik
  if printf '%s' "$govde" | grep -qiE 'CREATE[[:space:]]+OR[[:space:]]+ALTER[[:space:]]+PROCEDURE'; then
    printf '%s' "$govde" | grep -qiE 'SET[[:space:]]+XACT_ABORT[[:space:]]+ON' \
      || warns+=('SP var ama `SET XACT_ABORT ON` yok.')
    printf '%s' "$govde" | grep -qiE 'BEGIN[[:space:]]+TRY' \
      || warns+=('SP var ama `TRY/CATCH` yok.')
  fi

  # ---- 12) Mekan havuzu eksik (fifo-domain §1)
  if printf '%s' "$govde" | grep -qiE 'ehMekan[[:space:]]+IN[[:space:]]*\('; then
    printf '%s' "$govde" | grep -qE 'ehMekan[[:space:]]+IN[[:space:]]*\([[:space:]]*1[[:space:]]*,[[:space:]]*12[[:space:]]*,[[:space:]]*4477[[:space:]]*,[[:space:]]*4478' \
      || warns+=('`ehMekan IN (...)` havuz seti `1, 12, 4477, 4478` DEGIL -> mekan 12 ANA DEPO, disarida birakilamaz (fifo-domain §1). Acilis/cikis/ortalama AYNI seti kullanmali.')
  fi

  # ---- 13) Bolme var, NULLIF yok
  if printf '%s' "$govde" | grep -qE '(SUM|COUNT|CAST)[^,;]*/[[:space:]]*(SUM|COUNT|[a-z]+\.)' ; then
    printf '%s' "$govde" | grep -qi 'NULLIF' \
      || warns+=('bolme var ama `NULLIF(payda, 0)` gorunmuyor -> sifira bolme TUM sorguyu dusurur ve sessiz bos cikti birakir.')
  fi
fi

# ======================================================== shell/build ====
if [[ "$f" == *.sh ]]; then

  # ---- 14) Satir numarasiyla kaynak dilimleme (olculdu: master yarim uretildi)
  grep -qE "sed[[:space:]]+-n[[:space:]]+['\"][0-9]+,[0-9]+p" "$f" 2>/dev/null \
    && warns+=('`sed -n "N,Mp"` ile SATIR NUMARASI dilimleme -> kaynak dosyaya tek satir eklenince dilim kayar ve cikti SESSIZCE bozulur. Isim/desen bazli cikar (awk).')

  # ---- 15) `set -e` altinda `grep -q ... && ...` (olculdu bugun)
  if grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e' "$f" 2>/dev/null; then
    grep -qE 'grep[[:space:]]+-[a-zA-Z]*q[^|]*&&' "$f" 2>/dev/null \
      && warns+=('`set -e` altinda `grep -q ... && ...` -> grep BULAMAZSA (cogu zaman istenen durum) betik sessizce 1 ile duser. `if grep -q ...; then ...; fi` kullan.')
    grep -qE '^[[:space:]]*[A-Z_]+=\$\(grep[[:space:]]+-[a-zA-Z]*c[^)]*\)[[:space:]]*$' "$f" 2>/dev/null \
      && warns+=('`set -e` altinda `X=$(grep -c ...)` -> 0 eslesmede grep 1 doner ve betik duser. Sonuna `|| true` ekle.')
  fi
fi

if [ ${#warns[@]} -gt 0 ]; then
  echo "uyari post-edit ($f):" >&2
  for w in "${warns[@]}"; do echo "  ~ $w" >&2; done
  echo "  (uyari, blok degil -- gercek kapi: build-master dogrulamalari + dolu-DB kosumu + /fifo-dogrula)" >&2
fi

exit 0
