# FIFO Domain & Demo Kuralları (ZORUNLU)

> Bu oturumda tekrar tekrar yapılan hataların kuralı. `paths:` yok — compact sonrası da geçerli.
> Kaynak: kullanıcı düzeltmeleri 2026-06-02. İhlal = kullanıcının işini sana yaptırmak.

## 1. İŞ KURALI — maliyet ortak havuz, satış mekan-bazlı
- Maliyet **mekan-bağımsız TEK ortak havuz** hesaplanır → FIFO çıkış `PARTITION BY StkId` (mekan YOK) = **doğru tasarım**, bug değil.
- Satış **mekan-bazlı** (FifoCikisDetay.MekanId), ortak maliyetle maliyetlenir → **karlılık mekan bazında**.
- Havuz TÜM mekanları kapsar: **`1, 12, 4477, 4478` + `ehAltDepo=0`**. Açılış snapshot, FIFO çıkış, ortalama ay-sonu stok HEPSİ aynı seti kullanmalı.
- **Mekan 12 = ANA DEPO** (en büyük stok ~6.3M), şube değil. Açılışta ASLA dışlama.

## 2. DEVRE DIŞI (FifoDevreDisiUrunler) — non-inventory dışlama
- **Kriter = İSİM/KATEGORİ bazlı** (poşet/ambalaj/gider): `stkAd LIKE '%Poşet%'/'%Poset%'/'%Ambalaj%'/'%Hediye Çeki%'/'%Madde Alımı%'/'%Geri Dönüşüm%'` VEYA `KatAna='Hediye Çeki'`. Bunların maliyeti 0, alışı gider yazılır → FIFO dışı.
- **YASAK kriter: `SonAlis=0` veya "alış yok"**. Gerçek kırtasiyenin çoğu SonAlış=0 ve fat'ta alışı yok ama fiyatı **fytOzl'den** gelir → FIFO'da KALIR (SART_TAMAMLAMA). SonAlış=0 ≠ non-inventory. Bu kriterle gerçek ürün dışlama.
- **Tablo KALICI + ADDITIVE**: `TRUNCATE`/`DELETE` YOK. Yeni non-inventory `INSERT ... WHERE NOT EXISTS` ile eklenir; eski kayıt silinmez. (İstisna: kendi hatanı düzeltirken yanlış eklediğini çıkarabilirsin.)
- Devre-dışı ürün envanter snapshot'ta KALIR (stok doğruluğu), sadece maliyet katmanı kurulmaz.

## 3. ŞÜPHE & DOĞRULA — sınıflandırma/dışlama önce kanıt
- Bir ürünü dışlamadan / "şu tür" demeden ÖNCE gerçek veriye bak (alış faturası, satış, kategori, isim). Kaba heuristik (SonAlış=0, "alışı yok") ile toplu işlem YASAK.
- Memory/yazılı-kod/eski-skill iddialarına körü körüne güvenme — koddan/veriden doğrula. (Bu oturumda KaynakTip 'FATURA' hatası, mekan kimliği hatası, devre-dışı kriteri hatası hep bundan.)

## 4. RERUN-SAFE (idempotency)
- Dönem yeniden işlenirken: katman silmeden ÖNCE o dönemin `FifoCikisDetay`'ını geri-yükle (KalanMiktar += tüketim) + sil. Yoksa `FK_FifoCikisDetay_FifoKatman` patlar (ALIS/ACILIS katmanı çıkış referanslı). Sıra: rollback → alış(+) → satış(−).
- **Açılış re-run**: önce FIFO çıktı tablolarını temizle (FifoCikisDetay → FifoKatman → FifoAcilisEnvanter → FifoSorunluStoklar). Sonraki döneme veri varken açılış re-run FK'ya takılır (`sp_Fifo_DonemKontrol` guard'ı kontrol eder).

## 5. LOKAL DEMO ORTAMI
- Çalışmalar **`BT-FIKRI`** (default instance, SQL Server 2022 **Developer Edition**, Windows auth — 10GB limit YOK). DB dosyaları **`D:\SQLData`**. Eski Express (`BT-FIKRI\SQLEXPRESS`) TERK edildi. Canlı `192.168.40.201` KULLANMA (ETL tohumlama hariç, tek-seferlik SELECT).
- ERP kaynak = **`DerinSIS_Local`** (DerinSISBkm DEĞİL — karışmasın). SP'ler repoint edildi.
- Deploy: `Invoke-Sqlcmd -ServerInstance 'BT-FIKRI' -InputFile`. Tek sorgu/SELECT: sqlcli + SQLCLI_CONN. sqlcmd.exe ODBC patlıyor (kullanma).
- ETL: `sqlcli copy --from <canlı> --to <lokal> --query ... --table ... --truncate` (cross-server SqlBulkCopy). sqlcli **D:/Dev/sqlcli'da** geliştirilir, fifo'ya kopyalanmaz.
- Scope: yıl **2026**, devir **2025-12-31**.

## 6. FİYAT 0 OLAMAZ — sıfır maliyet KESİNLİKLE yasak (kullanıcı kuralı 2026-06-19)
- **Hiçbir FifoKatman.BirimMaliyet = 0 (veya <0) kalamaz.** Stoğu olan her katman gerçek/fallback POZİTİF maliyet taşımalı. 0 maliyet = sessiz yanlış kâr (marj %100 görünür) → CFO raporunu bozar.
- **Kök neden (doğrulandı 19.06):** açılış tamamlama (`ACILIS_TAMAMLA`/Durum=`TAMAMLAMA`) "son alış"ı seçerken **0-değerli fatura satırını** (numune/hediye/düzeltme irsaliyesi — `ehTutarN=0`) kabul edip 0 kopyalıyor; aynı ürünün fatAyr'da sıfırdan farklı gerçek fiyatı VARKEN (10/12 vakada vardı: 24.65/80.64/77.60…) onu atlıyor.
- **Fix kuralı:** fallback/tamamlama fiyat seçimi DAİMA `ehAdetN<>0 AND ehTutarN<>0` (birim fiyat>0) ile filtrelenir — **0 fiyatlı kaynak "bulunamadı" sayılır, sonraki kademeye geçilir** (son alış → merkez → son geçerli satış → aylık devir → sabit). Hiçbir kademe pozitif bulamazsa `SABIT_FIYAT_TAMAMLAMA` (>0) veya `ManuelMaliyet` zorunlu; FIYAT_YOK/0 BIRAKILMAZ.
- **Doğrulama (rerun sonrası ZORUNLU geçer):** `SELECT COUNT(*) FROM FifoKatman WHERE BirimMaliyet<=0` → **0 dönmeli**. Aynı şekilde `FifoCikisDetay WHERE BirimMaliyet<=0` → 0. `/fifo-dogrula` C6 bu kapıyı kontrol eder.
- Gerçekten hiç fiyatı olmayan ürün (örn. 67903, 50911 — fatAyr'da nonzero yok) → kategori imputation veya elle ManuelMaliyet; 0 değil.

## İlişkili
- `memory/fifo_logic_findings.md` — bulgular + kanıt
- `memory/local_demo_env.md` — ortam durumu
- `memory/feedback_local_db.md` — lokal DB kuralı
- `docs/DOGRULAMA_DEFTERI.md` — SP doğrulama + bug+fix kaydı
