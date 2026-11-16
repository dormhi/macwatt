#import <Foundation/Foundation.h>

// AppleSMC'den anahtar okuma. Root gerektirmez; değerler ~1 sn'de bir güncellenir
// (IORegistry'deki AppleSmartBattery verisi ise onlarca saniye eski kalabiliyor).

BOOL SMCOpen(void);

// Sayısal anahtarı (flt, si8/16/32, ui8/16/32) double olarak okur.
BOOL SMCReadNumber(const char *key, double *out);

// Ham baytların herhangi biri sıfırdan farklıysa YES (bayrak/hex anahtarlar için).
BOOL SMCReadNonZero(const char *key, BOOL *out);
