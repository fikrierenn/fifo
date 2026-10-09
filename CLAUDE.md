# fifo

## Orkestra

Bu projede yazılım üretimi Orkestra ile yürür (Claude Code eklentisi `orkestra@orkestra`). Orkestra'nın yeri `ORKESTRA_HOME`,
tanımsızsa bu deponun kardeşi `../orkestra`. Eklenti kaydı makineye özgüdür, git dışı `.claude/settings.local.json`'dadır:
yeni makinede bir kez `ork.cmd proje-kur .` (var olan dosyalara dokunmaz, eklentiyi bağlar).

- Akış: `/tanit` (ilk iş) → `/spec` → `/plan` → `/gorevler` → `/uygula` → `/kabul-testi` → `/surum`. Küçük iş: `/hata`, `/refactor`. Durum: `/durum`.
- Rol ajanları eklentide **`orkestra:` önekiyle** çağrılır: skill'de `sql-yazar` yazıyorsa alt ajan tipi `orkestra:sql-yazar`'dır.
- Deterministik kapılar: `ork.cmd kapilar --staged` (Windows) / `./ork kapilar --staged`. Araç durumu: `ork doktor`.
- Günlük: karar (gerekçesiyle), ölçüm (kanıtıyla), reddedilen/işe yaramayan yol, kritik bilgi, açık soru ve belirleyici kullanıcı sözü **oluştuğu anda** `ork not <tür> "…"` ile `docs/journal/` altına yazılır; sohbet ve ara durum yazılmaz. Sıkıştırma öncesi ham döküm `.orkestra/gunluk-ham/` (git dışı). Oturum sonu `/devir`. Görev defteri git'te (`specs/NNN-ad/defter.md`, `ork defter`). Kip: `config/orkestra.json` → `gunluk`.
- Projeye özel bilgi: `docs/proje/` (`/tanit` yazar), veritabanları ve compat seviyeleri `config/veritabanlari.json`.
- SQL runtime kuralları, test-önce ve merge insan kararı ilkeleri Orkestra anayasasındandır; proje kuralı çelişirse `/adr` ile kayda geçirin.
