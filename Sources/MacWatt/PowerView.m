#import "PowerView.h"

static const CGFloat kContentWidth = 310;

static NSTextField *Caption(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

static NSTextField *Value(NSString *text, BOOL bold) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedDigitSystemFontOfSize:19
                                                  weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    return label;
}

static NSTextField *Plain(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont monospacedDigitSystemFontOfSize:size weight:weight];
    return label;
}

static NSTextField *Wrapping(CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.preferredMaxLayoutWidth = kContentWidth;
    label.selectable = NO;
    return label;
}

static NSBox *Separator(void) {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    return box;
}

static NSStackView *Horizontal(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}

static NSStackView *Vertical(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    return stack;
}

static NSString *FormatMinutes(int minutes) {
    if (minutes < 60) {
        return [NSString stringWithFormat:@"%d dk", minutes];
    }
    return [NSString stringWithFormat:@"%d sa %d dk", minutes / 60, minutes % 60];
}

static NSString *Num(double v) {
    return fabs(v - round(v)) < 0.05 ? [NSString stringWithFormat:@"%.0f", v] : [NSString stringWithFormat:@"%.1f", v];
}

static NSString *ProfileText(ChargerProfile *p) {
    if (p.minVolts > 0 && p.minVolts < p.volts - 0.05) {
        return [NSString stringWithFormat:@"%@ %@–%@ V %@ A", p.kind, Num(p.minVolts), Num(p.volts), Num(p.amps)];
    }
    return [NSString stringWithFormat:@"%@ V %@ A", Num(p.volts), Num(p.amps)];
}

@interface PowerView ()
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *percentLabel;
@property (nonatomic, strong) NSTextField *timeLabel;
@property (nonatomic, strong) NSTextField *reasonLabel;

@property (nonatomic, strong) NSStackView *inputSection;
@property (nonatomic, strong) NSTextField *inputV;
@property (nonatomic, strong) NSTextField *inputA;
@property (nonatomic, strong) NSTextField *inputW;

@property (nonatomic, strong) NSStackView *batterySection;
@property (nonatomic, strong) NSTextField *batteryNote;
@property (nonatomic, strong) NSTextField *batteryV;
@property (nonatomic, strong) NSTextField *batteryA;
@property (nonatomic, strong) NSTextField *batteryW;

@property (nonatomic, strong) NSTextField *systemValue;

@property (nonatomic, strong) NSStackView *chargerSection;
@property (nonatomic, strong) NSBox *chargerSeparator;
@property (nonatomic, strong) NSTextField *chargerName;
@property (nonatomic, strong) NSTextField *chargerDetail;
@property (nonatomic, strong) NSTextField *chargerActive;
@property (nonatomic, strong) NSTextField *chargerProfiles;
@property (nonatomic, strong) NSTextField *chargerCable;

@property (nonatomic, strong) NSTextField *temperatureLabel;
@end

@implementation PowerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self == nil) {
        return nil;
    }
    [self buildLayout];
    return self;
}

