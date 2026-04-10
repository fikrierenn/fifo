# FIFO Algoritma Ozeti

## Acilis Katmani
- Envanter tarihindeki stok alinir.
- ERP gecis tarihinden envanter tarihine kadar alislar cekilir.
- Ters FIFO ile stok miktarlari yaslandirilir.
- Havuz: ACILIS, eksik varsa ACILIS_TAMAMLA.

## Donem FIFO
- Donem alislari ALIS olarak katmanlanir.
- Satislar FIFO kesistirme ile katmanlara dagitilir.
- fifo_StokMaliyetCikis tablosuna yazilir.
- Katman miktarKalan guncellenir.

## Edge Cases
- Alis yoksa ALIS_YOK loglanir.
- Yetersiz stok varsa STOK_YETERSIZ loglanir.
- Iade/satis ters isaretli olabilir.
