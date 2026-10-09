---
paths:
  - "**/tests/**"
  - "**/*.Tests/**"
  - "**/*.E2E/**"
  - "**/db/testler/**"
---

# Test dosyası kuralları (özet — test-hatti, kullanıcının test-discipline skill'i)

- Test yazan rol kodu, kod yazan rol testi değiştirmez (hook fiziksel olarak engeller). Kilitli test (`test-kilidi.json`) değişmez.
- İsim `Metot_Senaryo_Beklenen` / tSQLt `[test <senaryo> <beklenen>]`; AAA; bir test bir davranış; `[Trait("AC", "...")]` ile kabul kriterine bağ.
- Kırmızı doğru sebepten görülür (derleme hatası kırmızı sayılmaz). Testlerin en az %10'u "ne olmamalı"yı doğrular.
- Yasak: `Skip`/`Ignore` · assert'siz test · kendi kendini doğrulayan assertion · catch içinde assert · `Thread.Sleep`/`Task.Delay` ile bekleme · testte if/döngü · paylaşılan değişken durum · kendi kodunu mock'lamak (fake yaz).
- Gerçek SQL Server (test veritabanı / Testcontainers) mock'a tercih edilir; zaman `FakeTimeProvider`.
