# Kolonun / Objenin Var Olduğunu SOR, Varsayma

_Belinza `alan-var-mi-sor.md`den uyarlandı. Orada Odoo alanı sorulmuyordu;
burada **ERP kolonu, SP parametresi ve KaynakTip değeri** varsayılıyor._

## Ölçülen vakalar (FIFO)

| Varsayım | Nereden geldi | Gerçek |
|---|---|---|
| `FifoKatman.KaynakTip` değerlerinden biri `FATURA` | eski `memory/schema.md` | **öyle bir değer yok**; gerçek küme `ACILIS · ACILIS_TAMAMLA · ALIS · AYLIK_DEVIR · SENTETIK_ALIS · IADE` |
| `FifoCikisDetay.SatisTutar` çıkış SP'sinde yazılmıyor | `fifo-expert.md` risk listesi | yazılıyor (`02_V2_CoreProcedures.sql:1156`) |
| V2 açılış mekan 12'yi hariç tutuyor | aynı bayat liste | tutmuyor; havuz `1,12,4477,4478` |
| `Invoke-Sqlcmd -TrustServerCertificate` var | başka ortamdan alışkanlık | bu sürümde **parametre yok**, komut patladı |
| `01_V2_Tables.sql` idempotent | plan dosyası | 7 tabloyu koşulsuz DROP ediyordu |

Beşinde de kaynak koda ya da sisteme **sorulmadı**; başka bir yerde
gördüğüm doğru sanıldı.

## Kural

> Bir kolon adı, SP parametresi, KaynakTip/Durum değeri ya da komut
> parametresi **koda yazılmadan önce** kaynaktan doğrulanır. Başka bir yerde
> çalışıyor olması kanıt değildir.

Araçlar hazır ve cevabı kesin:

```sql
-- kolon var mı
SELECT name, TYPE_NAME(user_type_id) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FifoKatman');

-- SP imzası
SELECT p.name, par.name, TYPE_NAME(par.user_type_id)
FROM sys.procedures p JOIN sys.parameters par ON par.object_id = p.object_id
WHERE p.name = 'sp_Fifo_AylikRutinFull' ORDER BY par.parameter_id;

-- gerçekte hangi değerler yazılıyor
SELECT KaynakTip, Durum, COUNT(*) FROM dbo.FifoKatman GROUP BY KaynakTip, Durum;

-- constraint gerçekten kurulu ve güvenilir mi
SELECT name, definition, is_disabled, is_not_trusted FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('dbo.FifoKatman');
```

Kod tarafı için `grep`; **kaynak dosya otoritedir**, memory değil.

## Neden bu sınıf sinsi

Bazıları **gürültülü** patlar (olmayan kolon → Err 207) ve ucuz görünür.
Pahalı olan sessiz olanıdır: alan **var** ama **anlamı farklıdır**.

Ölçülmüş örnek (pusula, aynı ERP): `irsHrk.ehTip = 10` **Yerel Alım**,
ama `fat.eTip = 10` **İade Fark Faturası**. İki ayrı sözlük
(`dbo.irsTip_vw` 34 kod, `dbo.fatTip_vw` 13 kod), biri diğerine kopyalanmış.
Bu hata patlamaz; sadece alış toplamını sessizce yanlış yapar.

FIFO'da aynı tuzak: alış filtresi `f.eTip IN (0, 2)` **fatura** tarafındadır.
`irsHrk` tarafında aynı kodlar farklı şey demektir.

## Genişletilmiş hâli

| Kopyalanan şey | Doğrulama |
|---|---|
| SQL kolonu | `sys.columns` |
| SP parametresi | `sys.parameters` |
| KaynakTip / Durum / SorunTipi değeri | `GROUP BY` ile gerçekte ne yazılıyor |
| Constraint varlığı | `sys.check_constraints` + `is_disabled` + `is_not_trusted` |
| ERP tip kodu (`eTip` / `ehTip`) | ilgili lookup view; **iki sözlük ayrıdır** |
| Komut/araç parametresi | `Get-Help` ya da bir kez dene |
| Dizin / dosya yolu | `ls` — doküman kanıt değil |

## Sınır testi

> *"Bunun burada var olduğunu nereden biliyorum — sordum mu, yoksa başka
> yerde işe yaradığı için mi?"*

İkincisiyse sorulmamıştır.

## İlişkili
- `olctum-mu-cikardim-mi.md` — doküman ölçüm değildir
- `sql-server-conventions.md` — ERP tip kodları ve tuzakları
