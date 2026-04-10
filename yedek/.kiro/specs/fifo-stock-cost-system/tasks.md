# Uygulama Planı

- [x] 1. Veritabanı Şeması Oluşturma




  - bkm.StokMaliyetHavuzu, bkm.StokEnvanter, bkm.StokMaliyetSorunlu, bkm.StokMaliyetCikis tablolarını oluştur
  - Her tablo için uygun indeksleri ekle
  - _Gereksinimler: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ]* 1.1 Tablo yapıları için property testleri yaz
  - **Özellik 5: Açılış Katman Alanları**
  - **Doğrular: Gereksinim 1.5**

- [ ]* 1.2 Tablo yapıları için property testleri yaz
  - **Özellik 10: Yeni Alış Katman Alanları**
  - **Doğrular: Gereksinim 2.5**

- [ ] 2. Açılış Stoku Prosedürü (sp_StokMaliyetAcilis)
  - Envanter snapshot okuma mantığını implement et
  - Ters-FIFO algoritmasını implement et
  - Tamamlama katmanı oluşturma mantığını implement et
  - Sorunlu kayıt loglama mantığını implement et
  - _Gereksinimler: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ]* 2.1 Açılış prosedürü için property testleri yaz
  - **Özellik 1: Envanter Okuma Doğruluğu**
  - **Doğrular: Gereksinim 1.1**

- [ ]* 2.2 Açılış prosedürü için property testleri yaz
  - **Özellik 2: Ters-FIFO Katman Toplamı**
  - **Doğrular: Gereksinim 1.2**

- [ ]* 2.3 Açılış prosedürü için property testleri yaz
  - **Özellik 3: Tamamlama Katmanı Oluşturma**
  - **Doğrular: Gereksinim 1.3**

- [ ]* 2.4 Açılış prosedürü için property testleri yaz
  - **Özellik 4: Alış Bulunamama Kaydı**
  - **Doğrular: Gereksinim 1.4**

- [ ] 3. Alış Katmanları Prosedürü (sp_StokMaliyetAlisKatman)
  - Alış belgelerini okuma mantığını implement et
  - Net miktar ve net tutar hesaplama mantığını implement et
  - Birim maliyet hesaplama mantığını implement et
  - İdempotent silme ve ekleme mantığını implement et
  - _Gereksinimler: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ]* 3.1 Alış prosedürü için property testleri yaz
  - **Özellik 6: Alış Belge Filtreleme**
  - **Doğrular: Gereksinim 2.1**

- [ ]* 3.2 Alış prosedürü için property testleri yaz
  - **Özellik 7: Birim Maliyet Hesaplama Doğruluğu**
  - **Doğrular: Gereksinim 2.2**

- [ ]* 3.3 Alış prosedürü için property testleri yaz
  - **Özellik 8: Net Alış Hesaplama**
  - **Doğrular: Gereksinim 2.3**

- [ ]* 3.4 Alış prosedürü için property testleri yaz
  - **Özellik 9: Alış Katman İdempotency**
  - **Doğrular: Gereksinim 2.4**

- [ ] 4. Checkpoint - Temel yapıların testi
  - Tüm testlerin başarılı olduğundan emin ol, sorular varsa kullanıcıya sor.

- [ ] 5. Satış ve İade İşleme Mantığı
  - Satış belgelerini okuma ve filtreleme mantığını implement et
  - Günlük net miktar hesaplama mantığını implement et
  - POS iade tanımlama ve negatif miktar uygulama mantığını implement et
  - _Gereksinimler: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ]* 5.1 Satış işleme için property testleri yaz
  - **Özellik 11: Satış Belge Filtreleme**
  - **Doğrular: Gereksinim 3.1**

- [ ]* 5.2 Satış işleme için property testleri yaz
  - **Özellik 12: Günlük Net Satış Hesaplama**
  - **Doğrular: Gereksinim 3.2**

- [ ]* 5.3 Satış işleme için property testleri yaz
  - **Özellik 13: POS İade İşareti**
  - **Doğrular: Gereksinim 3.3**

- [ ] 6. FIFO Eşleştirme Algoritması (sp_StokMaliyetFIFOCikis)
  - Katman kümülatif eksen hesaplama mantığını implement et
  - Satış kümülatif eksen hesaplama mantığını implement et
  - Kesişim mantığı ile FIFO dağılımını implement et
  - Kısmi ve tam katman tüketimi mantığını implement et
  - _Gereksinimler: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_

- [ ]* 6.1 FIFO algoritması için property testleri yaz
  - **Özellik 16: Katman Kronolojik Sıralama**
  - **Doğrular: Gereksinim 4.1**

- [ ]* 6.2 FIFO algoritması için property testleri yaz
  - **Özellik 17: Katman Kümülatif Eksen Tutarlılığı**
  - **Doğrular: Gereksinim 4.2**

- [ ]* 6.3 FIFO algoritması için property testleri yaz
  - **Özellik 18: Satış Kümülatif Eksen Tutarlılığı**
  - **Doğrular: Gereksinim 4.3**

- [ ]* 6.4 FIFO algoritması için property testleri yaz
  - **Özellik 19: FIFO Kesişim Doğruluğu**
  - **Doğrular: Gereksinim 4.4**

