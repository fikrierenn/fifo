# FIFO yeniden yazım — ölçüme dayalı kararlar (09.10.2026)

Kaynak: opus alt ajan salt-SELECT ölçümü (sqlcli --profile erp/encore --read-only), pencere 01.01.2025–30.09.2026. Mal evreni = urn.urnTip=0 − 5 hizmet kalemi (plan 43).

## Ölçülmüş temel gerçekler

- Açılış 31.12.2025: şirket geneli net (26142/4480/4835 hariç) 249.352 çeşit / 7.615.026 adet. 153 bakiyesi 345.723.085,47 ₺ (2026 açılış fişiyle kuruşu kuruşuna). Örtük 45,4 ₺/adet (çıkarım).
- 26142 İPTAL-Transfer: −3,20M negatif (123K çeşit), 2025'ten beri yalnız ehTip 11 girişi — kalıntı. 4480 İade Deposu: −334K, stoksuz iade çıkarıyor.
- Alışın ~%66'sı (tutar) ehTip 10 Yerel Alım ile doğrudan mağazaya (2026: 498,9M), merkeze ehTip 0 258,7M.
- Transfer (13/9/8) değer taşıyor (~alış fiyatının %91'i).
- 2026 tüketen hareketler: satış 1/4/100; 99 sayım −1,22M (bunun ~%54'ü 01.08.2026 İst.Yolu "SINAV OKULLARI" tek belge −663.221 adet/154,6M); 90 −692K (değersiz); 96/98/92; 95 dönüşüm; 89 küçük. Değersiz girişler: 16 Stok EKLE +1,21M adet 0 ₺, SahafGiris 88 +5.720 0 ₺.
- Alış iadesi bağı fatAyr.reffatId (%98,7 dolu, %97,7 fiyat ±%1). fat.eBagIade iddiası çürük. ehTip 12 ehTutarN fatura değeri DEĞİL (12,25M vs fatAyr 41,25M). 2026 iade 76,17M, 18,04M'ı açılış öncesi alışa bağlı.
- Satış iadesi (Encore DocType 3, 2026 18,92M): aynı gün %50, aynı ay %33,3, sonraki ay %6,4, bağsız %10.
- fat.eTip 10 → fatAyr.ehSipID alış faturası eID'si (%98,5). fat.eTip 8 bağsız (ürün düzeyi). 2026: 8=3,90M, 10=11,67M.
- Maliyetsiz ciro 2026: hiç alışı yok + açılışta yok 350,8M — 336,1M Sınav "SÜRELİ YAYIN 2026" paketleri (88 ile 106,9M giriş). Sahte ürünler urnTip=0: "M" 60318 66,1M (Yanıt 223'e 30.09'da −111.805 adet, sonra 15M iade), YEMEK BEDELİ 5,7M, hediye çeki ~2,9M, KAFE 0,7M.
- Negatif stok (transit hariç): negatif bakiyede çıkış net çıkışın %0,3–1,1'i (Oca–Tem).
- Dönemsel vs sürekli fark: 33.274 adet / 9 ay (~%0,4).
- Grup içi alış %44,5 (ODAK 9525, Bursa Kültür 56).
- Fin_AyKapanis 2025/01–2026/06; 2026/07–08 kaydı YOK. Geç belge 2026: 44 belge/7,2M.

## Denetleyici kararları (ölçüme dayalı)

1. Şirket geneli tek havuz; 26142, 4480, 4835 havuz dışı, ayrı "mutabakat bekleyen" raporu.
2. Tüketenler: 1,4,100, 99(−), 90(−), 96, 98, 92, 95(−), 89, 2, 12. Katman açanlar: 0, 10, 88(+), 16(+), 99(+), 95(+), iadeler. Transferler tek havuzda yok sayılır. Gider kovaları ayrı: SMM (satış) / fire-sayım / iç kullanım / bozuk.
3. Alış iadesi: reffatId'nin alış katmanından, değer fatAyr birim fiyatı; bağsız → en eski katman.
4. Satış iadesi: aynı ürünün o ayki ortalama çıkış maliyetiyle geri girer; bağsız/eski dönem → son çıkış maliyeti; gelir ters işaret, ehTip 3 dahil.
5. eTip 10 → ehSipID katmanını düzeltir; eTip 8 → açık katmanlara adet oranıyla, tükenmiş kısım SMM.
6. Sürekli günlük FIFO; negatife düşen çıkış "bekleyen maliyet" kuyruğu, sonraki alışla kapanır; sentetik/sabit fiyat yok.
7. Grup içi alış fatura fiyatıyla; rapor ilişkili/dış ayrı kova.
8. Mekan 12 ehTip 1 = toptan/grup içi, tüketir.
9. Kapanmış aya yazılmaz; geç belge açık aya düzeltme. Fin_AyKapanis'te 07–08/2026 eksik.
10. Evren kara listesi (urnTip yetmez) gerekli.

## GMY politika kararları (09.10.2026)

- **11.** Sınav süreli yayın paketleri FIFO dışı, ayrı model; 01.08 SINAV OKULLARI sayım çıkışı paket maliyeti sayılır (fire değil); Sınav marjı ayrı raporlanır.
- **12.** Sahte ürün kara listesi FIFO deposunda elle tutulur; tutarsız fiyat/adet şüphelisi raporda uyarı olarak çıkar, listeye GMY ekler.
- **13.** Değersiz girişler (ehTip 16 Stok EKLE, SahafGiris): son alış birim maliyetiyle bayraklı katman; son alış yoksa "maliyetsiz" kovası.
- **14.** Açılış değeri ters FIFO esas; 153 (345.723.085,47) ile fark ve sebepleri açılış raporunda gösterilir, düzeltme yapılmaz.
- **15.** Git işleri (GitHub yedeği, 37 commit'siz dosya) sonraya bırakıldı.
- **16.** Süreli yayın paketi: satış önce, maliyet sonradan aylık faturalarla gelir (GMY 09.10) → paket modeli satış dönemine tahakkuk/sonradan gelen faturayla eşleştirme; 01.08 sayım çıkışının bu modeldeki yeri ölçülecek.
