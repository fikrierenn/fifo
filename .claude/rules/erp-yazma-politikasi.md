# ERP yazma politikası

- **ERP salt okunur.** `DerinSISBkm`, `EncoreMerkez` ve bağlı sunucularda INSERT/UPDATE/DELETE/MERGE,
  DDL ya da yazan SP çağrısı **yasak**. Ölçüm `sqlcli ... --read-only` ile yapılır.
- **İzinli yazma hedefi yalnız `BKMMaliyet`** veritabanıdır (FIFO'nun kendi tabloları).
- `bkm.Fin_AyKapanis` yalnız **okunur** (kapanmış ay bilgisi); FIFO bu tabloya yazmaz.
- Yeni bir yazma hedefi gerekiyorsa önce GMY onayı, sonra bu dosya güncellenir.
- Yıkıcı deneme (yeniden koşum, toplu silme) referans veritabanında değil, `COPY_ONLY` kopyada yapılır.
