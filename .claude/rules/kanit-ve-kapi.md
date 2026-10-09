# Kanıt ve kapı ilkeleri

> Eski v2 kurallarından (alan-var-mi-sor, yama-hedefi-dogrulama, kosan-is-bayatlar, dogrulama-siniri)
> süzülmüş dört ilke. v2 vakaları ve v2 mantığı taşınmadı.

## 1. Koda yazmadan kaynaktan doğrula
Kolon adı, SP parametresi, kod değeri (ehTip, eTip, KaynakTip…) hafızadan yazılmaz. Önce kaynak:
`sys.columns`, lookup view'ı (`irsTip_vw`, `fatTip_vw`), sema kaydı ya da canlı sayım.
Liste elle yazılmaz; `GROUP BY` / `sqlcli lookup --count-from` ile üretilir.

## 2. Dar desen yalancı yeşil verir
Bir denetim yalnız aradığı biçimi bulur. "Bulunamadı" tek başına kanıt değildir:
- denetimin aradığı nüfus boşsa sonuç "bakamadım"dır, "temiz" değil;
- kırılabilirliği gösterilmemiş kapı, kapı değildir (bilerek boz → kırmızı gör → geri al).

## 3. Koşan iş bayatlar
- Uzun koşu başlarken kod sürümü (commit) ve girdi tarihi kaydedilir; sonuç o sürüme aittir.
- Yıkıcı yeniden koşu referans veritabanında değil, `COPY_ONLY` kopyada yapılır.

## 4. Çelişki → reddet, eksiklik → say
- İki doğru bilgi aynı anda tutamıyorsa (ör. `tüketilen > giriş`, `kalan < 0`) koşu **durur**: bu bir kod hatasıdır.
- Bilgi doğru ama eksikse (ör. maliyeti henüz gelmemiş çıkış) koşu **devam eder**, eksik ayrı kovada sayılır
  ve raporda görünür (bekleyen maliyet, maliyetsiz kova, mutabakat bekleyen mekan).
- Eksiklik çelişkiye döndüğü an (ör. kuyruk kapanmış ama maliyet hâlâ boş) reddedilir.
- Sıkılaştırılan constraint kurulamazsa betik patlamaz ama kalıcı iz bırakır (`CONSTRAINT_KURULAMADI`).
