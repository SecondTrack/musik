#import <UIKit/UIKit.h>
@interface MMLoginController : UIViewController
// YES: gespeicherte Anmeldung überspringen und direkt den Code-Login (spotify.com/pair) zeigen
@property (nonatomic) BOOL forcePairing;
@end
