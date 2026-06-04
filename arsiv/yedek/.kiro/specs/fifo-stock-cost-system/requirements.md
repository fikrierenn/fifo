# Gereksinimler Dokümanı

## Giriş

Bu doküman, perakende ortamları (fiziksel mağazalar + e-ticaret) için tasarlanmış FIFO (İlk Giren İlk Çıkar) Stok Maliyet Havuzu Sisteminin gereksinimlerini belirtir. Sistem, stok maliyet katmanlarını yönetir, alış ve satış işlemlerini takip eder, iadeleri işler ve muhasebe standartlarına uygun olarak Satılan Malın Maliyeti (SMM) hesaplar. Sistem, 2021 öncesi stoklardan açılış stokunu işler, 31 Mayıs 2021'den itibaren tüm alışlar için maliyet katmanları oluşturur ve günlük ve ürün bazında satış ve iadeleri uygun maliyet katmanlarıyla eşleştirmek için FIFO metodolojisini uygular.

## Sözlük

- **FIFO (İlk Giren İlk Çıkar)**: En eski stok kalemlerinin önce satıldığı olarak kaydedildiği bir stok değerleme yöntemi
- **Maliyet Katmanı**: Belirli bir birim maliyet ve miktara sahip, maliyet havuzunda ayrı olarak takip edilen farklı bir stok partisi
- **SMM (Satılan Malın Maliyeti)**: Bir dönemde satılan mallara atfedilebilen doğrudan maliyetler
- **Açılış Stok Katmanı**: Belirli bir anlık görüntü tarihinde maliyet katmanlarına dönüştürülen başlangıç stok bakiyesi
- **Stok Maliyet Havuzu**: Tüm stok maliyet katmanlarını (açılış, alışlar, iadeler) takip eden merkezi depo
- **Net Satış Mantığı**: İadelerin satış miktarlarını azalttığı, ürün bazında günlük satış ve iade toplamı
- **POS İade**: Stoğa geri envanter ekleyen satış noktası iade işlemi
- **Kümülatif Eksen**: İşlemlerin FIFO eşleştirmesi için kümülatif miktar aralıklarına eşlendiği zaman sıralı bir dizi
- **Stok Maliyet Havuzu Sistemi**: FIFO metodolojisini uygulayan eksiksiz stok maliyetlendirme sistemi
- **Ters-FIFO**: En son alışlardan geriye doğru çalışarak açılış stok katmanlarını yeniden oluşturma yöntemi
- **Tamamlama Katmanı**: Alış geçmişi açılış stok miktarlarını karşılamak için yetersiz olduğunda oluşturulan ek maliyet katmanı

## Gereksinimler

### Gereksinim 1: Açılış Stoku Başlatma

**Kullanıcı Hikayesi:** Muhasebe müdürü olarak, belirli bir envanter tarihinden açılış stok bakiyelerini başlatmak istiyorum, böylece sistem FIFO hesaplamaları için doğru başlangıç maliyet katmanlarına sahip olsun.

#### Kabul Kriterleri

1. Sistem belirtilen bir envanter tarihi için açılış stokunu başlattığında, Stok Maliyet Havuzu Sistemi o tarih için envanter anlık görüntü görünümünden stok miktarlarını OKUMALIDIR
2. 31 Mayıs 2021 sonrası alış geçmişi olan ürünler için açılış stoku işlendiğinde, Stok Maliyet Havuzu Sistemi maliyet katmanları oluşturmak için alış işlemlerini kullanarak ters-FIFO metodolojisini UYGULAMALIDIR
3. Ters-FIFO işleme açılış stokunu karşılamak için yetersiz alış miktarlarıyla sonuçlandığında, Stok Maliyet Havuzu Sistemi en son alış birim maliyetini kullanarak bir tamamlama katmanı OLUŞTURMALIDIR
4. Açılış stokunda bir ürün için hiç alış geçmişi yoksa, Stok Maliyet Havuzu Sistemi ürünü 'ALIS_YOK' sorun tipiyle sorun takip tablosuna KAYDETMELIDIR
5. Açılış stok katmanları oluşturulduğunda, Stok Maliyet Havuzu Sistemi her katmanı 'ACILIS' veya 'ACILIS_TAMAMLA' katman tipi ve 'NORMAL' durumu ile maliyet havuzuna YAZMALIDIR

### Gereksinim 2: Alış İşlemi İşleme

**Kullanıcı Hikayesi:** Stok kontrolörü olarak, tüm alış işlemlerinin maliyet katmanları olarak kaydedilmesini istiyorum, böylece sistem FIFO hesaplamaları için doğru stok maliyetlerini korusun.

#### Kabul Kriterleri

