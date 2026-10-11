#import <UIKit/UIKit.h>
#import "MMRootController.h"
#import "MMLoginController.h"
#import "MMSpotify.h"

@interface MMAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation MMAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    if ([MMSpotify hasStoredCreds]) {
        // Schon gekoppelt: sofort in die App (kein kurzes Aufblitzen des Login-Bildschirms).
        // Die Anmeldung läuft unsichtbar im Hintergrund; ohne Netz verbindet sie sich später selbst neu.
        self.window.rootViewController = [[MMRootController alloc] init];
        [MMSpotify startNetworkWatch];
        if ([MMSpotify networkReachable])
            [MMSpotify loginStoredWithCompletion:^(BOOL ok, NSString *u, NSString *e) {
                if (!ok && [MMSpotify lastLoginRejected]) [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil];
            }];
    } else {
        // Noch nie gekoppelt: Code-Login (spotify.com/pair)
        self.window.rootViewController = [[MMLoginController alloc] init];
    }
    [self.window makeKeyAndVisible];
    // Persönliche Daten abgelaufen -> automatisch Code-Login (spotify.com/pair) zeigen
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(authExpired) name:@"MMAuthExpired" object:nil];
    return YES;
}

- (void)authExpired {
    static NSTimeInterval last = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if ([self.window.rootViewController isKindOfClass:[MMLoginController class]] || now - last < 30) return;   // nicht mehrfach
    last = now;
    MMLoginController *lc = [[MMLoginController alloc] init];
    lc.forcePairing = YES;
    self.window.rootViewController = lc;
}
@end
