// spotauth.m — holt lokal einen Spotify-OAuth-Access-Token (scope=streaming) per PKCE.
// Öffnet den Browser, du loggst dich bei Spotify ein, der Token landet in ~/.spotify-token.
// Läuft nur auf DEINEM Rechner; weder Passwort noch Token verlassen das Gerät.
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <CommonCrypto/CommonCrypto.h>

static NSString *b64url(NSData *d){
    NSString *s=[d base64EncodedStringWithOptions:0];
    s=[s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s=[s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    s=[s stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return s;
}
int main(){ @autoreleasepool{
    NSString *clientId=[[NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".spotify-clientid"] encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!clientId.length){ printf("keine ~/.spotify-clientid\n"); return 1; }
    int port=5588; NSString *redirect=[NSString stringWithFormat:@"http://127.0.0.1:%d/login",port];

    // PKCE
    unsigned char vb[48]; for(int i=0;i<48;i++)vb[i]=arc4random()&0xff;
    NSString *verifier=b64url([NSData dataWithBytes:vb length:48]);
    unsigned char ch[CC_SHA256_DIGEST_LENGTH];
    NSData *vd=[verifier dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(vd.bytes,(CC_LONG)vd.length,ch);
    NSString *challenge=b64url([NSData dataWithBytes:ch length:CC_SHA256_DIGEST_LENGTH]);

    NSString *authURL=[NSString stringWithFormat:
      @"https://accounts.spotify.com/authorize?client_id=%@&response_type=code&redirect_uri=%@&scope=streaming%%20user-read-private%%20user-read-email%%20user-library-read%%20user-library-modify%%20playlist-read-private%%20playlist-read-collaborative%%20playlist-modify-private%%20playlist-modify-public%%20user-read-recently-played%%20user-top-read&code_challenge_method=S256&code_challenge=%@",
      clientId,
      [redirect stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
      challenge];

    // lokalen Redirect-Server starten
    int srv=socket(AF_INET,SOCK_STREAM,0); int one=1; setsockopt(srv,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    struct sockaddr_in a; memset(&a,0,sizeof(a)); a.sin_family=AF_INET; a.sin_port=htons(port); a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(srv,(struct sockaddr*)&a,sizeof(a))!=0){printf("Port %d belegt\n",port);return 1;}
    listen(srv,1);

    printf("\n>>> Öffne den Browser und logge dich bei Spotify ein …\n");
    system([[NSString stringWithFormat:@"open '%@'",authURL] UTF8String]);

    // auf Redirect warten
    int c=accept(srv,NULL,NULL); char buf[4096]; int n=(int)read(c,buf,sizeof(buf)-1); buf[n>0?n:0]=0;
    NSString *req=[NSString stringWithUTF8String:buf];
    NSString *code=nil; NSRange r=[req rangeOfString:@"code="];
    if(r.location!=NSNotFound){ NSString *rest=[req substringFromIndex:r.location+5];
        NSRange e=[rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"& "]];
        code=e.location!=NSNotFound?[rest substringToIndex:e.location]:rest; }
    char *resp="HTTP/1.1 200 OK\r\nContent-Type:text/html\r\n\r\n<h2>Fertig — zurueck zum Terminal.</h2>";
    write(c,resp,strlen(resp)); close(c); close(srv);
    if(!code){printf("kein code erhalten\n");return 1;}

    // Code -> Access-Token
    NSString *body=[NSString stringWithFormat:@"grant_type=authorization_code&code=%@&redirect_uri=%@&client_id=%@&code_verifier=%@",
        code,[redirect stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],clientId,verifier];
    NSMutableURLRequest *tr=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"]];
    tr.HTTPMethod=@"POST"; [tr setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    tr.HTTPBody=[body dataUsingEncoding:NSUTF8StringEncoding];
    NSData *td=[NSURLConnection sendSynchronousRequest:tr returningResponse:NULL error:NULL];
    NSDictionary *j=td?[NSJSONSerialization JSONObjectWithData:td options:0 error:NULL]:nil;
    NSString *tok=j[@"access_token"];
    if(!tok){printf("Token-Austausch fehlgeschlagen: %s\n", td?[[NSString alloc] initWithData:td encoding:NSUTF8StringEncoding].UTF8String:"(nichts)");return 1;}
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@".spotify-datatoken"];
    [tok writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *rt=j[@"refresh_token"];
    if(rt.length)[rt writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@".spotify-datarefresh"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    printf("\n✅ User-Token + Refresh gespeichert: %s\n", path.UTF8String);
    printf("   access.len=%lu refresh.len=%lu\n",(unsigned long)tok.length,(unsigned long)rt.length);
    return 0;
}}
