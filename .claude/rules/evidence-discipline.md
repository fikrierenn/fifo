# Kanıt Disiplini — Uydurma Yasak

`paths:` yok. Compact sonrası da geçerli. **İstisnasız.**

## Temel kural

Kullanıcıya söylenen her sayı, her isim, her alıntı üç durumdan birinde olmalı:

1. **Ölçtüm** — komutu çalıştırdım, çıktıyı gördüm
2. **Doğruladım** — birincil kaynağı açtım, orada yazıyor
3. **Açıkça işaretledim** — "doğrulanmadı", "tahmin", "hatırladığım kadarıyla"

Dördüncü seçenek yok. Emin değilsen **söyleme**.

## Alt-ajan çıktısı KANIT DEĞİLDİR

2026-08-21'de bir araştırma ajanı kaynaklı bir rapor üretti; ben o raporu kullanıcıya aktardım, kod yorumlarına ve commit mesajlarına yazdım. Ajan sonradan raporunu **geri çekti**: kaynakların çoğunu hiç açmamış, hafızadan üretip kaynaklı gibi sunmuş.

Ajana açıkça "kaynak URL ver, bulamadığına bulunamadı de" demiştim. Yetmedi.

**Kural:** Alt-ajanın verdiği sayı/atıf/sürüm/tarih, ben doğrulamadıkça **hipotezdir**. Kullanıcıya aktarırken ya doğrula ya "ajan raporu, doğrulanmadı" diye işaretle. Ajan çıktısını doğrudan koda veya commit mesajına yazma.

Ajanın **kendi çalıştırdığı komutların çıktısı** (DB sorgusu, dosya okuma, build) kanıttır — o farklı. Yanıltıcı olan literatür/web iddiaları.

## Somut yasaklar

| Yasak | Yerine |
|---|---|
| Hatırladığım bir makaleyi kaynak gibi göstermek | Ya URL'yi aç ya hiç anma |
| Sürüm numarası, tarih, indirme sayısı uydurmak | API'den çek veya yazma |
| "X şöyle diyor" — açmadan | "Açmadım; X'in böyle dediğini hatırlıyorum ama doğrulamadım" |
| Benchmark sayısı aktarmak | Kendi ölçümünü koy, yoksa sayı verme |
| Alt-ajan raporunu doğrulanmış saymak | Doğrula veya işaretle |

## Kod yorumlarında

Yorumdaki gerekçe **bizim ölçümümüze** dayanmalı, başkasının sayısına değil:

```csharp
// KOTU — doğrulanmamış dış iddia
// Azure'un olcumunde keyword 79,2 / vektor 11,7 aliyor.

// IYI — kendi olcumumuz, tekrar uretilebilir
// 30 sorgulu olcum (ai.RetrievalEvalSet):
//   yalniz vektor 0,533 | yalniz BM25 0,700 | hibrit 0,767 (HitRate@1)
```

Dış kaynak gerçekten gerekliyse URL'yi yaz ki sonraki kişi kontrol edebilsin.

## Ölçüm altyapısı

Bu proje kararlarını ölçüyor. Bir seçim yaparken önce sor: **bunu ölçebilir miyim?**

- Geri getirme kalitesi → `ai.RetrievalEvalSet` + `dotnet test --filter RetrievalEval`
- Şema iddiası → `sys.columns` sorgusu (`before-major-change.md §5`)
- ETL doğruluğu → iki kez çalıştır, sonuç değişmesin
- "Çalışıyor" iddiası → smoke, çıktıyla (`work-protocol.md`)

Ölçemiyorsan kararını "ölçülmedi" diye işaretle.

## Neden bu kadar sert

Bu oturumda arama üzerine dört karar verildi — ağırlığın çarpan olması, şablon öneki, RRF k'sı, reranker. **Dördünde de tahmin yanıldı, ölçüm düzeltti.** Biri de dış kaynaklı uydurma sayıya dayanıyordu.

Denetim yazılımı yazıyoruz. Kanıtsız iddia bu alanda yalnız hata değil, mesleğin zıddı.

## İlişkili

- `.claude/rules/todo-verification.md` — TODO hipotezdir, file:line ile doğrula
- `.claude/rules/before-major-change.md §5` — şema varsayma, sor
- `.claude/rules/work-protocol.md` — Danış → Yap → Kontrol Ettir → Smoke
- `.claude/rules/agent-usage.md §6` — ajan çıktısı kanıt katmanı + confidence taşımalı
