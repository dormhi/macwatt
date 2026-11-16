# MacWatt

MacBook için menü çubuğu uygulaması: adaptörden gelen ve pile giren/çıkan gücü volt, amper ve watt olarak canlı gösterir, bağlı şarj cihazını ve kabloyu tanır.

## Özellikler

- **Canlı ölçüm (0.5 sn):** Adaptör girişi, pil ve toplam sistem tüketimi için V / A / W. Değerler doğrudan SMC'den okunur; macOS'un pil kaydındaki (IORegistry) değerler onlarca saniye eski kalabildiği için onlar yalnızca yedek olarak kullanılır.
- **Şarj cihazı tanıma:** USB-PD kimliğinden üretici, sunulan tüm güç profilleri (5 / 9 / 15 / 20 / 28 V…), Mac'in seçtiği profil ve bağlı port. Apple adaptörleri adıyla görünür (ör. "Apple 140W USB-C Power Adapter").
- **Kablo bilgisi:** E-marker'lı kablolarda üretici, akım kapasitesi (3 A / 5 A), maksimum voltaj ve USB hızı.
- **Kalan süre:** Pildeyken boşalmaya, şarjdayken dolmaya kalan süre.
- **Şarj olmama nedeni:** Pil dolu, adaptör yetersiz, pil sıcak, Optimize Pil Şarjı, şarjı durduran bir uygulama (AlDente vb.) gibi durumlar.
- **Küçük menü çubuğu:** Yalnızca metin — adaptördeyken `35.9W`, pildeyken `−7.9W`.

## Gereksinimler

- macOS 13 veya üstü
- Apple Silicon MacBook (M2 üzerinde test edildi; Intel Mac'lerde denenmedi)
- Xcode Command Line Tools (`xcode-select --install`)

Root yetkisi gerekmez.

## Kurulum

### DMG ile

1. [Releases](https://github.com/dormhi/macwatt/releases) sayfasından `MacWatt-<sürüm>.dmg` dosyasını indirin.
2. DMG'yi açın, `MacWatt.app`'i `Applications` klasörüne sürükleyin.
3. İlk açılışta macOS "geliştirici doğrulanamadı" uyarısı verir (uygulama Apple Developer ID ile imzalı değil). **Sistem Ayarları → Gizlilik ve Güvenlik** altında **Yine de Aç**'a basın. Bu yalnızca bir kez gerekir.

### Kaynaktan

```bash
git clone https://github.com/dormhi/macwatt.git
cd macwatt
./install.sh
```

Uygulama `/Applications/MacWatt.app` olarak kurulur ve açılır.

| Komut | Ne yapar |
| --- | --- |
| `./build.sh` | Yalnızca derler (`build/MacWatt.app`) |
| `./package.sh` | Dağıtım DMG'si üretir (`dist/MacWatt-<sürüm>.dmg`) |
| `./install.sh` | Derler, kurar, başlatır |
| `./install.sh --autostart` | Ayrıca oturum açılışında otomatik başlatır |
| `./install.sh --autostart-off` | Otomatik başlatmayı kapatır |
| `./install.sh --uninstall` | Uygulamayı ve otomatik başlatmayı kaldırır |

Terminalden tek seferlik okuma:

```bash
/Applications/MacWatt.app/Contents/MacOS/MacWatt --print
```

## Nasıl çalışır

| Veri | Kaynak |
| --- | --- |
| Pil V / A / W | SMC `B0AV`, `B0AC`, `B0AP` |
| Adaptör girişi V / A / W | SMC `VD0R`, `ID0R`, `PDTR` |
| Sistem tüketimi | SMC `PSTR` |
| Yüzde, sıcaklık, kalan süre, şarj kodları | IORegistry `AppleSmartBattery` |
| PD profilleri, etkin profil, port | IORegistry `IOPortFeaturePowerSource` |
| Şarj cihazı / kablo kimliği | IORegistry `IOPortTransportComponentCCUSBPDSOP` / `SOPp` |

## Sınırlamalar

- SMC anahtarları Apple tarafından belgelenmemiştir ve macOS sürümleri arasında değişebilir. Okunamazlarsa uygulama IORegistry değerlerine döner.
- Üçüncü parti şarj cihazları çoğu zaman adlarını bildirmez; bu durumda üretici, USB-IF Vendor ID'sinden küçük bir tabloyla bulunur, bulunamazsa kod olarak gösterilir. Bir cihazın GaN olup olmadığı sistemden öğrenilemez.
- "Şarj olmama nedeni" macOS'un belgelenmemiş kodlarına değil ölçümlere dayanır; Optimize Pil Şarjı tahmini olarak gösterilir.

## Lisans

[MIT](LICENSE)
