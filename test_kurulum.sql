-- Test Kurulum
-- Kurulumdan sonra:

-- Örnek ERP devir fiyatları yükle (satınalma şartı ile)
-- INSERT dbo.ErpDevirFiyatlari(StkId, SatinalmaSerti, BirimMaliyet, Miktar, ToplamTutar, Aciklama)
-- VALUES 
--     (12345, 'SART001', 15.50, 100, 1550.00, N'ERP devir fiyatı - SART001'),
--     (12346, 'SART001', 25.75, 50, 1287.50, N'ERP devir fiyatı - SART001');

-- Açılış FIFO (örnek) - Ortak maliyet sistemi + ERP devir fiyatları
EXEC dbo.sp_Fifo_AcilisStoklariniMaliyetlendir 
    @EnvanterTarihi='2025-12-31', 
    @BaslangicTarihi='2025-01-01', 
    @StkId=NULL,
    @SatinalmaSerti='SART001';  -- Satınalma şartı ile ERP devir fiyatları

SELECT TOP 20 *
FROM dbo.FifoKatman 
ORDER BY KatmanId DESC;

SELECT TOP 20 *
FROM dbo.FifoSorunluStoklar 
ORDER BY StkId;

-- Sabit fiyat tablosu kontrol
SELECT * FROM dbo.ErpDevirFiyatlari ORDER BY StkId, SatinalmaSerti;

SELECT TOP 50 *
FROM dbo.MaliyetIslem 
ORDER BY Baslangic DESC;

SELECT TOP 200 *
FROM dbo.MaliyetIslemAdim 
ORDER BY Baslangic DESC;