1. Bir tarih aralığı için alış işlemleri işlendiğinde, Stok Maliyet Havuzu Sistemi o aralıktaki irsaliye ve faturalardan tüm alış belgelerini OKUMALIDIR
2. Bir alış işlemi için birim maliyet hesaplanırken, Stok Maliyet Havuzu Sistemi net tutarı miktara BÖLMELIDIR
3. Alış işlemleri hem borç hem de alacak girişleri içerdiğinde, Stok Maliyet Havuzu Sistemi ürün başına işlem tarihi başına net miktar ve net tutarı HESAPLAMALIDIR
4. Alış maliyet katmanları eklenirken, Stok Maliyet Havuzu Sistemi yeni katmanları eklemeden önce aynı tarih aralığı için mevcut 'ALIS' tipi katmanları KALDIRMALIDIR
5. Bir alış katmanı oluşturulduğunda, Stok Maliyet Havuzu Sistemi onu 'ALIS' katman tipi, toplam miktara eşit kalan miktar ve 'NORMAL' durumu ile maliyet havuzuna YAZMALIDIR

### Gereksinim 3: Satış ve İade İşlemi İşleme

**Kullanıcı Hikayesi:** Satış müdürü olarak, satış ve iade işlemlerinin ürün başına günlük net miktarlarla işlenmesini istiyorum, böylece sistem stok hareketlerini doğru bir şekilde yansıtsın ve FIFO maliyetlendirmesini doğru uygulasın.

#### Kabul Kriterleri

1. Bir tarih aralığı için satış işlemleri işlendiğinde, Stok Maliyet Havuzu Sistemi belge tipi (1,4,5,100,101) İÇİNDE ve lokasyon (1,4477,4478) İÇİNDE olan tüm satış belgelerini OKUMALIDIR
2. Günlük işlemler toplandığında, Stok Maliyet Havuzu Sistemi satış ve iadeleri birleştirerek ürün başına gün başına net miktarı HESAPLAMALIDIR
3. Bir işlem POS iadesi olarak tanımlandığında, Stok Maliyet Havuzu Sistemi o ürün ve tarih için net satışları azaltmak üzere negatif miktar UYGULAMALIDIR
4. Günlük net miktar pozitif olduğunda, Stok Maliyet Havuzu Sistemi bunu stoğu azaltan bir satış işlemi olarak KABUL ETMELIDIR
5. Günlük net miktar negatif olduğunda, Stok Maliyet Havuzu Sistemi bunu stoğu artıran bir iade işlemi olarak KABUL ETMELIDIR

### Gereksinim 4: FIFO Maliyet Eşleştirme Algoritması

**Kullanıcı Hikayesi:** Mali kontrolör olarak, sistemin FIFO metodolojisini kullanarak satış ve iadeleri maliyet katmanlarıyla eşleştirmesini istiyorum, böylece SMM muhasebe standartlarına uygun olarak hesaplansın.

#### Kabul Kriterleri

1. Satışlar maliyet katmanlarıyla eşleştirilirken, Stok Maliyet Havuzu Sistemi tüm maliyet katmanlarını giriş tarihine göre artan sırada SIRALAMALIDIR
2. Maliyet katmanları için kümülatif eksen oluşturulurken, Stok Maliyet Havuzu Sistemi her katmanı kronolojik sıraya göre kümülatif miktar aralıklarına EŞLEMELIDIR
3. Satış işlemleri için kümülatif eksen oluşturulurken, Stok Maliyet Havuzu Sistemi her işlemi işlem tarihi sırasına göre kümülatif miktar aralıklarına EŞLEMELIDIR
4. FIFO dağılımı hesaplanırken, Stok Maliyet Havuzu Sistemi kesişim mantığını kullanarak satış kümülatif aralıklarını katman kümülatif aralıklarıyla EŞLEŞTIRMELIDIR
5. Bir satış bir maliyet katmanını kısmen tükettiğinde, Stok Maliyet Havuzu Sistemi o katmanın kalan miktarını AZALTMALI ve kalan satış miktarı için bir sonraki katmana GEÇMELİDİR
6. Bir satış bir maliyet katmanını tamamen tükettiğinde, Stok Maliyet Havuzu Sistemi kalan miktarı sıfıra AYARLAMALI ve bir sonraki en eski katmanla DEVAM ETMELİDİR
7. İade işlemleri işlenirken, Stok Maliyet Havuzu Sistemi iade edilen miktarları aynı FIFO eşleştirme mantığını ters yönde kullanarak stoğa geri EKLEMELIDIR

### Gereksinim 5: Maliyet Çıkış Kaydı

**Kullanıcı Hikayesi:** Muhasebe analisti olarak, tüm FIFO maliyet hesaplamalarının özel bir tabloda kalıcı olmasını istiyorum, böylece satılan malın maliyetini doğru bir şekilde denetleyebilir ve raporlayabilirim.

#### Kabul Kriterleri

