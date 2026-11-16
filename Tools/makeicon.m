#import <Cocoa/Cocoa.h>

static const CGFloat kCanvas = 1024.0;

int main(void) {
    @autoreleasepool {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:(NSInteger)kCanvas
                                                                        pixelsHigh:(NSInteger)kCanvas
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:context];

        NSRect canvas = NSMakeRect(0, 0, kCanvas, kCanvas);
        [[NSColor clearColor] setFill];
        NSRectFill(canvas);

        CGFloat inset = 100.0;
        NSRect body = NSInsetRect(canvas, inset, inset);
        NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:body
                                                                xRadius:185
                                                                yRadius:185];

        NSGradient *fill = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithSRGBRed:0.20 green:0.62 blue:1.00 alpha:1.0],
            [NSColor colorWithSRGBRed:0.04 green:0.28 blue:0.78 alpha:1.0],
        ]];
        [fill drawInBezierPath:squircle angle:-90];

        [squircle addClip];
        NSGradient *sheen = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithWhite:1.0 alpha:0.22],
            [NSColor colorWithWhite:1.0 alpha:0.0],
        ]];
        [sheen drawInRect:NSMakeRect(0, kCanvas * 0.55, kCanvas, kCanvas * 0.45) angle:-90];

        const CGFloat scale = 0.72;
        CGFloat center = kCanvas / 2.0;
        NSBezierPath *bolt = [NSBezierPath bezierPath];
        CGFloat xs[] = {0.610, 0.285, 0.455, 0.365, 0.755, 0.565};
        CGFloat ys[] = {0.930, 0.470, 0.470, 0.070, 0.545, 0.545};
        for (int i = 0; i < 6; i++) {
            CGFloat x = center + (xs[i] * kCanvas - center) * scale;
            CGFloat y = center + (ys[i] * kCanvas - center) * scale;
            if (i == 0) {
                [bolt moveToPoint:NSMakePoint(x, y)];
            } else {
                [bolt lineToPoint:NSMakePoint(x, y)];
            }
        }
        [bolt closePath];
        bolt.lineJoinStyle = NSLineJoinStyleRound;
        bolt.lineWidth = 18;

        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [NSColor colorWithWhite:0.03 alpha:0.20];
        shadow.shadowBlurRadius = 18;
        shadow.shadowOffset = NSMakeSize(0, -6);
        [shadow set];

        [[NSColor whiteColor] setFill];
        [bolt fill];

        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *output = (NSProcessInfo.processInfo.arguments.count > 1)
                               ? NSProcessInfo.processInfo.arguments[1]
                               : @"AppIcon-1024.png";
        if (![png writeToFile:output atomically:YES]) {
            fprintf(stderr, "yazılamadı: %s\n", output.UTF8String);
            return 1;
        }
    }
    return 0;
}
