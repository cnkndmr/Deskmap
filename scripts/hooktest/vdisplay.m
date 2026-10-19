// Sanal monitör: çalıştığı sürece macOS'a bir ekran ekler, çıkınca kaldırır.
// Kanca testleri gerçek monitör olmadan "monitör takıldı/çıkarıldı" denesin diye.
// Kullanım: vdisplay [saniye] [genişlik] [yükseklik] [seri]   (saniye 0 = SIGTERM'e kadar, en fazla 300;
// başlatan süreç ölünce kendiliğinden kapanır). Seri (varsayılan 1) aynı model iki monitörü
// taklit eder: farklı seri = farklı monitör, aynı seri = EDID'i aynı iki monitör (multimon.sh).
// CGVirtualDisplay özel bir CoreGraphics arayüzü (DeskPad/BetterDisplay de kullanır).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int serialNum;
@property(copy, nonatomic) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@end

static volatile sig_atomic_t stop = 0;
static void onSignal(int sig) { stop = 1; }

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 0;
        unsigned int width = argc > 2 ? atoi(argv[2]) : 1920;
        unsigned int height = argc > 3 ? atoi(argv[3]) : 1080;
        unsigned int serial = argc > 4 ? (unsigned int)strtoul(argv[4], NULL, 0) : 0x0001;
        signal(SIGTERM, onSignal);
        signal(SIGINT, onSignal);

        CGVirtualDisplayDescriptor *desc = [CGVirtualDisplayDescriptor new];
        desc.queue = dispatch_get_main_queue();
        desc.name = @"Deskmap Test Display";
        desc.maxPixelsWide = width;
        desc.maxPixelsHigh = height;
        desc.sizeInMillimeters = CGSizeMake(width * 0.25, height * 0.25);
        desc.vendorID = 0xDE5C;
        desc.productID = 0x0001;
        desc.serialNum = serial;
        desc.terminationHandler = ^(id a, id b) { stop = 1; };

        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:desc];
        if (!display) { fprintf(stderr, "virtual display could not be created\n"); return 1; }
        CGVirtualDisplaySettings *settings = [CGVirtualDisplaySettings new];
        settings.hiDPI = 0;
        settings.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:60]];
        if (![display applySettings:settings]) { fprintf(stderr, "settings rejected\n"); return 1; }
        printf("display %u %ux%u\n", display.displayID, width, height);
        fflush(stdout);

        // Asla açık kalmasın: en fazla MAX_SECONDS, ve başlatan süreç
        // (test betiği) ölürse hemen kapan (ebeveyn launchd'ye geçer).
        const double MAX_SECONDS = 300;
        if (seconds <= 0 || seconds > MAX_SECONDS) seconds = MAX_SECONDS;
        pid_t parent = getppid();
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
        while (!stop && [end timeIntervalSinceNow] > 0 && getppid() == parent && parent != 1) {
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        }
        display = nil;
        printf("removed\n");
    }
    return 0;
}
