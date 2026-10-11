#import "MMKeepAlive.h"
#import "MMSpotify.h"
#import "MMAudio.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static AVAudioPlayer *gSilence;

// 1 s Stille als WAV (16 kHz mono)
static NSURL* silenceFile(void){
    NSString*path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"mm-silence.wav"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
        int rate=16000, n=rate; NSMutableData*w=[NSMutableData data];
        void (^u32)(uint32_t)=^(uint32_t v){ [w appendBytes:&v length:4]; }; void (^u16)(uint16_t)=^(uint16_t v){ [w appendBytes:&v length:2]; };
        [w appendBytes:"RIFF" length:4]; u32(36+n*2); [w appendBytes:"WAVEfmt " length:8];
        u32(16); u16(1); u16(1); u32(rate); u32(rate*2); u16(2); u16(16); [w appendBytes:"data" length:4]; u32(n*2);
        [w appendData:[NSMutableData dataWithLength:n*2]];
        [w writeToFile:path atomically:YES];
    }
    return [NSURL fileURLWithPath:path];
}

@implementation MMKeepAlive
+ (BOOL)enabled { id v=[[NSUserDefaults standardUserDefaults] objectForKey:@"bgDownload"]; return v?[v boolValue]:YES; }
+ (void)setEnabled:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"bgDownload"]; [[NSUserDefaults standardUserDefaults] synchronize];
    if(!on) [self stop];
}
static BOOL enoughPower(void){
    UIDevice*d=[UIDevice currentDevice]; d.batteryMonitoringEnabled=YES;
    UIDeviceBatteryState st=d.batteryState;
    if(st==UIDeviceBatteryStateCharging||st==UIDeviceBatteryStateFull) return YES;
    return d.batteryLevel<0 || d.batteryLevel>0.2;
}
+ (void)start {
    static dispatch_once_t o; dispatch_once(&o, ^{
        NSNotificationCenter*nc=[NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification*n){ [self check]; }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification*n){ [self stop]; }];
        for(NSString*k in @[@"MMDownloadDone",@"MMDownloadFull",@"MMDownloadError"])
            [nc addObserverForName:k object:nil queue:nil usingBlock:^(NSNotification*n){ [self stop]; }];
        [nc addObserverForName:@"MMDownloadProgress" object:nil queue:nil usingBlock:^(NSNotification*n){
            if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground) [self check]; }];
    });
}
// Im Hintergrund: Stille an, wenn geladen wird, keine Musik läuft und genug Akku da ist
+ (void)check {
    BOOL need=[self enabled] && [MMSpotify isDownloading] && ![MMAudio isPlaying] && enoughPower();
    if(need && !gSilence.playing){
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
        [[AVAudioSession sharedInstance] setActive:YES error:NULL];
        gSilence=[[AVAudioPlayer alloc] initWithContentsOfURL:silenceFile() error:NULL];
        gSilence.numberOfLoops=-1; gSilence.volume=0.0; [gSilence play];
        NSLog(@"[keepalive] Download läuft im Hintergrund weiter");
    } else if(!need && gSilence) [self stop];
}
+ (void)stop { if(gSilence){ [gSilence stop]; gSilence=nil; NSLog(@"[keepalive] aus"); } }
@end
