# App Preview Baslat

.NET uygulamasini baslatip browser'da preview eder.

## Gorev
1. Build kontrol:
```bash
cd D:/Dev/fifo/app && dotnet build --nologo 2>&1
```

2. Hata varsa /build-fix calistir

3. .claude/launch.json olustur/guncelle:
```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "fifo-app",
      "runtimeExecutable": "dotnet",
      "runtimeArgs": ["run", "--project", "app/"],
      "port": 5000
    }
  ]
}
```

4. preview_start ile baslat

5. Preview screenshot al ve kontrol et

6. Console/network hatalari varsa duzelt

## Kurallar
- Port 5000 kullan
- HTTPS degil HTTP (development)
- VPN baglantisi gerekli (DB erisimi)
