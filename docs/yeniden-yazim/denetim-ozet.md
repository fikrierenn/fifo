# FIFO motoru denetimi — özet (09.10.2026, opus alt ajan, salt okuma)

Kaynak: //BT-FIKRI/d$/Dev/fifo (kopya C:\dev\fifo, HEAD f5af0fc). Satır no'lar v2-production/02_V2_CoreProcedures.sql (02) ve 14_V2_AcilisOptimize.sql (14).

## Kritik

- K1 Alış iadesi (fat.eTip=2, irsHrk ehTip 2/12) katman düşürmüyor — 02:819-822, 02:955. 2025: 50,79M TL (%5,8). ÖLÇÜLDÜ.
- K2 Satış dışı stok hareketleri (sayım, fire, dönüşüm, iç kullanım, 88/89) havuza dokunmuyor — 02:955. ÖLÇÜLDÜ.
- K3 Ayın 1'i alışları kayboluyor (`> @baslangic`) — 02:805/827/1573. 01.01.2026: 14 fatura/535.688 TL; 2025 ≈16,6M. ÖLÇÜLDÜ.
- K4 Satış iadesi/gelir: aynı gün iade gelire ekleniyor (+1,11M Ocak), iade-ağır gün düşülmüyor (0,39M), karşılanamayan satış geliri yazılmıyor, önceki dönem iadesi kayboluyor, iade_cum tutarsız, ehTip 3 yok. Ocak gelirinin "tutması" hataların birbirini götürmesi (ÇIKARIM).
- K5 Merkez depo açılışı ERP defterinden, negatif bakiye atılarak: 31.12.2025 mekan 12 +5,61M/−4,22M → net 1,39M yerine 5,61M. ÖLÇÜLDÜ.

## Yüksek

- Y1 İki açılış algoritması (02 Hangfire, 14 Wizard) farklı kurallar.
- Y2 Fiyat farkı (fat.eTip 8) ve iade fark (10) faturaları okunmuyor: 2025 7,43M+9,86M.
- Y3 Hangi BKMMaliyet doğru belli değil: ERP kopyası son kayıt 23.03.2026, Ocak gelir 67,80M/SMM 55,02M; 72,35M yalnız erişilemeyen yerel kopyada; 872 sıfır maliyetli çıkış.
- Y4 STOK_YETERSIZ iade adedini mutlak ekliyor (02:1151); Hangfire batch sentetik adımı atlıyor.
- Y5 Tahmini maliyet SatisFiyat×0,65 ama SatisFiyat KDV dahil; otomatik devre dışı ürünü marjdan düşürüyor; AYLIK_DEVIR 2021-25 tarihli katmanlar önce tüketiliyor.
- Y6 Manuel maliyet tüm geçmiş katmanları eziyor, çıkışları güncellemiyor.
- Y7 Hangfire aylık job ↔ batch SP sonuç kümesi/kolon adı uyumsuz; hiç uçtan uca koşmamış (ÇIKARIM).
- Y8 Yeniden koşum FK ile patlar; dönem kilidi yok.
- Y9 Ortalama maliyet (12) iade işareti çift ters; ay sonu ≤0 ürün düşüyor.

## Orta (özet)

O1 açılışta iade/fiyat farkı yok, pencere 31.05.2021 sabit · O2 alışın %48'i ODAK 9525 (grup içi) · O3 SatisTutar doldurma tüm tipleri katıyor · O4 ay içi sıra yok (dönemsel FIFO) · O5 geçmiş ay sonu değer üretilemiyor · O6 yarım açılış riski · O7 dış mutabakat yok, 06 kırık · O8 mekan 12 ehTip 1 etiketi yanlış.

## Korunacaklar

Aralık kesişimli çıkış çekirdeği (02:965-1042), yeniden koşum geri yükleme deseni, ters FIFO açılış formülü, şart fiyatı önbelleği, CHECK/FK kısıtları, MaliyetIslem/FifoBatch izleme, build-master kapıları, fifo-degismez.ps1, DOGRULAMA_DEFTERI.

## GMY karar soruları (13)

1 havuz kapsamı · 2 merkez açılış miktarı (WMS/sayım) · 3 açılış değeri ↔ 153 · 4 hangi hareket tüketir · 5 alış iadesi maliyeti · 6 satış iadesi maliyet/gelir · 7 fiyat farkı faturaları · 8 maliyetsiz ürün · 9 negatif stok · 10 ay içi sıra · 11 grup içi alış · 12 gelir kaynağı/mekan 12 · 13 dönem kapama.