- (void)buildLayout {
    self.statusLabel = Plain(@"Okunuyor…", 13, NSFontWeightSemibold);
    self.percentLabel = Plain(@"", 13, NSFontWeightSemibold);
    NSStackView *header = Horizontal(@[self.statusLabel, self.percentLabel], 8);
    header.distribution = NSStackViewDistributionEqualSpacing;

    self.timeLabel = Caption(@"");
    self.reasonLabel = Wrapping(11, NSFontWeightMedium);
    self.reasonLabel.textColor = [NSColor systemOrangeColor];
    NSStackView *headerBlock = Vertical(@[header, self.timeLabel, self.reasonLabel], 2);

    self.inputV = Value(@"—", NO);
    self.inputA = Value(@"—", NO);
    self.inputW = Value(@"—", YES);
    self.inputSection = Vertical(@[Caption(@"Adaptörden Mac'e giriş"),
                                   Horizontal(@[self.inputV, self.inputA, self.inputW], 14)], 3);

    self.batteryNote = Caption(@"");
    self.batteryV = Value(@"—", NO);
    self.batteryA = Value(@"—", NO);
    self.batteryW = Value(@"—", YES);
    self.batterySection = Vertical(@[Horizontal(@[Caption(@"Pil"), self.batteryNote], 6),
                                     Horizontal(@[self.batteryV, self.batteryA, self.batteryW], 14)], 3);

    self.systemValue = Plain(@"—", 12, NSFontWeightRegular);
    NSStackView *systemRow = Horizontal(@[Plain(@"Sistem tüketimi", 12, NSFontWeightRegular), self.systemValue], 8);
    systemRow.distribution = NSStackViewDistributionEqualSpacing;

    self.chargerName = Wrapping(13, NSFontWeightSemibold);
    self.chargerDetail = Wrapping(11, NSFontWeightRegular);
    self.chargerDetail.textColor = [NSColor secondaryLabelColor];
    self.chargerActive = Wrapping(12, NSFontWeightRegular);
    self.chargerProfiles = Wrapping(11, NSFontWeightRegular);
    self.chargerProfiles.textColor = [NSColor secondaryLabelColor];
    self.chargerCable = Wrapping(11, NSFontWeightRegular);
    self.chargerCable.textColor = [NSColor secondaryLabelColor];
    self.chargerSection = Vertical(@[Caption(@"Şarj cihazı"), self.chargerName, self.chargerDetail,
                                     self.chargerActive, self.chargerProfiles, self.chargerCable], 3);
    self.chargerSeparator = Separator();

    self.temperatureLabel = Caption(@"");
    NSButton *quit = [NSButton buttonWithTitle:@"Çıkış" target:NSApp action:@selector(terminate:)];
    quit.controlSize = NSControlSizeSmall;
    quit.bezelStyle = NSBezelStyleRounded;
    NSStackView *footer = Horizontal(@[self.temperatureLabel, quit], 8);
    footer.distribution = NSStackViewDistributionEqualSpacing;

    NSStackView *stack = Vertical(@[
        headerBlock,
        self.inputSection,
        self.batterySection,
        systemRow,
        self.chargerSeparator,
        self.chargerSection,
        Separator(),
        footer,
    ], 11);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
        [stack.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];
    for (NSView *row in stack.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    for (NSView *row in @[header, self.reasonLabel]) {
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    [self updateWithSample:nil];
}

static void SetText(NSTextField *label, NSString *text) {
    label.stringValue = text ?: @"";
    label.hidden = text.length == 0;
}

- (void)updateWithSample:(PowerSample *)s {
    if (s == nil || !s.registryOK) {
        self.statusLabel.stringValue = @"Pil verisi okunamadı";
        self.percentLabel.stringValue = @"";
        SetText(self.timeLabel, nil);
        SetText(self.reasonLabel, nil);
        self.inputSection.hidden = YES;
        self.batterySection.hidden = YES;
        self.chargerSection.hidden = YES;
        self.chargerSeparator.hidden = YES;
        self.systemValue.stringValue = @"—";
        self.temperatureLabel.stringValue = @"";
        return;
    }

    if (s.charging) {
        self.statusLabel.stringValue = @"Şarj oluyor";
    } else if (s.powerConnected) {
        self.statusLabel.stringValue = @"Güç bağlı, şarj olmuyor";
    } else {
        self.statusLabel.stringValue = @"Pilden çalışıyor";
    }
    self.percentLabel.stringValue = [NSString stringWithFormat:@"%%%d", s.percent];

    NSString *time = nil;
    if (s.charging) {
        time = s.minutesToFull > 0 ? [NSString stringWithFormat:@"Dolmasına %@", FormatMinutes(s.minutesToFull)]
                                   : @"Dolma süresi hesaplanıyor…";
    } else if (!s.powerConnected) {
        time = s.minutesToEmpty > 0 ? [NSString stringWithFormat:@"Kalan süre ~%@", FormatMinutes(s.minutesToEmpty)]
                                    : @"Kalan süre hesaplanıyor…";
    }
    SetText(self.timeLabel, time);
    SetText(self.reasonLabel, s.reason);

    self.inputSection.hidden = !s.powerConnected;
    self.inputV.stringValue = [NSString stringWithFormat:@"%.2f V", s.inputV];
    self.inputA.stringValue = [NSString stringWithFormat:@"%.3f A", s.inputA];
    self.inputW.stringValue = [NSString stringWithFormat:@"%.2f W", s.inputW];

    self.batterySection.hidden = NO;
    self.batteryV.stringValue = [NSString stringWithFormat:@"%.2f V", s.batteryV];
    self.batteryA.stringValue = [NSString stringWithFormat:@"%.3f A", s.batteryA];
    self.batteryW.stringValue = [NSString stringWithFormat:@"%+.2f W", s.batteryW];
    if (s.batteryA > 0.02) {
        self.batteryNote.stringValue = @"şarj oluyor";
    } else if (s.batteryA < -0.02) {
        self.batteryNote.stringValue = @"boşalıyor";
    } else {
        self.batteryNote.stringValue = @"beklemede";
    }

    self.systemValue.stringValue = [NSString stringWithFormat:@"%.2f W", s.systemW];

    ChargerInfo *c = s.powerConnected ? s.charger : nil;
    self.chargerSection.hidden = c == nil;
    self.chargerSeparator.hidden = c == nil;
    if (c) {
        SetText(self.chargerName, c.displayName);
        SetText(self.chargerDetail, c.detail);

        NSMutableArray *active = [NSMutableArray array];
        if (c.port) {
            [active addObject:c.port];
        }
        if (c.activeProfile) {
            [active addObject:[NSString stringWithFormat:@"anlaşılan %@ (%@ W)",
                               ProfileText(c.activeProfile), Num(c.activeProfile.watts)]];
        }
        SetText(self.chargerActive, [active componentsJoinedByString:@" · "]);

        NSMutableArray *profiles = [NSMutableArray array];
        for (ChargerProfile *p in c.profiles) {
            [profiles addObject:ProfileText(p)];
        }
        SetText(self.chargerProfiles, profiles.count > 1
                    ? [@"Profiller: " stringByAppendingString:[profiles componentsJoinedByString:@" · "]]
                    : nil);
        SetText(self.chargerCable, c.cable ? [@"Kablo: " stringByAppendingString:c.cable] : nil);
    }

    self.temperatureLabel.stringValue = [NSString stringWithFormat:@"Pil sıcaklığı %.1f °C", s.temperatureC];
}

@end
