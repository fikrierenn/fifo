# Build Et ve Hata Duzelt

.NET projesini build eder, hata varsa duzeltir.

## Arguman
$ARGUMENTS — proje yolu (varsayilan: app/)

## Gorev
1. Build calistir:
```bash
cd D:/Dev/fifo/$ARGUMENTS && dotnet build --nologo 2>&1
```

2. Hata varsa:
   - Hata mesajini oku
   - Ilgili dosyayi ac
   - Duzelt
   - Tekrar build et
   - 0 hata olana kadar tekrarla

3. Uyari varsa:
   - Nullable, unused variable gibi uyarilari duzelt
   - CS8618, CS0168 gibi yaygın uyarilari handle et

4. Basarili build sonrasi:
   - Dosya sayisi ve proje ozeti goster

## Kurallar
- 3 denemede duzeltemezse kullaniciya sor
- Her duzeltmeyi acikla (1 cumle)
