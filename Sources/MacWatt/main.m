#import <Cocoa/Cocoa.h>
#import <IOKit/ps/IOPowerSources.h>
#import "PowerReader.h"
#import "PowerView.h"

// SMC değerleri ~1 sn'de bir değişiyor; yarım saniyede bir okumak yeni değeri en geç 0.5 sn gecikmeyle gösterir.
static const NSTimeInterval kFastInterval = 0.5;
// Adaptör, kalan süre, sıcaklık gibi yavaş değişen IORegistry alanları.
static const NSTimeInterval kSlowInterval = 3.0;

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (void)powerSourceChanged;
@end

static AppDelegate *gDelegate = nil;

static void PowerSourceCallback(void *context) {
    [gDelegate powerSourceChanged];
}

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) PowerView *powerView;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) PowerSample *sample;
@property (nonatomic) CFAbsoluteTime lastSlowRead;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.sample = [[PowerSample alloc] init];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    button.target = self;
    button.action = @selector(togglePopover:);

    self.powerView = [[PowerView alloc] initWithFrame:NSMakeRect(0, 0, 338, 10)];
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = self.powerView;

    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = controller;
    self.popover.behavior = NSPopoverBehaviorTransient;

    CFRunLoopSourceRef source = IOPSNotificationCreateRunLoopSource(PowerSourceCallback, NULL);
    if (source) {
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFRelease(source);
    }

    [self refresh:YES];

    self.timer = [NSTimer timerWithTimeInterval:kFastInterval
                                         target:self
                                       selector:@selector(tick)
                                       userInfo:nil
                                        repeats:YES];
    self.timer.tolerance = 0.05;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)powerSourceChanged {
    // Fiş takıldı/çıktı: adaptör bilgisi kısa sürede yerleşir, bir kez daha oku.
    [self refresh:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refresh:YES];
    });
}

- (void)tick {
    [self refresh:NO];
}

- (void)refresh:(BOOL)forceSlow {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (forceSlow || now - self.lastSlowRead >= kSlowInterval) {
        PowerReadSlow(self.sample);
        self.lastSlowRead = now;
    }
    PowerReadFast(self.sample);
    [self render];
}

- (void)togglePopover:(id)sender {
    if (self.popover.shown) {
        [self.popover performClose:nil];
        return;
    }
    [self refresh:YES];
    NSStatusBarButton *button = self.statusItem.button;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)render {
    PowerSample *s = self.sample;

    [self.powerView updateWithSample:s];
    NSSize fitting = self.powerView.fittingSize;
    if (fitting.width > 0 && fitting.height > 0 && !NSEqualSizes(fitting, self.popover.contentSize)) {
        self.popover.contentSize = fitting;
    }

    NSStatusBarButton *button = self.statusItem.button;
    if (!s.registryOK) {
        button.title = @"—";
        button.toolTip = @"Pil verisi okunamadı";
        return;
    }

    // Menü çubuğu yalnızca metin: adaptördeyken giriş gücü, pildeyken eksi işaretli tüketim.
    NSString *title = s.powerConnected
        ? [NSString stringWithFormat:@"%.1fW", s.inputW]
        : [NSString stringWithFormat:@"−%.1fW", fabs(s.batteryW)];
    if (![button.title isEqualToString:title]) {
        button.title = title;
    }

    NSMutableString *tip = [NSMutableString stringWithFormat:@"%%%d", s.percent];
    if (s.reason) {
        [tip appendFormat:@" — %@", s.reason];
    }
    [tip appendFormat:@"\nGiriş %.2f V / %.3f A / %.2f W\nPil %.2f V / %.3f A / %+.2f W",
                      s.inputV, s.inputA, s.inputW, s.batteryV, s.batteryA, s.batteryW];
    if (s.powerConnected && s.charger) {
        [tip appendFormat:@"\n%@", s.charger.displayName];
    }
    button.toolTip = tip;
}

@end

static void PrintSample(void) {
    PowerSample *s = [[PowerSample alloc] init];
    if (!PowerReadSlow(s)) {
        printf("Pil verisi okunamadı\n");
        return;
    }
    PowerReadFast(s);
    const char *status = s.charging ? "şarj oluyor" : (s.powerConnected ? "güç bağlı, şarj olmuyor" : "pilden çalışıyor");
    printf("Durum:    %s (%%%d)%s\n", status, s.percent, s.fastFromSMC ? "" : "  [SMC yok, IORegistry]");
    if (s.reason) {
        printf("Neden:    %s\n", s.reason.UTF8String);
    }
    if (s.charging && s.minutesToFull > 0) {
        printf("Dolma:    %d sa %d dk\n", s.minutesToFull / 60, s.minutesToFull % 60);
    } else if (!s.powerConnected && s.minutesToEmpty > 0) {
        printf("Kalan:    %d sa %d dk\n", s.minutesToEmpty / 60, s.minutesToEmpty % 60);
    }
    printf("Giriş:    %6.2f V  %7.3f A  %7.2f W\n", s.inputV, s.inputA, s.inputW);
    printf("Pil:      %6.2f V  %7.3f A  %+7.2f W\n", s.batteryV, s.batteryA, s.batteryW);
    printf("Sistem:   %7.2f W\n", s.systemW);
    ChargerInfo *c = s.charger;
    if (c) {
        printf("Adaptör:  %s\n", c.displayName.UTF8String);
        if (c.detail.length) {
            printf("          %s\n", c.detail.UTF8String);
        }
        if (c.port) {
            printf("Port:     %s\n", c.port.UTF8String);
        }
        for (ChargerProfile *p in c.profiles) {
            printf("  %s %-6s %5.1f-%5.1f V  %5.2f A  %6.1f W\n", p.active ? "*" : " ", p.kind.UTF8String,
                   p.minVolts, p.volts, p.amps, p.watts);
        }
        if (c.cable) {
            printf("Kablo:    %s\n", c.cable.UTF8String);
        }
    }
    printf("Sıcaklık: %.1f °C\n", s.temperatureC);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--print") == 0) {
                PrintSample();
                return 0;
            }
        }
    }

    NSApplication *application = [NSApplication sharedApplication];
    gDelegate = [[AppDelegate alloc] init];
    application.delegate = gDelegate;
    [application run];
    return 0;
}
