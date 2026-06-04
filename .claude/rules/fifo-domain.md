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

## İlişkili
- `memory/fifo_logic_findings.md` — bulgular + kanıt
- `memory/local_demo_env.md` — ortam durumu
- `memory/feedback_local_db.md` — lokal DB kuralı
- `docs/DOGRULAMA_DEFTERI.md` — SP doğrulama + bug+fix kaydı
