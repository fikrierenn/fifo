# Doğrulama Sınırı: Reddet mi, Say mı?

_Belinza `dogrulama-siniri.md`den alındı; ölçüt aynen geçerli, **vakalar
FIFO'dan yeniden kuruldu**._

## Ölçüt

> **REDDET** — durum **ÇELİŞKİLİYSE**. İki doğru bilgi aynı anda tutamıyorsa.
> **SAY** — durum **EKSİKSE**. Bilgi doğru ama tam değil.

Tek cümlede: **"bu iki şey aynı anda doğru olabilir mi?"** Olamazsa reddet.

## Neden

Çelişki bir VERİ durumu değil, bir **KOD hatasıdır**. Çalıştırmaya devam
etmek onu gizler — ve gizlenen kod hatası, bu deponun "sessiz yanlış kâr"
dediği sınıfın ta kendisidir.

Eksiklik ise meşru olabilir. Bir ürünün fiyatı kaynakta gerçekten yoksa
"eksik" tam budur: hiçbir şey çelişmiyor, bilgi yok. Reddetmek doğru veriyi
de atar.

## Örnekler — bu depodan

| Durum | Tanı | Karar |
|---|---|---|
| `FifoKatman.KalanMiktar > GirisMiktar` | "girdi 10" + "kalan 12" aynı anda doğru olamaz | **REDDET** (CHECK constraint patlatır) |
| `FifoCikisDetay.BirimMaliyet ≠ katmanın BirimMaliyet'i` | çıkış maliyeti katmandan KOPYALANIR; farklıysa kod hatası | **REDDET** (`/fifo-dogrula` C3) |
| Katman tüketimi ile `KalanMiktar` tutmuyor | defter mutabakatı; ikisi aynı anda doğru olamaz | **REDDET** (C1) |
| `BirimMaliyet <= 0` olan katman | §6 "fiyat 0 olamaz" ile çelişir | **REDDET** (constraint 547) |
| Çıkış var, katman yok (orphan) | çıkış bir katmana işaret ediyor, katman yok | **REDDET** (C4, FK) |
| `STOK_YETERSIZ` 550 ürün | ERP'de stok var, FIFO havuzunda yok — **eksiklik**, geçmiş alış verisi kısmi | **SAY** (sorunlu stok kaydı + sentetik katman) |
| `FIYAT_YOK` — kaynakta hiç fiyat yok | bilgi gerçekten yok, çelişki yok | **SAY** → sonraki kademe / imputation / devre-dışı |
| Ocak marjı referanstan %0,1 sapıyor | iki koşu farklı ERP anlık görüntüsü görmüş olabilir | **SAY** (açıkla, sebebini bul) |
| Ocak marjı referanstan %5 sapıyor | aynı kaynaktan aynı hesap iki farklı sonuç veremez | **REDDET** (kök neden bulunmadan rapor yok) |

## Deploy tarafındaki uygulaması (2026-09-10 kararı)

Constraint sıkılaştırma sırasında ihlal bulunursa:

- **Script PATLAMAZ** — DDL ortasında `THROW`, master'ı yarım deploy halinde
  bırakır (tablolar yeni, SP'ler eski) ve hangi sürümün çalıştığı belirsizleşir.
  Bu, veri kaybından farklı ama denetlenebilirlik açısından daha kötüdür.
- **Ama sessiz de kalmaz.** Uyarı `PRINT`'te bırakılmaz (otomasyonda
  `Invoke-Sqlcmd` verbose akışında kaybolur); `FifoSorunluStoklar`'a
  `CONSTRAINT_KURULAMADI` satırı yazılır — kalıcı denetim izi.
- **Mali kapı ayrıdır ve serttir.** Cutover bu uyarıda **DURUR**. "DDL çalıştı
  mı" ile "0 maliyetli satır var mı" iki farklı sorudur; ikincisi bir deploy
  adımı değil, bir **kapanış kapısıdır**.

## Sınırın bittiği yer

**Eksiklik çelişkiye döndüğü an.** O an sayma — reddet ya da tamamla.

Örnek: *"Ocak kapandı"* + *"Ocak çıkışlarının bir kısmı maliyetsiz"* çelişkidir.
Dönem kapandı denemez.

## Ne zaman tetiklenir

Bir doğrulama yazarken, bir constraint eklerken, `/fifo-dogrula`ya kontrol
eklerken, ve *"bu durumda ne yapmalı — uyar mı, dur mu"* sorusunun sorulduğu
her yerde. Cevap sezgiyle verilmez; yukarıdaki tek cümlelik testten geçirilir.

## İlişkili
- `fifo-domain.md` §6 — fiyat 0 olamaz
- `.claude/commands/fifo-dogrula.md` — C1-C8
- `error-handling.md` — beklenen sonuç vs gerçek hata
