# Kodlama Disiplini (Karpathy Prensipleri)

## Simplicity First — Spekülatif Kod Yasak

- İstenen dışında feature ekleme. "İleride lazım olur" gerekçesiyle abstraction yok.
- Tek kullanımlık kod için class/interface/strategy pattern çıkarma.
- İmkânsız senaryolar için error handling yazma (iç kodda framework garantilerine güven).
- 200 satır yazıp 50'ye düşürebiliyorsan → yeniden yaz.
- Test: "Kıdemli bir mühendis buna 'gereksiz karmaşık' der mi?" Evet → sadeleştir.

**YAPMA:**
```
// Kullanıcı "discount hesapla" dedi → Strategy pattern + factory + config sınıfı
```
**YAP:**
```
// 1 fonksiyon, 1 satır iş mantığı
```

## Surgical Changes — Sadece İstenen Satıra Dokun

- Bug fix yaparken komşu kodu "iyileştirme", yorum düzenleme, stil değiştirme yasak.
- Mevcut stili taklit et — farklı yapardın bile olsa.
- İlgisiz dead code fark edersen: **raporla, silme** (kullanıcı kararı).
- Senin değişikliğin yüzünden orphan kalan import/değişken/fonksiyonu sil. Önceden var olan dead code'a dokunma.

**Kontrol testi:** Her değiştirilen satır, kullanıcının talebine doğrudan izlenebilmeli. İzlenemiyorsa → o satırı geri al.
