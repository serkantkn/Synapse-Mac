# Synapse for Mac

**Android telefonun, Mac'inin bir parçası.** Synapse, aynı Wi-Fi'deki Android telefonunu Mac'ine bağlar: bildirimler, aramalar, mesajlar, pano, dosyalar ve telefonun ekranı Mac'te. Sunucu yok, hesap yok; her şey yerel ağında ve uçtan uca şifreli kalır.

## İndir

En yeni sürüm [**Releases**](https://github.com/serkantkn/Synapse-Mac/releases) sayfasında: `Synapse-<sürüm>-mac.dmg`. macOS 14 Sonoma veya üstü gerekir; macOS 26'da Liquid Glass tasarımıyla açılır.

DMG'yi aç, Synapse'i Uygulamalar klasörüne sürükle. Uygulama henüz Apple onayından geçmediği için ilk açılışta macOS onu durdurur: Sistem Ayarları → Gizlilik ve Güvenlik'te en alttaki “Yine de Aç” düğmesine bas.

Telefon uygulaması: [serkantkn/Synapse-Android](https://github.com/serkantkn/Synapse-Android)

## Neler var

- **Bildirimler** Mac'te görünür; WhatsApp gibi uygulamalara Mac'ten cevap yazabilirsin.
- **Aramalar ve mesajlar:** gelen aramayı ve SMS'i gör, geri ara.
- **Ekran yansıtma:** telefonun ekranını ayrı bir pencerede aç, fare ve klavyeyle kullan.
- **Pano senkronizasyonu:** birinde kopyaladığın metin diğerine geçer.
- **Dosya ve link gönder:** dosyayı pencereye sürükle ya da seç; telefondan gelen linkler Mac'in tarayıcısında açılır.
- **Fotoğraflar:** telefondaki son fotoğrafları gör, Mac'e kaydet.
- **Menü çubuğu:** pil, şimdi çalan, son bildirim ve hızlı eylemler tek tıkta. **Telefonu bul** ile sessizdeki telefonu çaldır.

## Güvenlik ve gizlilik

- Cihazlar yalnızca yerel ağda doğrudan konuşur; hiçbir veri bir sunucuya gitmez. Reklam, analiz ve izleme yok.
- İlk eşleşme Mac'te görünen 6 haneli PIN ya da QR kod ile yapılır. PIN ağda hiçbir biçimde gönderilmez (PAKE); sonraki bağlantılar PIN sormadan kurulur. İstersen Ayarlar'dan her bağlantıda PIN isteyebilirsin.
- Bütün trafik AES-256-GCM ile şifrelenir.

## Hata ve öneri

Bir sorunla karşılaşırsan [bir issue aç](https://github.com/serkantkn/Synapse-Mac/issues); Mac modelini, macOS ve uygulama sürümünü yazman çok yardımcı olur.

Bu depo sürümleri ve geri bildirimi taşır; kaynak kod ayrı ve gizli tutuluyor.

---

## English

**Your Android phone, part of your Mac.** Synapse connects your Android phone on the same Wi-Fi to your Mac: notifications, calls, messages, the clipboard, files and the phone's screen, all on the Mac. No server, no account: everything stays on your local network, end-to-end encrypted.

Download the latest `Synapse-<version>-mac.dmg` from [Releases](https://github.com/serkantkn/Synapse-Mac/releases) (macOS 14 or later). The app is not notarized yet: on first launch, open System Settings → Privacy & Security and click “Open Anyway”. The phone app is at [serkantkn/Synapse-Android](https://github.com/serkantkn/Synapse-Android).
