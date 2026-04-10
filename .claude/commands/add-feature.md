# Yeni Feature Ekle

Mevcut app'e yeni bir feature ekler. /new-page'den farki: birden fazla dosya, is mantigi, SP entegrasyonu.

## Arguman
$ARGUMENTS — feature aciklamasi. Ornekler:
- `batch-monitor "Batch calistirma izleme paneli"`
- `urun-detay "Tek urun icin katman/cikis/maliyet detayi"`
- `sorunlu-stoklar "Sorunlu stok listesi ve cozum onerileri"`

## Gorev
1. Feature'in ne yaptigini anla
2. Gerekli SP/view/tablo'lari belirle (semantic_layer.md ve schema.md oku)
3. Dosya listesi olustur:
   - PageModel (.cshtml.cs)
   - View (.cshtml)
   - Varsa ek DTO/service class'lari
4. Her dosyayi yaz
5. _Layout.cshtml sidebar'a link ekle
6. Build et (0 hata)
7. Eklenen dosyalari listele

## Kurallar
- Mevcut pattern'lere uy (Db, MaliyetLogger, Dapper, Tailwind)
- Yeni SP gerekiyorsa SQL dosyasini da yaz (v2-production/ altina)
- SELECT * YASAK
- Test edilebilir yaz (DI, async)

## Referanslar
- Mevcut feature'lar: app/Features/ altini tara
- SP'ler: memory/semantic_layer.md
- Tablo semasi: memory/schema.md
