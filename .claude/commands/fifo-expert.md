# FIFO Maliyetlendirme Uzmanı

FIFO katman yaşam-döngüsü ve maliyet hesaplama hakkında soruları yanıtla, analiz yap. **Bu dosyadaki her olgu v2-production/ kodundan doğrulanmıştır (memory/eski-doküman değil).** Cevap verirken kodu oku, dosya:satır göster; memory'e körü körüne güvenme.

## Argüman
`$ARGUMENTS` — soru/analiz türü. Örnekler:
- `katman yasam dongusu` — KaynakTip × Durum tam matrisi
- `katman durumu <StkId>` — ürün için katman analizi (lokal DB)
- `cikis nasil tuketir` — FIFO çıkış interval-intersection mantığı
- `acilis fallback` — 5 kademeli açılış fallback zinciri
- `sentetik ne zaman` — SENTETIK_ALIS katman koşulu
- `sorunlu stoklar` — SorunTipi dağılımı
- `mekan kapsam` — açılış/çıkış/ortalama mekan tutarsızlığı

## KATMAN KAYNAK TİPLERİ (koddan doğrulanmış — TEK GERÇEK)
> `FATURA` diye bir KaynakTip **YOKTUR** (eski skill/schema.md hatası). Çıkış tüketim filtresi: `KaynakTip IN ('ACILIS','ACILIS_TAMAMLA','ALIS','AYLIK_DEVIR','SENTETIK_ALIS')` — [02:865](../../v2-production/02_V2_CoreProcedures.sql).

| KaynakTip | Nerede yazılır | Durum değer(ler)i | Anlam |
|-----------|----------------|-------------------|-------|
| `ACILIS` | 02 `sp_Fifo_AcilisMaliyetlendir`, 14 `..._V2` | `NORMAL` | Açılış ters-FIFO katmanı (gerçek alış fiyatı) |
| `ACILIS_TAMAMLA` | 02, 14 | `TAMAMLAMA` (son alış) · `MERKEZ_TAMAMLAMA` (mekan 12) · `SART_TAMAMLAMA` (son geçerli fiyat) | Açılışta eksik miktar tamamlama |
| `AYLIK_DEVIR` | 02, 14 | `AYLIK_DEVIR` · `FIYAT_YOK` · `SABIT_FIYAT_TAMAMLAMA` | Çok eski stok için geçmiş ay devri |
| `ALIS` | 02 `sp_Fifo_AlisKatmanEkle` ([02:772](../../v2-production/02_V2_CoreProcedures.sql)) | `NORMAL` | Aylık alış faturası katmanı (fat+fatAyr, eTip 0/2) |
| `SENTETIK_ALIS` | 04 `sp_Fifo_SentetikKatmanOlustur` | `HAYALI_SART` · `HAYALI_SABIT` · `HAYALI_FIYAT_YOK` | STOK_YETERSIZ için hayali katman |

## KATMAN YAŞAM DÖNGÜSÜ
```
OLUŞUM                                    TÜKETİM
─────────                                 ───────
ACILIS (ters-FIFO, en yeni alıştan        sp_Fifo_CikisMaliyetle:
geriye stok dolana dek)          ─┐        - satış irs+irsAyr (eTip 1,4,5,100,101)
ACILIS_TAMAMLA (5-kademe fallback)│         NOT irsHrk! [02:882]
AYLIK_DEVIR (eski stok)           ├─► FifoKatman ─► - kümülatif interval-intersection
ALIS (aylık fat faturaları)       │    KalanMiktar    cikisMiktar=MIN(layerEnd,satEnd)
SENTETIK_ALIS (yetersiz stok)    ─┘                    -MAX(layerStart,satStart) [02:953]
                                                      - FIFO sıra: fifoSiraTarihi,
                                                        fifoSiraBelgeNoNum, girisBelgeNo, KatmanId
                                                      - KalanMiktar -= tüketim [02:1025]
                                                      - FifoCikisDetay'a yaz
```
- **GirisMiktar** sabit; **KalanMiktar** çıkışla düşer. CHECK: `0 <= KalanMiktar <= GirisMiktar` ([01:39](../../v2-production/01_V2_Tables.sql)).
- **Mekan-agnostik**: tüketim `PARTITION BY StkId` — mekan YOK ([02:900]). Satışın MekanId'si FifoCikisDetay'a yazılır ama katman global tüketilir.
- **Rerun-safe**: aynı dönem çıkışı önce KalanMiktar'a geri yüklenir, sonra yeniden hesaplanır ([02:839]).

## AÇILIŞ 5 KADEMELİ FALLBACK (eksik miktar için, sırayla)
1. Son alış fiyatı (aynı ürün) → `TAMAMLAMA`
2. Merkez depo (mekan 12) son alış → `MERKEZ_TAMAMLAMA`
3. Son geçerli fiyat (`fn_SonGecerliFiyat`) → `SART_TAMAMLAMA`
4. Aylık devir (geçmiş ay stok×fiyat) → `AYLIK_DEVIR` / `FIYAT_YOK`
5. Sabit fallback param → `SABIT_FIYAT_TAMAMLAMA`
Hiçbiri yoksa → `FifoSorunluStoklar.ALIS_YOK`.

## SORUN TİPLERİ (FifoSorunluStoklar.SorunTipi — koddan)
`ALIS_YOK` · `ALIS_YOK_MERKEZ_TAMAMLANDI` · `ALIS_YOK_SONGECERLI_TAMAMLANDI` · `ALIS_EKSIK_TAMAMLANDI` · `STOK_YETERSIZ` · `SENTETIK_FIYATLANDI` · `SENTETIK_FIYAT_YOK` · `FIYAT_YOK` · `SABIT_FIYAT_TAMAMLANDI` · `PROSEDUR_HATASI`.

## BİLİNEN RİSKLER (memory/fifo_logic_findings.md — doğrula)
- **Mekan kapsam driftı**: V2 açılış (14) mekan-12 hariç, çıkış (02) mekan-12 dahil, ortalama (12) filtresiz → mekan-12 STOK_YETERSIZ. `/fifo-dogrula` C7.
- **IADE**: KalanMiktar düşürür (geri eklemez); gün-içi netlenir.
- **SatisTutar**: çıkış SP'si yazmaz, yalnız 19 backfill doldurur → yeni çıkışlarda NULL.

## GÖREV
1. Soruyu anla → ilgili SP'yi OKU (`v2-production/02,04,12,14`), iddiayı koddan doğrula.
2. Veri gerekirse **LOKAL DB** (canlı sıkıntılı — `memory/feedback_local_db.md`):
   `cd D:/Dev/fifo && dotnet run --project D:/Dev/sqlcli -- query "<SORGU>"`
3. Katman analizi: `vw_Fifo_KatmanDurumu`, `vw_Fifo_AySonuBirimMaliyet`; invariant: `/fifo-dogrula`.
4. 1 cümle özet + kanıtlı detay (dosya:satır / tablo). Emin değilsen "DOĞRULANMADI" de.

## İlişkili
- `memory/semantic_layer.md` — FIFO akışı (§3, §10 KaynakTip/Durum doğru)
- `memory/fifo_logic_findings.md` — invariant + risk
- `.claude/commands/fifo-dogrula.md` — çalıştırılabilir doğrulama
- `.claude/agents/sql-sp-reviewer.md` — derin SP iş-doğruluğu denetimi
