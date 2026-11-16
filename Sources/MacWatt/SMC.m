#import "SMC.h"
#import <IOKit/IOKitLib.h>

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCGetKeyInfo = 9 };

static io_connect_t gConnection = IO_OBJECT_NULL;
static NSMutableDictionary<NSNumber *, NSValue *> *gInfoCache;

static uint32_t FourCC(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static BOOL Call(SMCParam *in, SMCParam *out) {
    size_t size = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(gConnection, kSMCHandleYPCEvent,
                                                 in, sizeof(SMCParam), out, &size);
    return kr == KERN_SUCCESS && out->result == 0;
}

BOOL SMCOpen(void) {
    if (gConnection != IO_OBJECT_NULL) {
        return YES;
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) {
        return NO;
    }
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &gConnection);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        gConnection = IO_OBJECT_NULL;
        return NO;
    }
    gInfoCache = [NSMutableDictionary dictionary];
    return YES;
}

static BOOL KeyInfo(uint32_t key, SMCKeyInfo *info) {
    NSValue *cached = gInfoCache[@(key)];
    if (cached != nil) {
        [cached getValue:info size:sizeof(*info)];
        return info->dataSize > 0;
    }
    SMCParam in = {0}, out = {0};
    in.key = key;
    in.data8 = kSMCGetKeyInfo;
    BOOL ok = Call(&in, &out);
    SMCKeyInfo result = ok ? out.keyInfo : (SMCKeyInfo){0};
    gInfoCache[@(key)] = [NSValue valueWithBytes:&result objCType:@encode(SMCKeyInfo)];
    *info = result;
    return ok && result.dataSize > 0;
}

static BOOL ReadRaw(const char *name, SMCKeyInfo *info, uint8_t bytes[32]) {
    if (!SMCOpen()) {
        return NO;
    }
    uint32_t key = FourCC(name);
    if (!KeyInfo(key, info)) {
        return NO;
    }
    SMCParam in = {0}, out = {0};
    in.key = key;
    in.keyInfo.dataSize = info->dataSize;
    in.data8 = kSMCReadKey;
    if (!Call(&in, &out)) {
        return NO;
    }
    memcpy(bytes, out.bytes, 32);
    return YES;
}

BOOL SMCReadNumber(const char *name, double *out) {
    SMCKeyInfo info;
    uint8_t b[32];
    if (!ReadRaw(name, &info, b)) {
        return NO;
    }
    uint32_t le32 = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    uint16_t le16 = (uint16_t)(b[0] | (b[1] << 8));
    uint32_t type = info.dataType;
    if (type == FourCC("flt ")) {
        float f;
        memcpy(&f, b, sizeof(f));
        *out = f;
    } else if (type == FourCC("si8 ")) {
        *out = (int8_t)b[0];
    } else if (type == FourCC("ui8 ")) {
        *out = b[0];
    } else if (type == FourCC("si16")) {
        *out = (int16_t)le16;
    } else if (type == FourCC("ui16")) {
        *out = le16;
    } else if (type == FourCC("si32")) {
        *out = (int32_t)le32;
    } else if (type == FourCC("ui32")) {
        *out = le32;
    } else {
        return NO;
    }
    return YES;
}

BOOL SMCReadNonZero(const char *name, BOOL *out) {
    SMCKeyInfo info;
    uint8_t b[32];
    if (!ReadRaw(name, &info, b)) {
        return NO;
    }
    BOOL nonZero = NO;
    for (uint32_t i = 0; i < info.dataSize && i < 32; i++) {
        if (b[i] != 0) {
            nonZero = YES;
        }
    }
    *out = nonZero;
    return YES;
}
