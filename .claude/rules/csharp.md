---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.props"
---

# C# / proje dosyası kuralları (özet — tam katalog: kurallar-dotnet, biçim: yazim-csharp)

- Katman yönü: Domain bağımlılıksız; Application Infrastructure'ı bilmez; dış sistem port arayüzüyle.
- İsim: tip/metot/özellik PascalCase · arayüz `I` · async `…Async` · instance alan `_camelCase` · private static `s_camelCase` · parametre/yerel camelCase · alan terimleri Türkçe, teknik kalıp İngilizce, tanımlayıcıda Türkçe karakter yok.
- Yasak: `DateTime.Now` (TimeProvider) · `async void` (olay işleyici hariç) · `.Result`/`.Wait()` · boş catch · string birleştirmeyle SQL · kodda sır · para için `double`/`float` · `#pragma warning disable`/`NoWarn` ile susturma · `.csproj`'da paket sürümü (merkezi paket yönetimi).
- Her I/O `CancellationToken` alır; loglama mesaj şablonuyla; veri erişimi Dapper + SP (`CommandDefinition`).
- Kanıt: `dotnet build -warnaserror` (0 hata 0 uyarı) + testler. Kaydettiğin anda `cs_denetle.py` hook'u hızlı geri bildirim verir; kesin kanıt build'dir.
