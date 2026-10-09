# Yama Hedefini Doğrula — düzelttiğin şey gerçekten orada mı

_Belinza `yama-hedefi-dogrulama.md`den alındı. Genel hâli aynen geçerli;
**vaka FIFO'dan**._

## Olan (2026-09-10, ölçüldü)

Master deploy scriptinin maliyet defterini silmesi bulundu ve düzeltildi:
`01_V2_Tables.sql` tamamen `IF OBJECT_ID(...) IS NULL CREATE TABLE` desenine
çevrildi. Doğrulama yapıldı ve **geçti**:

```
master DROP TABLE dbo.Fifo/Maliyet sayisi (0 olmali): 0
```

Sonra boş bir veritabanına iki kez deploy edildi, canary satırı hayatta kaldı,
"veri kaybı kusuru kapandı" denildi.

**Kapanmamıştı.** Aynı kusurdan ikincisi `12_V2_OrtalamaAylikMaliyet.sql`
içinde duruyordu:

```sql
IF OBJECT_ID('dbo.OrtalamaAylikMaliyet', 'U') IS NOT NULL
    DROP TABLE dbo.OrtalamaAylikMaliyet;
```

Doğrulama komutu onu **kaçırdı** çünkü deseni `dbo.Fifo` ve `dbo.Maliyet`
öneklerini arıyordu; tablonun adı `OrtalamaAylikMaliyet` ile başlıyor.
Canary testi de kaçırdı çünkü o tablo lokalde **boştu** — silinecek bir şey
yoktu, dolayısıyla kayıp görünmedi.

Bulan: bağımsız bir danışman ajanı.

## Kural

> Bir düzeltme yazıldığında, hedeflediği desenin **kod tabanında gerçekten
> ve tamamen** kapsandığı aynı oturumda doğrulanır. Dar desen, geçmiş bir
> doğrulamayı **yalancı yeşil** yapar.

Bu vakada doğru desen şuydu:

```bash
grep -cE '^[[:space:]]*DROP TABLE dbo\.' master.sql   # onek varsaymaz
```

Sonuç sıfır olmalıydı; dar desenle sıfır göründü, geniş desenle 1 çıktı.

## Genişletilmiş hâli

| Yama türü | Doğrulama |
|---|---|
| Bir SQL antipattern'i temizlendi | deseni **önek varsaymadan** tüm dosyalarda ara; tek dosyada düzeltmek yetmez |
| Bir SP'ye koruma eklendi | **kardeş SP'de** aynı koruma var mı (`02` ↔ `14` aynı işi iki kez yapıyor) |
| Bir constraint kondu | o tabloya yazan **tüm** kod yolları ihlal edebilir mi |
| Build scriptine kapı eklendi | kapı **kırılabiliyor mu** — bilerek boz, kırmızı gör, geri al |
| Bir kolon SELECT'e eklendi | pozisyonel eşleme yapan taraf **aynı sıraya** eklendi mi |
| Doküman güncellendi | anlattığı dosya/dizin **hâlâ var mı** |

## Neden bu sınıf pahalı

Yama **hata vermez**. Deploy 0 hatayla geçer, test yeşildir, sayfa açılır.
Yalnızca beklenen koruma gelmez — ve o an insan sebebi başka yerde arar.
Bu, bu deponun "sessiz hata" dediği sınıfın tam örneği: yanlış olan sonuç
değil, **sebep atfı**.

## Genel hâli

> **Olumlu bir iddia olmadan, olumsuz bir iddia kanıt değildir.**

*"`DROP TABLE` bulamadım"* bir yokluk iddiasıdır. Aradığım desenin, aramadığı
bir şeyi de bulabildiğini göstermedikçe kanıt değildir.

Sınama: *"bu doğrulamayı, kusurun hiç düzeltilmediği bir dünyada da geçer
miyim?"* Geçiyorsam ölçtüğüm şey iddiam değildir.

Canary testi bu sınamadan **kaldı**: `OrtalamaAylikMaliyet` boş olduğu için
kusur düzeltilmemiş dünyada da canary hayatta kalırdı.

## Ne zaman tetiklenir

Bir kusur sınıfı temizlenirken; bir kapı yazılırken; ve özellikle
**"aynı şeyden başka yerde var mı"** sorusunun sorulmadığı her düzeltmede.

## İlişkili
- `olctum-mu-cikardim-mi.md` — kapsam eşleşmesi
- `dogrulama-siniri.md` — çelişki mi eksiklik mi
