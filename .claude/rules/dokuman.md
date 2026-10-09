---
paths:
  - "**/docs/**/*.md"
  - "**/README.md"
  - "**/CHANGELOG.md"
---

# Doküman kuralları (özet — /dokuman, yazim-metin, docs/bilgi/14)

- Her sayfa tek Diátaxis türü: öğretici · nasıl yapılır · başvuru · açıklama. Görev adımlarının arasına kavram anlatımı gömülmez.
- `docs/yardim`, `docs/mimari`, `docs/isletim`, `docs/veritabani`, `docs/proje` altında künye zorunlu: `> Tür: … · Kaynak commit: … · İzlenen yollar: … · Son doğrulama: gg.aa.yyyy`.
- Her arayüz adı, alan, hata mesajı, sayı kaynağına (kod, `.resx`, `db/hata-kodlari.yaml`) birebir uyar; doğrulanmamış bilgi `[?] Doğrulanmadı:` ile işaretlenir.
- Yardım: hedef odaklı başlık, bir adım bir eylem, arayüz adı **kalın**, sonuç ve sorun giderme; ekran görüntüsünde gerçek kişi verisi yok.
- Türkçe: TDK yazımı, terim tutarlılığı, sayı 1.234,56, tarih gg.aa.yyyy, "Hata oluştu" gibi boş mesaj yok, yapay zekâ klişesi yok. CHANGELOG `[Yayımlanmamış]` altında kullanıcı etkisiyle.
- Kaydettiğin anda `dokuman_denetle.py` hook'u koşar (Vale kurallarıyla aynı kaynak).
