#import <Foundation/Foundation.h>

// USB-PD güç profili (PDO). Örn. 20 V × 5 A sabit, ya da PPS/AVS aralığı.
@interface ChargerProfile : NSObject
@property (nonatomic, copy) NSString *kind;   // "Fixed", "PPS", "AVS"...
@property (nonatomic) double minVolts;         // aralıklı profillerde alt sınır, sabitte = volts
@property (nonatomic) double volts;
@property (nonatomic) double amps;
@property (nonatomic) double watts;
@property (nonatomic) BOOL active;
@end

@interface ChargerInfo : NSObject
@property (nonatomic, copy) NSString *displayName;    // "Apple 140W USB-C Power Adapter" / "Anker · 100 W USB-PD"
@property (nonatomic, copy) NSString *detail;         // "VID 0x2FE6" gibi ek tanımlayıcılar (boş olabilir)
@property (nonatomic) double ratedWatts;
@property (nonatomic, copy) NSString *port;           // "USB-C 1", "MagSafe 3"
@property (nonatomic, copy) NSArray<ChargerProfile *> *profiles;
@property (nonatomic, strong) ChargerProfile *activeProfile;
@property (nonatomic, copy) NSString *cable;          // "Belkin · 5 A · 50 V · USB 2.0" (boş olabilir)
@end

@interface PowerSample : NSObject

// Yavaş veri (IORegistry, birkaç saniyede bir ve fiş takılınca/çıkınca)
@property (nonatomic) BOOL registryOK;
@property (nonatomic) BOOL externalConnected;
@property (nonatomic) BOOL fullyCharged;
@property (nonatomic) int percent;
@property (nonatomic) double temperatureC;
@property (nonatomic) int minutesToEmpty;   // -1 = hesaplanıyor
@property (nonatomic) int minutesToFull;    // -1 = hesaplanıyor
@property (nonatomic) uint32_t notChargingCode;
@property (nonatomic) uint32_t slowChargingCode;
@property (nonatomic) uint32_t inhibitCode;
@property (nonatomic, strong) ChargerInfo *charger;   // güç bağlı değilse nil

// Hızlı veri (SMC, ~1 sn güncel; SMC yoksa IORegistry değerleri)
@property (nonatomic) BOOL fastFromSMC;
@property (nonatomic) double inputV, inputA, inputW;
@property (nonatomic) double batteryV, batteryA, batteryW;
@property (nonatomic) double systemW;

// Türetilen
@property (nonatomic) BOOL powerConnected;
@property (nonatomic) BOOL charging;
@property (nonatomic, copy) NSString *reason;   // şarj olmama / yavaş şarj nedeni, yoksa nil

@end

// IORegistry'den yavaş alanları tazeler. Pil servisi yoksa NO.
// includeCharger: şarj cihazı/kablo kimliğini de yeniden tara (pahalı; fiş değişince ve popover açılınca).
BOOL PowerReadSlow(PowerSample *sample, BOOL includeCharger);

// SMC'den anlık V/A/W okur ve türetilen alanları hesaplar.
void PowerReadFast(PowerSample *sample);
