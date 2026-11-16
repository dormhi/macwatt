#import "PowerReader.h"
#import "SMC.h"
#import <IOKit/IOKitLib.h>

@implementation ChargerProfile
@end

@implementation ChargerInfo
@end

@interface PowerSample ()
// IORegistry'deki (gecikmeli) anlık değerler; SMC okunamazsa bunlar kullanılır.
@property (nonatomic) double regInputV, regInputA, regInputW;
@property (nonatomic) double regBatteryV, regBatteryA;
@property (nonatomic) double regSystemW;
@end

@implementation PowerSample
@end

#pragma mark - Yardımcılar

static int64_t Number(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value longLongValue];
    }
    return 0;
}

static int64_t NumberIn(NSDictionary *dict, NSString *key, NSString *subKey) {
    NSDictionary *sub = dict[key];
    if ([sub isKindOfClass:[NSDictionary class]]) {
        return Number(sub, subKey);
    }
    return 0;
}

static NSString *String(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return value;
    }
    return nil;
}

static NSArray<NSDictionary *> *EntriesOfClass(const char *className) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) != KERN_SUCCESS) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    io_object_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
            [result addObject:CFBridgingRelease(props)];
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return result;
}

static BOOL SamePort(NSDictionary *a, NSDictionary *b) {
    return Number(a, @"ParentPortNumber") == Number(b, @"ParentPortNumber") &&
           Number(a, @"ParentPortType") == Number(b, @"ParentPortType");
}

// USB-IF Vendor ID → üretici. Yalnızca doğrulanmış, şarj/kablo dünyasında yaygın olanlar.
static NSString *VendorName(int64_t vid) {
    switch (vid) {
    case 0x05AC: return @"Apple";
    case 0x291A: return @"Anker";
    case 0x050D: return @"Belkin";
    case 0x04E8: return @"Samsung";
    case 0x18D1: return @"Google";
    case 0x2717: return @"Xiaomi";
    case 0x12D1: return @"Huawei";
    case 0x17EF: return @"Lenovo";
    case 0x413C: return @"Dell";
    case 0x03F0: return @"HP";
    case 0x045E: return @"Microsoft";
    case 0x0B05: return @"ASUS";
    case 0x054C: return @"Sony";
    case 0x1004: return @"LG";
    case 0x0451: return @"Texas Instruments";
    case 0x04B4: return @"Cypress/Infineon";
    case 0x0BDA: return @"Realtek";
    case 0x2109: return @"VIA Labs";
    default: return nil;
    }
}