- [ ]* 6.5 FIFO algoritması için property testleri yaz
  - **Özellik 20: Kısmi Katman Tüketimi**
  - **Doğrular: Gereksinim 4.5**

- [ ]* 6.6 FIFO algoritması için property testleri yaz
  - **Özellik 21: Tam Katman Tüketimi**
  - **Doğrular: Gereksinim 4.6**

- [ ]* 6.7 FIFO algoritması için property testleri yaz
  - **Özellik 22: İade FIFO Eşleştirmesi**
  - **Doğrular: Gereksinim 4.7**

- [ ] 7. Maliyet Çıkış Kaydı
  - FIFO sonuçlarını StokMaliyetCikis tablosuna yazma mantığını implement et
  - Satış ve iade kayıt formatlarını implement et
  - Katman kalan miktar güncelleme mantığını implement et
  - _Gereksinimler: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ]* 7.1 Çıkış kaydı için property testleri yaz
  - **Özellik 23: Çıkış Kaydı Yazma**
  - **Doğrular: Gereksinim 5.1**

- [ ]* 7.2 Çıkış kaydı için property testleri yaz
  - **Özellik 24: Çıkış Kaydı Alan Bütünlüğü**
  - **Doğrular: Gereksinim 5.2**

- [ ]* 7.3 Çıkış kaydı için property testleri yaz
  - **Özellik 25: Satış Kaydı Format**
  - **Doğrular: Gereksinim 5.3**

- [ ]* 7.4 Çıkış kaydı için property testleri yaz
  - **Özellik 26: İade Kaydı Format**
  - **Doğrular: Gereksinim 5.4**

- [ ]* 7.5 Çıkış kaydı için property testleri yaz
  - **Özellik 27: Katman Kalan Miktar Güncelleme**
  - **Doğrular: Gereksinim 5.5**

- [ ] 8. Checkpoint - FIFO mantığının testi
  - Tüm testlerin başarılı olduğundan emin ol, sorular varsa kullanıcıya sor.

- [ ] 9. SMM Raporlama
  - Günlük SMM toplama view/query'sini oluştur
  - Ürün bazlı SMM toplama view/query'sini oluştur
  - Dönem SMM hesaplama mantığını implement et
  - İade etkisi hesaplama mantığını implement et
  - _Gereksinimler: 6.1, 6.2, 6.3, 6.4, 6.5_

- [ ]* 9.1 Raporlama için property testleri yaz
  - **Özellik 28: Günlük SMM Toplama**
  - **Doğrular: Gereksinim 6.1**

- [ ]* 9.2 Raporlama için property testleri yaz
  - **Özellik 29: Ürün Bazlı SMM Toplama**
  - **Doğrular: Gereksinim 6.2**

- [ ]* 9.3 Raporlama için property testleri yaz
  - **Özellik 30: Dönem SMM Hesaplama**
  - **Doğrular: Gereksinim 6.3**

- [ ]* 9.4 Raporlama için property testleri yaz
  - **Özellik 31: İade SMM Etkisi**
  - **Doğrular: Gereksinim 6.4**

- [ ]* 9.5 Raporlama için property testleri yaz
  - **Özellik 32: SMM Rapor İçeriği**
  - **Doğrular: Gereksinim 6.5**

- [ ] 10. Hata Yönetimi ve Validasyon
  - Sıfır/null miktar validasyonunu implement et
  - Sıfıra bölme hata yönetimini implement et
  - Yetersiz stok kontrolü ve loglama mantığını implement et
  - Transaction rollback mantığını implement et
  - _Gereksinimler: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ]* 10.1 Hata yönetimi için property testleri yaz
  - **Özellik 33: Yetersiz Stok Kaydı**
  - **Doğrular: Gereksinim 7.3**

- [ ]* 10.2 Hata yönetimi için property testleri yaz
  - **Özellik 34: Prosedür İdempotency**
  - **Doğrular: Gereksinim 7.4**

- [ ] 11. Performans Optimizasyonu
  - Tüm indekslerin oluşturulduğunu doğrula
  - Geçici tablo indekslerini ekle
  - Query execution planlarını analiz et ve optimize et
  - _Gereksinimler: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ]* 11.1 Performans testleri yaz
  - 10,000 ürün ile açılış prosedürünü test et (5 dakika hedefi)
  - 1,000 belge ile alış prosedürünü test et (1 dakika hedefi)
  - 1 aylık satış ile FIFO prosedürünü test et (2 dakika hedefi)
  - _Gereksinimler: 8.5_

- [ ] 12. Entegrasyon Testleri
  - Tam akış testi: Açılış → Alış → Satış → Rapor
  - Çoklu dönem testi: Ardışık dönemler için işlemler
  - İade senaryosu testi: Satış sonrası iade işlemleri
  - _Gereksinimler: Tüm gereksinimler_

- [ ] 13. Final Checkpoint - Sistem testi
  - Tüm testlerin başarılı olduğundan emin ol, sorular varsa kullanıcıya sor.

- [ ] 14. Dokümantasyon ve Dağıtım
  - Dağıtım scriptlerini hazırla
  - Kullanım kılavuzu oluştur
  - Bakım prosedürlerini dokümante et
  - Arşivleme stratejisini dokümante et
  - _Gereksinimler: Tüm gereksinimler_
