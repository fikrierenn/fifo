# Deploy Öncesi Doğrulama

Deploy edilecek SQL dosyasını kontrol et.

## Argüman
$ARGUMENTS — dosya adı veya yolu (ör: `12_V2_OrtalamaAylikMaliyet.sql`)

## Görev
1. Belirtilen dosyayı oku (v2-production/ altında ara)
2. Şu kontrolleri yap:
   - `SET XACT_ABORT ON` var mı? (SP'lerde zorunlu)
   - `TRY/CATCH` pattern doğru mu?
   - `SELECT *` kullanılmış mı? (yasak)
   - `CREATE OR ALTER` idempotent mi?
   - Bağımlı objeler (FK, referans edilen tablo/SP) mevcut mu?
   - Index isimleri convention'a uyuyor mu? (IX_TabloAdi_KolonAdi)
3. `00_V2_Master_Deploy.sql` içinde `:r` satırı var mı kontrol et
4. `11_V2_SmokeTest.sql` içinde yeni objeler test ediliyor mu kontrol et

## Çıktı
- ✅ Geçen kontroller
- ❌ Başarısız kontroller + düzeltme önerisi
- ⚠️ Uyarılar (opsiyonel düzeltme)