static uint32_t VDO(NSArray *vdos, NSUInteger index) {
    if (index >= vdos.count || ![vdos[index] isKindOfClass:[NSData class]]) {
        return 0;
    }
    NSData *data = vdos[index];
    if (data.length < 4) {
        return 0;
    }
    const uint8_t *b = data.bytes;
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

// SOP' Discover Identity yanıtından kablo özeti. VDO sırası: ID Header, Cert Stat, Product, Cable.
static NSString *DescribeCable(NSDictionary *component) {
    if (component == nil) {
        return nil;
    }
    int64_t vid = Number(component, @"Vendor ID");
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *vendor = VendorName(vid);
    if (vendor) {
        [parts addObject:vendor];
    } else if (vid != 0) {
        [parts addObject:[NSString stringWithFormat:@"VID 0x%04llX", vid]];
    }

    NSString *type = String(component, @"Product Type Description");
    BOOL active = [type rangeOfString:@"Active"].location != NSNotFound;
    NSArray *vdos = [component[@"Metadata"] isKindOfClass:[NSDictionary class]] ? component[@"Metadata"][@"VDOs"] : nil;
    uint32_t cable = [vdos isKindOfClass:[NSArray class]] ? VDO(vdos, 3) : 0;
    if (cable != 0) {
        switch ((cable >> 5) & 0x3) {
        case 1: [parts addObject:@"3 A"]; break;
        case 2: [parts addObject:@"5 A"]; break;
        default: break;
        }
        static const char *voltages[] = {"20 V", "30 V", "40 V", "50 V"};
        [parts addObject:@(voltages[(cable >> 9) & 0x3])];
        static NSString *const speeds[] = {@"USB 2.0", @"USB 5 Gbps", @"USB 10 Gbps", @"USB4 20/40 Gbps", @"USB4 80 Gbps"};
        uint32_t speed = cable & 0x7;
        if (speed < 5) {
            [parts addObject:speeds[speed]];
        }
    }
    [parts addObject:active ? @"aktif" : @"pasif"];
    return [parts componentsJoinedByString:@" · "];
}

static ChargerProfile *ProfileFromOption(NSDictionary *option) {
    ChargerProfile *p = [[ChargerProfile alloc] init];
    NSString *cls = String(option, @"Class") ?: @"";
    NSString *kind = [cls stringByReplacingOccurrencesOfString:@"IOPortFeaturePowerSourceOption" withString:@""];
    p.kind = kind.length ? kind : @"Fixed";
    double v = (double)Number(option, @"Voltage (mV)") / 1000.0;
    double vMax = (double)Number(option, @"Max Voltage (mV)") / 1000.0;
    double vMin = (double)Number(option, @"Min Voltage (mV)") / 1000.0;
    p.volts = vMax > 0 ? vMax : v;
    p.minVolts = vMin > 0 ? vMin : p.volts;
    p.amps = (double)Number(option, @"Max Current (mA)") / 1000.0;
    p.watts = (double)Number(option, @"Max Power (mW)") / 1000.0;
    if (p.watts <= 0) {
        p.watts = p.volts * p.amps;
    }
    return p;
}

static BOOL SameProfile(NSDictionary *a, NSDictionary *b) {
    NSString *ua = String(a, @"UUID"), *ub = String(b, @"UUID");
    if (ua && ub) {
        return [ua isEqualToString:ub];
    }
    return Number(a, @"Voltage (mV)") == Number(b, @"Voltage (mV)") &&
           Number(a, @"Max Current (mA)") == Number(b, @"Max Current (mA)");
}

static ChargerInfo *ReadCharger(NSDictionary *battery) {
    NSDictionary *adapter = battery[@"AdapterDetails"];
    if (![adapter isKindOfClass:[NSDictionary class]]) {
        adapter = @{};
    }
    ChargerInfo *info = [[ChargerInfo alloc] init];
    info.ratedWatts = (double)Number(adapter, @"Watts");

    // Etkin güç kaynağı: WinningPowerSourceOption taşıyan, en yüksek güçlü kaynak.
    NSDictionary *source = nil;
    double bestW = -1;
    for (NSDictionary *entry in EntriesOfClass("IOPortFeaturePowerSource")) {
        NSDictionary *win = entry[@"WinningPowerSourceOption"];
        if (![win isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        double w = (double)Number(win, @"Max Power (mW)");
        if (w > bestW) {
            bestW = w;
            source = entry;
        }
    }

    NSMutableArray<ChargerProfile *> *profiles = [NSMutableArray array];
    if (source) {
        NSString *portType = String(source, @"ParentPortTypeDescription") ?: @"Port";
        info.port = [NSString stringWithFormat:@"%@ %lld", portType, Number(source, @"ParentPortNumber")];
        NSDictionary *win = source[@"WinningPowerSourceOption"];
        id options = source[@"PowerSourceOptions"];   // IOKit bunu NSSet olarak veriyor
        if ([options isKindOfClass:[NSArray class]] || [options isKindOfClass:[NSSet class]]) {
            for (NSDictionary *option in options) {
                if (![option isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                ChargerProfile *p = ProfileFromOption(option);
                p.active = SameProfile(option, win);
                [profiles addObject:p];
            }
        }
        if (profiles.count == 0) {
            ChargerProfile *p = ProfileFromOption(win);
            p.active = YES;
            [profiles addObject:p];
        }
    } else {
        NSArray *menu = adapter[@"UsbHvcMenu"];
        int64_t activeIndex = Number(adapter, @"UsbHvcHvcIndex");
        if ([menu isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in menu) {
                if (![item isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                ChargerProfile *p = [[ChargerProfile alloc] init];
                p.kind = @"Fixed";
                p.volts = p.minVolts = (double)Number(item, @"MaxVoltage") / 1000.0;
                p.amps = (double)Number(item, @"MaxCurrent") / 1000.0;
                p.watts = p.volts * p.amps;
                p.active = Number(item, @"Index") == activeIndex;
                [profiles addObject:p];
            }
        }
    }
    [profiles sortUsingComparator:^NSComparisonResult(ChargerProfile *a, ChargerProfile *b) {
        if (a.volts != b.volts) {
            return a.volts < b.volts ? NSOrderedAscending : NSOrderedDescending;
        }
        return a.minVolts < b.minVolts ? NSOrderedAscending : NSOrderedSame;
    }];
    info.profiles = profiles;
    for (ChargerProfile *p in profiles) {
        if (p.active) {
            info.activeProfile = p;
        }
    }
    if (info.ratedWatts <= 0) {
        for (ChargerProfile *p in profiles) {
            info.ratedWatts = MAX(info.ratedWatts, round(p.watts));
        }
    }

    // USB-PD kimliği (SOP = şarj cihazı, SOP' = kablo)
    NSDictionary *sop = nil, *sopPrime = nil;
    if (source) {
        for (NSDictionary *c in EntriesOfClass("IOPortTransportComponentCCUSBPDSOP")) {
            if (SamePort(c, source)) {
                sop = c;
            }
        }
        for (NSDictionary *c in EntriesOfClass("IOPortTransportComponentCCUSBPDSOPp")) {
            if (SamePort(c, source)) {
                sopPrime = c;
            }
        }
    }
    int64_t vid = Number(sop, @"Vendor ID");
    int64_t pid = Number(sop, @"Product ID");

    // Apple adaptörleri (ve bazı MagSafe/USB-C adaptörler) adını kendisi bildirir.
    NSString *name = String(adapter, @"Name");
    NSString *maker = String(adapter, @"Manufacturer");
    if ([maker hasPrefix:@"Apple"]) {
        maker = @"Apple";
    }
    if (maker == nil) {
        maker = VendorName(vid);
    }

    NSString *watts = info.ratedWatts > 0 ? [NSString stringWithFormat:@"%.0f W", info.ratedWatts] : nil;
    if (name) {
        info.displayName = (maker && ![name hasPrefix:maker]) ? [NSString stringWithFormat:@"%@ %@", maker, name] : name;
    } else {
        NSString *kind = profiles.count > 1 || source ? @"USB-PD şarj cihazı" : @"şarj cihazı";
        NSString *base = watts ? [NSString stringWithFormat:@"%@ %@", watts, kind] : kind;
        info.displayName = maker ? [NSString stringWithFormat:@"%@ · %@", maker, base] : base;
    }

    NSMutableArray<NSString *> *detail = [NSMutableArray array];
    if (maker == nil && vid != 0) {
        [detail addObject:[NSString stringWithFormat:@"Üretici kodu (VID) 0x%04llX", vid]];
    }
    NSString *model = String(adapter, @"Model");
    if (model) {
        [detail addObject:[NSString stringWithFormat:@"Model %@", model]];
    } else if (pid != 0) {
        [detail addObject:[NSString stringWithFormat:@"Ürün kodu 0x%04llX", pid]];
    }
    if (sop && Number(sop, @"Specification Revision") > 0) {
        [detail addObject:[NSString stringWithFormat:@"PD %lld.0", Number(sop, @"Specification Revision")]];
    }
    if ([adapter[@"IsWireless"] boolValue]) {
        [detail addObject:@"kablosuz"];
    }
    info.detail = [detail componentsJoinedByString:@" · "];
    info.cable = DescribeCable(sopPrime);
    return info;
}

#pragma mark - Okuma

// AppleSmartBattery'nin tüm sözlüğü (BatteryData, LifetimeData vb.) büyük; yalnızca gereken anahtarlar okunur.
static NSDictionary *BatteryProperties(void) {
    static io_service_t service = IO_OBJECT_NULL;
    if (service == IO_OBJECT_NULL) {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
        if (service == IO_OBJECT_NULL) {
            return nil;
        }
    }
    static NSArray<NSString *> *keys;
    if (keys == nil) {
        keys = @[@"ExternalConnected", @"FullyCharged", @"CurrentCapacity", @"Temperature",
                 @"AvgTimeToEmpty", @"AvgTimeToFull", @"ChargerData", @"PowerTelemetryData",
                 @"Voltage", @"InstantAmperage", @"Amperage", @"AdapterDetails"];
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    for (NSString *key in keys) {
        CFTypeRef value = IORegistryEntryCreateCFProperty(service, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
        if (value) {
            dict[key] = CFBridgingRelease(value);
        }
    }
    if (dict[@"CurrentCapacity"] == nil) {
        // Servis kaybolduysa (çok nadir) bir sonraki çağrıda yeniden bul.
        IOObjectRelease(service);
        service = IO_OBJECT_NULL;
        return nil;
    }
    return dict;
}

BOOL PowerReadSlow(PowerSample *s, BOOL includeCharger) {
    NSDictionary *dict = BatteryProperties();
    if (dict == nil) {
        s.registryOK = NO;
        return NO;
    }
    s.registryOK = YES;

    s.externalConnected = [dict[@"ExternalConnected"] boolValue];
    s.fullyCharged = [dict[@"FullyCharged"] boolValue];
    s.percent = (int)Number(dict, @"CurrentCapacity");
    s.temperatureC = (double)Number(dict, @"Temperature") / 100.0;

    int64_t toEmpty = Number(dict, @"AvgTimeToEmpty");
    int64_t toFull = Number(dict, @"AvgTimeToFull");
    s.minutesToEmpty = (toEmpty > 0 && toEmpty < 65535) ? (int)toEmpty : -1;
    s.minutesToFull = (toFull > 0 && toFull < 65535) ? (int)toFull : -1;

    s.notChargingCode = (uint32_t)NumberIn(dict, @"ChargerData", @"NotChargingReason");
    s.slowChargingCode = (uint32_t)NumberIn(dict, @"ChargerData", @"SlowChargingReason");
    s.inhibitCode = (uint32_t)NumberIn(dict, @"ChargerData", @"ChargerInhibitReason");

    s.regInputV = (double)NumberIn(dict, @"PowerTelemetryData", @"SystemVoltageIn") / 1000.0;
    s.regInputA = (double)NumberIn(dict, @"PowerTelemetryData", @"SystemCurrentIn") / 1000.0;
    s.regInputW = (double)NumberIn(dict, @"PowerTelemetryData", @"SystemPowerIn") / 1000.0;
    s.regSystemW = (double)NumberIn(dict, @"PowerTelemetryData", @"SystemLoad") / 1000.0;
    s.regBatteryV = (double)Number(dict, @"Voltage") / 1000.0;
    int64_t current = Number(dict, @"InstantAmperage");
    if (current == 0) {
        current = Number(dict, @"Amperage");
    }
    s.regBatteryA = (double)current / 1000.0;

    if (!s.externalConnected) {
        s.charger = nil;
    } else if (includeCharger || s.charger == nil) {
        // USB-PD port ağacını taramak pahalı; yalnızca istenince (fiş değişimi, popover açılışı) yapılır.
        s.charger = ReadCharger(dict);
    }
    return YES;
}

static NSString *ReasonFor(PowerSample *s) {
    if (!s.powerConnected) {
        return nil;
    }
    if (s.charging) {
        if (s.slowChargingCode != 0) {
            return s.temperatureC >= 35
                ? [NSString stringWithFormat:@"Yavaş şarj: pil sıcak (%.0f °C)", s.temperatureC]
                : [NSString stringWithFormat:@"Yavaş şarj (sistem kodu 0x%X)", s.slowChargingCode];
        }
        return nil;
    }

    BOOL flag = NO;
    if (SMCReadNonZero("CHTE", &flag) && flag) {
        return @"Şarj bir uygulama tarafından durduruldu (AlDente, battery vb.)";
    }
    if ((SMCReadNonZero("CHIE", &flag) && flag) || (SMCReadNonZero("CH0I", &flag) && flag)) {
        return @"Adaptör devre dışı bırakıldı — Mac pilden besleniyor";
    }
    if (s.fullyCharged || s.percent >= 100) {
        return @"Pil dolu";
    }
    if (s.inhibitCode != 0) {
        return [NSString stringWithFormat:@"Sistem şarjı engelledi (kod 0x%X)", s.inhibitCode];
    }
    if (s.inputW > 1 && s.batteryA < -0.05) {
        return [NSString stringWithFormat:@"Adaptör yetmiyor: giriş %.1f W, tüketim %.1f W", s.inputW, s.systemW];
    }
    if (s.temperatureC >= 35) {
        return [NSString stringWithFormat:@"Pil sıcak (%.0f °C) — soğuyunca devam eder", s.temperatureC];
    }
    if (s.percent >= 75) {
        return @"Büyük olasılıkla Optimize Pil Şarjı (%80'de bekletiyor)";
    }
    if (s.inputW < 1) {
        return @"Adaptörden güç gelmiyor";
    }
    return s.notChargingCode != 0
        ? [NSString stringWithFormat:@"Neden bilinmiyor (sistem kodu 0x%X)", s.notChargingCode]
        : @"Neden bilinmiyor";
}

void PowerReadFast(PowerSample *s) {
    double bv, ba, bw, iv, ia, iw, sw;
    BOOL batteryOK = SMCReadNumber("B0AV", &bv) && SMCReadNumber("B0AC", &ba);
    BOOL inputOK = SMCReadNumber("PDTR", &iw);
    s.fastFromSMC = batteryOK && inputOK;

    if (batteryOK) {
        s.batteryV = bv / 1000.0;
        s.batteryA = ba / 1000.0;
        s.batteryW = SMCReadNumber("B0AP", &bw) ? bw / 1000.0 : s.batteryV * s.batteryA;
    } else {
        s.batteryV = s.regBatteryV;
        s.batteryA = s.regBatteryA;
        s.batteryW = s.batteryV * s.batteryA;
    }

    if (inputOK) {
        s.inputW = iw;
        s.inputV = SMCReadNumber("VD0R", &iv) ? iv : 0;
        s.inputA = SMCReadNumber("ID0R", &ia) ? ia : (s.inputV > 0.5 ? iw / s.inputV : 0);
        // Fiş takılı değilken sensörler birkaç mV/mA gürültü verir.
        if (s.inputV < 1.0) {
            s.inputV = s.inputA = s.inputW = 0;
        }
    } else {
        s.inputV = s.regInputV;
        s.inputA = s.regInputA;
        s.inputW = s.regInputW;
    }

    if (SMCReadNumber("PSTR", &sw) && sw > 0) {
        s.systemW = sw;
    } else {
        s.systemW = s.regSystemW;
    }

    s.powerConnected = s.externalConnected || s.inputV > 4.5;
    s.charging = s.powerConnected && s.batteryA > 0.02;
    s.reason = ReasonFor(s);
}
