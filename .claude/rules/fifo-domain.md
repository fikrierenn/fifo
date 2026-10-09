# FIFO alan kuralları (yeniden yazım, 09.10.2026)

> Kaynak: `docs/yeniden-yazim/karar-olcumleri.md` (kararlar 1-16, ölçümleri ve gerekçeleri orada).
> Eski v2 kuralları (`eski/v2/.claude/rules/fifo-domain.md`) **geçersizdir**; oradan kural taşınmaz.

## 0. Şüphe, önce kanıt
Bir kural, kolon ya da kod değeri koda yazılmadan önce kaynağından (ERP, sema, ölçüm) doğrulanır.
Tahmin edilen değer "ÇIKARIM" diye işaretlenir; ölçülmüşse sorgusu yanında durur.

## 1. Havuz ve evren
- **Şirket geneli tek havuz.** Maliyet ürün başına (`stkID`) tek kuyrukta tutulur, mekan ayrımı yok.
- Havuz dışı: **26142** (İPTAL-Transfer, kalıntı), **4480** (İade Deposu, stoksuz iade çıkarır), **4835**.
  Bu mekanların bakiyesi ayrı bir "mutabakat bekleyen" raporunda gösterilir, havuza karışmaz.
- Mekanlar arası transfer (ehTip 8, 9, 11, 13) tek havuzda **yok sayılır**.
- Mal evreni: `urn.urnTip = 0` **yetmez**. Sahte ürünler (örn. "M", yemek bedeli, kafe, hediye çeki)
  elle tutulan **kara listeyle** dışarıda kalır. Listeye yalnız GMY ekler; motor şüpheliyi
  (tutarsız fiyat/adet) raporda **uyarı** olarak çıkarır, kendisi eklemez.

## 2. Hareket sınıfları (irsHrk.ehTip)
- **Tüketen:** 1, 4, 100 (satış) · 99(−) sayım eksiği · 90(−) · 96 bozuk · 98 iç kullanım · 92 boş paket ·
  95(−) dönüşüm çıkışı · 89 · 2 ve 12 (alış iadesi).
- **Katman açan:** 0, 10 (alış / yerel alım) · 88(+) · 16(+) Stok EKLE · 99(+) · 95(+) · satış iadeleri (3, 5, 101).
- Gider kovaları ayrı tutulur: SMM (satış) · sayım/fire · iç kullanım · bozuk.
- ⚠ **İki ayrı sözlük:** `irsTip_vw` (irsHrk.ehTip) ile `fatTip_vw` (fat.eTip) farklıdır.
  `ehTip 10` = Yerel Alım, `fat.eTip 10` = İade Fark Faturası. Biri diğerine kopyalanmaz.

## 3. İadeler ve fiyat düzeltmeleri
- **Alış iadesi:** `fatAyr.reffatId`'nin gösterdiği alış katmanından düşülür; değer **fatAyr birim
  fiyatı**dır. `irsHrk ehTip 12` tutarı fatura değeri DEĞİLDİR (ölçüldü: 12,25M ↔ 41,25M).
  `fat.eBagIade` kullanılmaz (iade faturalarında hep 0). Bağsız iade → en eski katman.
- **Satış iadesi:** aynı ürünün o ayki ortalama çıkış maliyetiyle geri girer; bağsız ya da eski dönem
  iadesi → son çıkış maliyeti. Gelir ters işaretle yazılır; `ehTip 3` dahildir.
- **İade fark faturası (`fat.eTip 10`):** `fatAyr.ehSipID` alış faturasının `eID`'sini gösterir
  (kolon adı yanıltıcı); o alış katmanının maliyetini düzeltir, katman tükendiyse fark SMM'ye.
- **Fiyat farkı (`fat.eTip 8`):** bağsızdır; ürünün açık katmanlarına adet oranıyla dağıtılır,
  tükenmiş kısım SMM'ye.

## 4. Hesap şekli
- **Sürekli, günlük FIFO.** Gün içi sıra aranmaz (POS satırı günlük toplamdır).
- Negatife düşen çıkış **bekleyen maliyet** kuyruğuna girer, sonraki alış geldiğinde o fiyatla kapanır.
- **Sentetik katman, sabit fiyat, satış fiyatı × oran YOK.** Maliyetsiz çıkış meşru bir durumdur ama
  her zaman ayrı kovada, sayılabilir ve etiketli görünür.
- Değeri 0 girişler (ehTip 16 Stok EKLE, Sahaf girişi): ürünün son alış birim maliyetiyle **bayraklı**
  katman; son alış yoksa "maliyetsiz" kovası.
- Grup içi alış (ODAK 9525, Bursa Kültür Merkezi 56 vb.) fatura fiyatıyla katmana girer;
  raporda ilişkili / dış alış ayrı kovadadır. Konsolide grup marjı motorun işi değildir.

## 5. Sınav süreli yayın paketleri
- FIFO **dışında**, ayrı modelde. Paket önce satılır, maliyeti sonradan aylık faturalarla parça parça gelir.
- Model satışı sonradan gelen faturalarla eşleştirir; satış ayında maliyet henüz belli olmayabilir.
- 01.08.2026 "SINAV OKULLARI" sayım çıkışı (İst.Yolu, −663.221 adet) paket maliyeti sayılır, fire değil.
  Bu modeldeki yeri **ölçülecek** (ÇIKARIM).

## 6. Açılış ve dönem
- Açılış tarihi **31.12.2025**, miktar ERP defterinden (Aralık 2025'te merkez depo WMS'e eşitlendi).
- Açılış değeri **ters FIFO** ile faturalardan. 153 Ticari Mallar (345.723.085,47 ₺) ile fark ve
  sebepleri açılış raporunda gösterilir; **düzeltme yapılmaz**.
- Kapanmış aya (`bkm.Fin_AyKapanis`) yazılmaz. Geç gelen belge, açık aya düzeltme olarak işlenir.

## 7. Değişmezler
Koşulabilir kurallar `sema/degismezler.json`'a yazılır ve `ork sema kostur` ile koşar.
Kırılabildiği (bilerek bozulunca kırmızı verdiği) gösterilmeden değişmez eklenmez.
