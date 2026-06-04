# FIFO Ops Panel - PRD

## Hedef
FIFO stok maliyet akisini manuel ve job tabanli calistirmak, izlemek ve sorunlari
hizlica goruntulemek.

## Kapsam
- Parametreli calistirma (acilis, alis katman, FIFO cikis)
- Tek urun guncelleme
- Sorunlu stok listesi
- Donem ozeti (cikis satiri, urun sayisi, maliyet)

## Kapsam Disi
- Tam otomatik job scheduler (SQL Agent ayarlari disinda)
- Harici entegrasyonlar
- Karma rapor tasarimlari

## Kabul Kriterleri
- UI uzerinden sp_fifo_StokMaliyetCalistir calistirilir.
- Tek urun icin @stkID verilebilir.
- Sorunlu stoklar tarih araligina gore listelenir.
- Hatalar UI uzerinde net mesajla gorunur.
