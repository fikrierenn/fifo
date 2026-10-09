# PLAN — <başlık>

**Tarih:** YYYY-MM-DD · **Tier:** 3 · **Durum:** Taslak

> `**Durum:**` satırı `tier3-plan-gate.sh` tarafından okunur.
> Taslak → **Onaylandı** (kullanıcı onayı sonrası) → Uygulamada → Tamamlandı.
> **Bitince güncelle.** Bayat plan, planın yokluğundan kötüdür.

## 1. Problem
Ne bozuk / ne eksik. **Ölçümle** yaz: kaç satır, kaç TL, hangi dosya:satır.
Çıkarımsa `ÇIKARIM` diye etiketle (`olctum-mu-cikardim-mi.md`).

## 2. Tier gerekçesi
`plan-first.md`deki hangi sinyal(ler) tetikledi:
- [ ] 1 · deploy scripti / master / build üretici
- [ ] 2 · `FifoKatman` / `FifoCikisDetay`'a yazan kod
- [ ] 3 · constraint / değişmez sıkılaşıyor ya da gevşiyor
- [ ] 4 · fallback kademesi / tier sırası / devre-dışı politikası
- [ ] 5 · uzun pipeline
- [ ] 6 · mali tabloya giden sayı
- [ ] 7 · prod cutover

## 3. Danışıldı mı (calisma-protokolu adım 1)
| Danışman | Ne soruldu | Kararı |
|---|---|---|
| `fifo-danisman` / `fifo-deploy-danismani` / `fifo-kapi-danismani` | | |

Danışılmadıysa **sebebini yaz**. "Unuttum" bir sebep değil.

## 4. Kapsam
### Dahil
### Hariç
### Etkilenen dosyalar / tablolar

## 5. Adımlar
1. [ ] **S1** …
2. [ ] **S2** …

Her adımın **kanıtı** ne olacak, yanına yaz.

## 6. Riskler
| Risk | Etki | Sessiz mi gürültülü mü | Mitigasyon |
|---|---|---|---|

> Sessiz risk gürültülüden tehlikelidir: deploy'u durduran hata görülür,
> sessizce silinen tablo görülmez.

## 7. Done kriterleri — ölçülebilir
- [ ] `SELECT COUNT(*) FROM FifoKatman WHERE BirimMaliyet <= 0` → **0**
- [ ] `SELECT COUNT(*) FROM FifoCikisDetay WHERE BirimMaliyet <= 0` → **0**
- [ ] `/fifo-dogrula` C1–C7 yeşil
- [ ] Ocak referans mutabakatı (Gelir / SMM / Brüt / marj) — sapma açıklanmış
- [ ] Deploy dokunulduysa: **dolu DB'ye** deploy + canary hayatta
- [ ] Kapı dokunulduysa: bilerek bozuldu, **kırmızı görüldü**, geri alındı

## 8. Smoke (calisma-protokolu adım 4)
Nerede GÖRDÜM — çıktıyla. "Derlendi" yetmez.

## 9. Rollback
Yanlış giderse nasıl dönülür. Yedek alındı mı, restore denendi mi.

## 10. İlişkili
`fifo-domain.md` · `plan-first.md` · ilgili SP/dosya
