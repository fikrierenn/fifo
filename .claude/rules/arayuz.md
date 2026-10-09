---
paths:
  - "**/*.razor"
  - "**/*.cshtml"
  - "**/*.xaml"
  - "**/*.resx"
  - "**/wwwroot/**"
---

# Arayüz dosyası kuralları (özet — yazim-metin §3, docs/bilgi/07, 15)

- Kullanıcıya görünen metin `.resx`'te; kod/markup içine gömülü Türkçe metin yok.
- Buton fiil ve eylemi söyler ("Transferi kaydet"), başlık/buton cümle düzeninde, hata mesajı "ne oldu + nasıl düzelir", yıkıcı işlemde eylem adlı onay; teknik hata kodu kullanıcıya gösterilmez.
- Tasarım sistemi: yalnız token değerleri ve katalog bileşenleri (`docs/tasarim/`); katalog dışı bileşen = ADR.
- Erişilebilirlik (WCAG 2.2 AA): etiketli alanlar, klavye ile tam kullanım, görünür odak, yeterli kontrast, anlamlı erişilebilir adlar.
- Durumlar: boş, yükleniyor, hata, başarı, yetkisiz — hepsi tasarlanmış olmalı. İş kuralı UI'da değil servis katmanında.
