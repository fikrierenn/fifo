# Kod Review

Belirtilen dosya veya dizini proje kurallarina gore review eder.

## Arguman
$ARGUMENTS — dosya yolu veya dizin. Ornekler:
- `app/Lib/Db.cs` — tek dosya
- `app/Features/Fifo/` — dizin
- `app/` — tum proje

## Kontrol Listesi
1. **CLAUDE.md kurallari**:
   - SELECT * kullanilmis mi? (YASAK)
   - Controller/API endpoint var mi? (YASAK)
   - Dapper kullaniliyor mu? (ZORUNLU)
   - Async/await dogru mu?

2. **Pattern tutarliligi**:
   - Db.cs ve MaliyetLogger.cs DI ile mi kullaniliyor?
   - Background islem pattern'i dogru mu? (Task.Run + MaliyetLogger)
   - Polling handler var mi? (OnGetDurumAsync)

3. **Guvenlik**:
   - SQL injection riski var mi? (parametreli sorgular mi?)
   - Connection string hardcoded mi?
   - Timeout ayarlanmis mi? (long-running SP'ler)

4. **Kod kalitesi**:
   - Gereksiz using var mi?
   - DTO property'leri dogru tiplenmis mi?
   - Null handling dogru mu?
   - Magic string/number var mi?

## Cikti
| Dosya | Sorun | Oncelik | Oneri |
|-------|-------|---------|-------|

Sonunda: toplam sorun sayisi ve genel degerlendirme.
