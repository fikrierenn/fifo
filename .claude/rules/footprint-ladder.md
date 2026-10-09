# Footprint Ladder — Yeni Yetenek En Dar Basamakta

_pusula `footprint-ladder.md`den uyarlandı (Hermes "narrow waist")._

## Temel ilke

**Çekirdek dar bel; yetenek kenarda.** Her yeni kalıcı yapı (rule / skill /
agent / hook / SP / view / sayfa) bakım yükü + bağlam maliyeti getirir. Bir
ihtiyaç çıktığında merdivenin **EN ALT** basamağında çöz; üste ancak alt
basamak yetmezse çık.

## Merdiven (alttan üste — alt = dar/ucuz)

| # | Basamak | Ne zaman | Maliyet |
|---|---|---|---|
| 1 | **Mevcut SP/view/kural/sorguyu genişlet** | var olana bir filtre/kolon/satır eklemek çözüyorsa | ~0 yeni yüzey |
| 2 | **Yeni skill** | tekrarlanan iş akışı; tetik-bazlı yüklenir | düşük |
| 3 | **Yeni kural** (`.claude/rules/`) | kalıcı davranış kuralı | orta — her oturum bağlamda |
| 4 | **Yeni agent** | özelleşmiş salt-okuma denetim/danışman | orta |
| 5 | **Yeni hook** | kural metin olarak yetmiyorsa, kapı gerekiyorsa | orta — ateşlenebilirliği ayrıca kanıtlanmalı |
| 6 | **Yeni tablo / SP / view** | kalıcı şema gerçeği | yüksek — deploy + migration + bakım |
| 7 | **Yeni Razor sayfa (SON ÇARE)** | kullanıcı-görünür yeni yüzey | en yüksek |

## Kurallar

1. **Aşağıdan yukarı sor:** "Bunu mevcut X'i genişleterek çözebilir miyim?"
2. **Atlama yapma:** 6/7'ye gitmeden 1-5 elendi mi?
3. **Şüphede aşağıda kal.** Dar çözüm yetmezse büyütmek kolay; geniş çözümü
   küçültmek zor.
4. **Kapı basamağı özel:** bir kapı yazmadan önce
   `fifo-kapi-danismani`ya danış. Ateşlenmeyen kapı, kapı olmamasından
   kötüdür.

## FIFO'ya özgü uygulaması

- **Bir kural veritabanında zorlanabiliyorsa yeri veritabanıdır**, checklist
  değil. Ölçülmüş vaka: "fiyat 0 olamaz" bir dokümandaydı; `20_V2` ve `21_V2`
  reprice scriptleri onu elle onarmak için yazılmıştı. `CHECK (BirimMaliyet > 0)`
  bir satır ve o hata sınıfını komple kapatıyor.
- **Aynı işi iki SP yapıyorsa desen kopyalanmaz, ortaklaştırılır ya da
  aralarındaki fark yazılır.** `02_V2` ve `14_V2` açılışı iki kez yazıyor ve
  birinde olan sıfır-fiyat koruması diğerinde yoktu (2026-09-10'da bulundu).

## Anti-pattern

- ❌ "Yeni ihtiyaç = yeni SP" refleksi → önce mevcut SP'ye parametre/filtre.
- ❌ Tek kullanımlık iş için yeni skill/agent → akışta inline çöz.
- ❌ "İleride lazım olur" diye geniş soyutlama.
- ❌ **Yeni skill/agent yaratmadan önce mevcut listeye BAKMAMAK.**
  `.claude/skills/`, `.claude/agents/`, `.claude/commands/` + global + plugin.
  Aynı isim/işlev varsa **genişlet**, yaratma.
- ❌ Dış repodan (bel, pusula, awesome-X) "esin" diye burada zaten olanı
  tekrar kurmak. Önce mevcut kural/skill ile kıyasla.
- ❌ **Gerekçeyi kopyalamak.** Desen taşınabilir, gerekçe her hedefte yeniden
  kurulur (`alan-var-mi-sor.md`).

## İlişkili
- `plan-first.md` — büyük basamak = Tier 3 plan
- `alan-var-mi-sor.md` — kopyalanan desende tehlike gerekçededir