1. FIFO eşleştirme maliyet dağılım sonuçları ürettiğinde, Stok Maliyet Havuzu Sistemi her eşleşen satırı maliyet çıkış tablosuna YAZMALIDIR
2. Maliyet çıkış kayıtları yazılırken, Stok Maliyet Havuzu Sistemi ürün ID, işlem tarihi, işlem tipi, katman ID, katman tarihi, miktar, birim maliyet ve toplam maliyeti İÇERMELİDİR
3. Bir satış işlemi kaydedildiğinde, Stok Maliyet Havuzu Sistemi işlem tipini 'SATIS' olarak AYARLAMALI ve miktarı pozitif olarak BELİRLEMELİDİR
4. Bir iade işlemi kaydedildiğinde, Stok Maliyet Havuzu Sistemi işlem tipini 'IADE' olarak AYARLAMALI ve negatif SMM etkisi için uygun işaret kuralını UYGULAMALIDIR
5. Maliyet katmanları güncellenirken, Stok Maliyet Havuzu Sistemi tüketilen miktarları yansıtmak için maliyet havuzu tablosundaki kalan miktar alanını GÜNCELLEMELIDIR

### Gereksinim 6: SMM Raporlama

**Kullanıcı Hikayesi:** Finans müdürü olarak, günlük ve ürün düzeyinde SMM raporları oluşturmak istiyorum, böylece maliyet performansını izleyebilir ve mali tabloları hazırlayabilirim.

#### Kabul Kriterleri

1. Günlük SMM raporları oluşturulurken, Stok Maliyet Havuzu Sistemi maliyet çıkış kayıtlarını işlem tarihine göre TOPARLAMALIDIR
2. Ürün düzeyinde SMM raporları oluşturulurken, Stok Maliyet Havuzu Sistemi maliyet çıkış kayıtlarını ürün ID ve işlem tarihine göre TOPARLAMALIDIR
3. Bir dönem için toplam SMM hesaplanırken, Stok Maliyet Havuzu Sistemi işlem tipi 'SATIS' olan tüm maliyet çıkış tutarlarını TOPLAMALIDIR
4. İadelerin SMM üzerindeki etkisi hesaplanırken, Stok Maliyet Havuzu Sistemi işlem tipi 'IADE' olan tüm maliyet çıkış tutarlarını uygun negatif etkiyle TOPLAMALIDIR
5. SMM raporları sunulurken, Stok Maliyet Havuzu Sistemi ürün detaylarını, işlem tarihlerini, miktarları, birim maliyetleri ve toplam maliyet tutarlarını İÇERMELİDİR

### Gereksinim 7: Veri Bütünlüğü ve Hata Yönetimi

**Kullanıcı Hikayesi:** Sistem yöneticisi olarak, sistemin veri bütünlüğünü doğrulamasını ve hataları zarif bir şekilde ele almasını istiyorum, böylece maliyet hesaplamaları doğru kalsın ve sorunlar izlenebilir olsun.

#### Kabul Kriterleri

1. Sıfır veya null miktar içeren herhangi bir işlem işlenirken, Stok Maliyet Havuzu Sistemi işlemi ATLAMALI ve bir uyarı KAYDETMELIDIR
2. Birim maliyet hesaplama sıfıra bölme ile sonuçlandığında, Stok Maliyet Havuzu Sistemi bir hata KAYDETMELI ve o işlemi ATLAMALIDIR
3. Bir satış miktarı maliyet katmanlarındaki mevcut stoğu aştığında, Stok Maliyet Havuzu Sistemi tutarsızlığı 'STOK_YETERSIZ' sorun tipiyle sorun takip tablosuna KAYDETMELIDIR
4. Bir tarih aralığı için maliyet katmanları yeniden işlenirken, Stok Maliyet Havuzu Sistemi yeni kayıtları eklemeden önce mevcut kayıtları kaldırarak idempotent işlemler SAĞLAMALIDIR
5. Herhangi bir veritabanı işlemi başarısız olduğunda, Stok Maliyet Havuzu Sistemi işlemi geri ALMALI ve detaylı hata bilgisini KAYDETMELIDIR

### Gereksinim 8: Performans ve Ölçeklenebilirlik

**Kullanıcı Hikayesi:** Veritabanı yöneticisi olarak, sistemin büyük hacimli işlemleri verimli bir şekilde işlemesini istiyorum, böylece günlük maliyet hesaplamaları kabul edilebilir zaman dilimlerinde tamamlansın.

#### Kabul Kriterleri

1. İşlemler işlenirken, Stok Maliyet Havuzu Sistemi satır satır cursor'lar yerine küme tabanlı işlemler KULLANMALIDIR
2. Maliyet katmanları sorgulanırken, Stok Maliyet Havuzu Sistemi ürün ID, giriş tarihi ve katman tipi üzerinde uygun indeksler KULLANMALIDIR
3. Maliyet çıkış kayıtları yazılırken, Stok Maliyet Havuzu Sistemi mümkün olduğunda toplu ekleme işlemleri KULLANMALIDIR
4. Büyük veri kümeleri toplandığında, Stok Maliyet Havuzu Sistemi ara sonuçlar için uygun indekslerle geçici tablolar KULLANMALIDIR
5. Saklı prosedürler çalıştırılırken, Stok Maliyet Havuzu Sistemi 10.000 ürüne kadar açılış stoku başlatmayı 5 dakika içinde TAMAMLAMALIDIR
