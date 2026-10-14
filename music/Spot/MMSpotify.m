#import "MMSpotify.h"
#import "MMAudio.h"
#import "shannon.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netdb.h>
#import <unistd.h>
#import <string.h>
#import <arpa/inet.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "mbedtls/bignum.h"
#import "mbedtls/ssl.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/ctr_drbg.h"
#import "mbedtls/entropy.h"

static const unsigned char DH_PRIME[96]={
 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xc9,0x0f,0xda,0xa2,0x21,0x68,0xc2,0x34,
 0xc4,0xc6,0x62,0x8b,0x80,0xdc,0x1c,0xd1,0x29,0x02,0x4e,0x08,0x8a,0x67,0xcc,0x74,
 0x02,0x0b,0xbe,0xa6,0x3b,0x13,0x9b,0x22,0x51,0x4a,0x08,0x79,0x8e,0x34,0x04,0xdd,
 0xef,0x95,0x19,0xb3,0xcd,0x3a,0x43,0x1b,0x30,0x2b,0x0a,0x6d,0xf2,0x5f,0x14,0x37,
 0x4f,0xe1,0x35,0x6d,0x6d,0x51,0xc2,0x45,0xe4,0x85,0xb5,0x76,0x62,0x5e,0x7e,0xc6,
 0xf4,0x4c,0x42,0xe9,0xa6,0x3a,0x36,0x20,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};

static void pvar(NSMutableData*d,uint64_t v){unsigned char b;do{b=v&0x7f;v>>=7;if(v)b|=0x80;[d appendBytes:&b length:1];}while(v);}
static void ptag(NSMutableData*d,int f,int wt){pvar(d,((uint64_t)f<<3)|wt);}
static void pbytes(NSMutableData*d,int f,NSData*v){ptag(d,f,2);pvar(d,v.length);[d appendData:v];}
static void pvarf(NSMutableData*d,int f,uint64_t v){ptag(d,f,0);pvar(d,v);}
static void pmsg(NSMutableData*d,int f,NSData*m){ptag(d,f,2);pvar(d,m.length);[d appendData:m];}
static uint64_t rvar(const unsigned char*b,NSUInteger len,NSUInteger*p){uint64_t r=0;int s=0;while(*p<len){unsigned char c=b[(*p)++];r|=(uint64_t)(c&0x7f)<<s;if(!(c&0x80))break;s+=7;}return r;}
static NSData* psub(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)return v;}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return nil;}
static int rd_all(int s,unsigned char*b,int n){int t=0;while(t<n){int r=(int)read(s,b+t,n-t);if(r<=0)return -1;t+=r;}return 0;}

static void slog(NSString*fmt,...);
static NSString*hexd(const unsigned char*b,int n);
static NSData* httpsReq(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut);
static NSString* b64std(NSData*data);
static const unsigned char AUDIO_IV[16]={0x72,0xe0,0x67,0xfb,0xdd,0xcb,0xcf,0x77,0xeb,0xe8,0xbc,0x64,0x3f,0x63,0x0d,0x93};
static void pstr(NSMutableData*d,int f,NSString*s){pbytes(d,f,[s dataUsingEncoding:NSUTF8StringEncoding]);}
static NSArray* psubs(NSData*m,int want){NSMutableArray*out=[NSMutableArray array];const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)[out addObject:v];}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return out;}
static int64_t pvarval(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==0){uint64_t v=rvar(b,len,&pos);if(f==want)return v;}
  else if(wt==2){uint64_t l=rvar(b,len,&pos);pos+=l;}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return -1;}

// base62 -> 16-Byte gid (klein-zuerst-Alphabet!)
static void base62ToGid(NSString*b62,unsigned char gid[16]){
    const char*A="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    unsigned char acc[16]={0};
    for(NSUInteger i=0;i<b62.length;i++){const char*q=strchr(A,(char)[b62 characterAtIndex:i]);int d=q?(int)(q-A):0;int carry=d;
        for(int j=15;j>=0;j--){int v=acc[j]*62+carry;acc[j]=v&0xff;carry=v>>8;}}
    memcpy(gid,acc,16);
}

// ---- Session-Zustand (bleibt nach Login offen) ----
static int gSock=-1; static shn_ctx gSnd,gRcv; static uint32_t gSend=0,gRecv=0; static uint64_t gMercSeq=1;
static NSString*gToken=nil; static NSString*gClientToken=nil; static NSString*gSpclient=nil;
static BOOL gLoading=NO;
static void sendpkt(int cmd,NSData*payload){
    NSMutableData*p=[NSMutableData data];unsigned char c=cmd;[p appendBytes:&c length:1];
    uint16_t l=htons((uint16_t)payload.length);[p appendBytes:&l length:2];[p appendData:payload];
    shn_nonce_u32(&gSnd,gSend++);shn_encrypt(&gSnd,p.mutableBytes,(int)p.length);
    unsigned char mac[4];shn_finish(&gSnd,mac,4);write(gSock,p.bytes,p.length);write(gSock,mac,4);
}
static NSData* recvpkt(int*cmd){
    shn_nonce_u32(&gRcv,gRecv++);
    unsigned char h[3];if(rd_all(gSock,h,3))return nil;shn_decrypt(&gRcv,h,3);
    *cmd=h[0];int len=(h[1]<<8)|h[2];
    unsigned char*pay=malloc(len?len:1);if(len&&rd_all(gSock,pay,len)){free(pay);return nil;}
    if(len)shn_decrypt(&gRcv,pay,len);
    unsigned char mac[4];rd_all(gSock,mac,4);
    NSData*d=[NSData dataWithBytes:pay length:len];free(pay);return d;
}

// ---- Client-Token (HTTPS POST, Anti-Bot) ----
static NSString* getClientToken(void){
    NSMutableData*macos=[NSMutableData data];pstr(macos,1,@"13.4.0");pstr(macos,2,@"MacBookPro18,3");pstr(macos,3,@"arm64");
    NSMutableData*psd=[NSMutableData data];pmsg(psd,3,macos);
    NSMutableData*conn=[NSMutableData data];pmsg(conn,1,psd);pstr(conn,2,@"0123456789abcdef0123456789abcdef01234567");
    NSMutableData*cdr=[NSMutableData data];pstr(cdr,1,@"1.2.52.442.g01c3f6ee");pstr(cdr,2,@"65b708073fc0480ea92a077233ca87bd");pmsg(cdr,3,conn);
    NSMutableData*req=[NSMutableData data];pvarf(req,1,1);pmsg(req,2,cdr);
    NSMutableURLRequest*r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://clienttoken.spotify.com/v1/clienttoken"]];
    r.HTTPMethod=@"POST";[r setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];[r setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];r.HTTPBody=req;
    NSData*resp=[NSURLConnection sendSynchronousRequest:r returningResponse:NULL error:NULL];
    NSData*granted=resp?psub(resp,2):nil; NSData*tok=granted?psub(granted,1):nil;
    return tok?[[NSString alloc] initWithData:tok encoding:NSUTF8StringEncoding]:nil;
}
// ---- spclient HTTPS GET mit Bearer + client-token ----
static NSData* spclientGet(NSString*path){
    NSString*host=gSpclient; NSRange c=[host rangeOfString:@":"]; if(c.location!=NSNotFound) host=[host substringToIndex:c.location];
    NSMutableArray*hdr=[NSMutableArray array];
    if(gToken.length)[hdr addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
    if(gClientToken.length)[hdr addObject:[@"client-token: " stringByAppendingString:gClientToken]];
    int st=0; NSData*d=httpsReq(@"GET",host,path,hdr,nil,&st);
    if(st!=200){slog(@"[spclient] %@ -> HTTP %d",path,st);return nil;}
    return d;
}
// ---- Mercury GET über den AP-Kanal ----
static NSData* mercuryGet(NSString*uri){
    uint64_t seq=gMercSeq++;
    NSMutableData*hdr=[NSMutableData data];pstr(hdr,1,uri);pstr(hdr,3,@"GET");
    NSMutableData*pl=[NSMutableData data];
    uint16_t sl=htons(8);[pl appendBytes:&sl length:2];unsigned char sb[8];for(int i=0;i<8;i++)sb[i]=(seq>>(8*(7-i)))&0xff;[pl appendBytes:sb length:8];
    unsigned char flags=1;[pl appendBytes:&flags length:1];uint16_t cnt=htons(1);[pl appendBytes:&cnt length:2];
    uint16_t hl=htons((uint16_t)hdr.length);[pl appendBytes:&hl length:2];[pl appendData:hdr];
    sendpkt(0xb2,pl);
    for(int tries=0;tries<200;tries++){
        int cmd;NSData*r=recvpkt(&cmd);if(!r)return nil;
        if(cmd==0x04){sendpkt(0x49,r);continue;}
        if(cmd!=0xb2 && cmd!=0xb5)continue;
        const unsigned char*b=r.bytes;NSUInteger pos=0,len=r.length;
        int seqlen=(b[0]<<8)|b[1];pos=2;uint64_t rseq=0;for(int i=0;i<seqlen;i++)rseq=(rseq<<8)|b[pos++];
        pos++;int parts=(b[pos]<<8)|b[pos+1];pos+=2;
        NSMutableArray*pp=[NSMutableArray array];
        for(int i=0;i<parts && pos+2<=len;i++){int plen=(b[pos]<<8)|b[pos+1];pos+=2;[pp addObject:[r subdataWithRange:NSMakeRange(pos,plen)]];pos+=plen;}
        if(rseq!=seq)continue;
        if(pp.count>=2)return pp[1];
        if(pp.count>=1)return pp[0];
        return [NSData data];
    }
    return nil;
}

static NSMutableString*gLog=nil;
// Log: mehrere Threads schreiben gleichzeitig -> gesperrt; nur die letzten 64 KB behalten
static void slog(NSString*fmt,...){
    va_list a; va_start(a,fmt); NSString*s=[[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    static NSObject*lock; static dispatch_once_t o; dispatch_once(&o,^{ lock=[NSObject new]; });
    @synchronized(lock){
        if(!gLog) gLog=[NSMutableString string];
        [gLog appendFormat:@"%@\n",s];
        if(gLog.length>65536) [gLog deleteCharactersInRange:NSMakeRange(0,gLog.length-49152)];
        [gLog writeToFile:@"/var/mobile/.spotify-log" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}
static NSString*hexd(const unsigned char*b,int n){NSMutableString*m=[NSMutableString string];for(int i=0;i<n;i++)[m appendFormat:@"%02x",b[i]];return m;}

@interface MMSpotify ()
+ (BOOL)resolveTrack:(NSString *)b62 cdn:(NSString **)cdnOut key:(NSData **)keyOut err:(NSString **)err;
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err;
+ (NSData *)loadAudioData:(NSString *)b62 err:(NSString **)err;
+ (void)postDlProgress;
+ (void)dlStep;
+ (void)dlFinishTrack:(NSString *)tid;
@end

@implementation MMSpotify

static BOOL gLoginRejected=NO;   // letzte Anmeldung von Spotify abgelehnt (nicht bloß keine Verbindung)
+ (NSString *)doLoginCred:(NSData *)credBlob err:(NSString **)err {
    gLoginRejected=NO;
    // DH-Keypair via mbedtls_mpi
    mbedtls_mpi P,G,X,GC,GS,SH; mbedtls_mpi_init(&P);mbedtls_mpi_init(&G);mbedtls_mpi_init(&X);mbedtls_mpi_init(&GC);mbedtls_mpi_init(&GS);mbedtls_mpi_init(&SH);
    mbedtls_mpi_read_binary(&P,DH_PRIME,96); mbedtls_mpi_lset(&G,2);
    unsigned char xb[95]; for(int i=0;i<95;i++)xb[i]=arc4random()&0xff; mbedtls_mpi_read_binary(&X,xb,95);
    mbedtls_mpi_exp_mod(&GC,&G,&X,&P,NULL); unsigned char gcb[96]; mbedtls_mpi_write_binary(&GC,gcb,96);

    // ClientHello
    NSMutableData*bi=[NSMutableData data];pvarf(bi,10,0);pvarf(bi,30,1);pvarf(bi,40,117300517);
    NSMutableData*dh=[NSMutableData data];pbytes(dh,10,[NSData dataWithBytes:gcb length:96]);pvarf(dh,20,1);
    NSMutableData*lch=[NSMutableData data];pmsg(lch,10,dh);
    unsigned char nn[16];for(int i=0;i<16;i++)nn[i]=arc4random()&0xff;
    NSMutableData*ch=[NSMutableData data];pmsg(ch,10,bi);pvarf(ch,30,0);pmsg(ch,50,lch);pbytes(ch,60,[NSData dataWithBytes:nn length:16]);unsigned char pad=0x1e;pbytes(ch,70,[NSData dataWithBytes:&pad length:1]);
    uint32_t size=2+4+(uint32_t)ch.length;NSMutableData*pkt=[NSMutableData data];unsigned char hd[2]={0,4};[pkt appendBytes:hd length:2];uint32_t be=htonl(size);[pkt appendBytes:&be length:4];[pkt appendData:ch];

    // AP-Verbindung
    gLog=nil; slog(@"=== login %@", [NSDate date]);
    slog(@"cred.len=%lu", (unsigned long)credBlob.length);
    NSData*ad=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=accesspoint"]];
    slog(@"apresolve bytes=%lu", (unsigned long)ad.length);
    NSArray*aps=ad?[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"]:nil;
    slog(@"ap count=%lu", (unsigned long)aps.count);
    if(!aps.count){ if(err)*err=@"kein Netz (apresolve)"; return nil; }
    int s=-1;for(NSString*ap in aps){NSArray*hp=[ap componentsSeparatedByString:@":"];struct hostent*he=gethostbyname([hp[0] UTF8String]);if(!he)continue;int t=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in sa;memset(&sa,0,sizeof(sa));sa.sin_family=AF_INET;sa.sin_port=htons([hp[1] intValue]);memcpy(&sa.sin_addr,he->h_addr,he->h_length);if(connect(t,(struct sockaddr*)&sa,sizeof(sa))==0){s=t;break;}close(t);}
    slog(@"ap socket=%d", s);
    if(s<0){ if(err)*err=@"AP nicht erreichbar"; return nil; }
    write(s,pkt.bytes,pkt.length);NSMutableData*acc=[NSMutableData dataWithData:pkt];

    unsigned char lb[4];if(rd_all(s,lb,4)){close(s);if(err)*err=@"Handshake abgebrochen";return nil;}uint32_t blen=ntohl(*(uint32_t*)lb)-4;
    NSMutableData*body=[NSMutableData dataWithLength:blen];if(rd_all(s,body.mutableBytes,blen)){close(s);if(err)*err=@"Handshake-Body";return nil;}
    [acc appendBytes:lb length:4];[acc appendData:body];
    slog(@"handshake body=%u", blen);
    NSData*gs=psub(psub(psub(psub(body,10),10),10),10);if(!gs){close(s);if(err)*err=@"kein Server-Key";return nil;}
    slog(@"server gs.len=%lu", (unsigned long)gs.length);
    mbedtls_mpi_read_binary(&GS,gs.bytes,(int)gs.length); mbedtls_mpi_exp_mod(&SH,&GS,&X,&P,NULL); unsigned char shb[96]; mbedtls_mpi_write_binary(&SH,shb,96);

    NSMutableData*data=[NSMutableData data];for(unsigned char i=1;i<=5;i++){NSMutableData*m=[NSMutableData dataWithData:acc];[m appendBytes:&i length:1];unsigned char mac[20];CCHmac(kCCHmacAlgSHA1,shb,96,m.bytes,m.length,mac);[data appendBytes:mac length:20];}
    const unsigned char*dd=data.bytes;unsigned char cmac[20];CCHmac(kCCHmacAlgSHA1,dd,20,acc.bytes,acc.length,cmac);
    NSMutableData*dhr=[NSMutableData data];pbytes(dhr,10,[NSData dataWithBytes:cmac length:20]);NSMutableData*lcr=[NSMutableData data];pmsg(lcr,10,dhr);
    NSMutableData*resp=[NSMutableData data];pmsg(resp,10,lcr);pmsg(resp,20,[NSData data]);pmsg(resp,30,[NSData data]);
    uint32_t rsz=htonl(4+(uint32_t)resp.length);NSMutableData*rpkt=[NSMutableData data];[rpkt appendBytes:&rsz length:4];[rpkt appendData:resp];write(s,rpkt.bytes,rpkt.length);

    // Shannon + Login — Session-Kontext bleibt erhalten
    gSock=s; shn_key(&gSnd,dd+20,32);shn_key(&gRcv,dd+52,32);
    NSMutableData*sys=[NSMutableData data];pvarf(sys,10,0);pvarf(sys,60,3);  // os=IPHONE
    NSMutableData*cre=[NSMutableData data];pmsg(cre,10,credBlob);pmsg(cre,50,sys);
    NSMutableData*lp=[NSMutableData data];unsigned char cc=0xab;[lp appendBytes:&cc length:1];uint16_t pl=htons((uint16_t)cre.length);[lp appendBytes:&pl length:2];[lp appendData:cre];
    shn_nonce_u32(&gSnd,0);shn_encrypt(&gSnd,lp.mutableBytes,(int)lp.length);unsigned char sm[4];shn_finish(&gSnd,sm,4);write(s,lp.bytes,lp.length);write(s,sm,4);

    slog(@"login sent, warte auf antwort");
    shn_nonce_u32(&gRcv,0);unsigned char h[3];if(rd_all(s,h,3)){close(s);gSock=-1;slog(@"keine antwort (rd_all h)");if(err)*err=@"keine Login-Antwort";return nil;}shn_decrypt(&gRcv,h,3);
    int rcmd=h[0];int rlen=(h[1]<<8)|h[2]; slog(@"raw hdr %02x %02x %02x -> cmd=0x%02x len=%d",h[0],h[1],h[2],rcmd,rlen); if(rlen<0||rlen>8192){close(s);gSock=-1;if(err)*err=@"Antwort unplausibel";return nil;}
    unsigned char*pay=malloc(rlen?rlen:1);if(rlen&&rd_all(s,pay,rlen)){free(pay);close(s);gSock=-1;if(err)*err=@"Antwort abgebrochen";return nil;}
    if(rlen)shn_decrypt(&gRcv,pay,rlen);unsigned char rmac[4];rd_all(s,rmac,4);
    slog(@"resp cmd=0x%02x len=%d", rcmd, rlen);
    slog(@"resp head=%@", hexd(pay, rlen<48?rlen:48));
    NSString*user=nil;
    if(rcmd==0xac){
        NSData*w=[NSData dataWithBytes:pay length:rlen]; NSData*u=psub(w,10); if(!u)u=psub(w,1);
        if(u)user=[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding];
        if(!user.length)user=@"Spotify";   // Login OK auch ohne lesbaren Namen
        slog(@"APWelcome user=%@", user);
        // Wiederverwendbare Zugangsdaten sichern (Feld 40) -> nie wieder Passwort/Browser
        NSData*reusable=psub(w,40);
        // Anderer (oder unbekannter) Nutzer -> zwischengespeicherte Web-API-Daten des Vorgängers verwerfen
        NSString*prev=[[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-user" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(![prev isEqualToString:user]){
            NSFileManager*fm=[NSFileManager defaultManager];
            for(NSString*f in [fm contentsOfDirectoryAtPath:@"/var/mobile/.spotcache" error:NULL]) if([f hasPrefix:@"api_"]) [fm removeItemAtPath:[@"/var/mobile/.spotcache/" stringByAppendingString:f] error:NULL];
            slog(@"Nutzerwechsel (%@ -> %@): API-Cache geleert", prev?:@"-", user);
        }
        if(reusable.length){ [reusable writeToFile:@"/var/mobile/.spotify-creds" atomically:YES];
            [user writeToFile:@"/var/mobile/.spotify-user" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            slog(@"reusable creds gesichert (%lu B)", (unsigned long)reusable.length); }
    }
    else if(rcmd==0xad){ gLoginRejected=YES; NSData*w=[NSData dataWithBytes:pay length:rlen]; slog(@"AuthFailure body=%@", hexd(w.bytes,(int)(w.length<32?w.length:32))); if(err)*err=@"Login abgelehnt (Token abgelaufen?)"; }
    else { if(err)*err=[NSString stringWithFormat:@"unerwartet (0x%02x)",rcmd]; }
    free(pay);
    mbedtls_mpi_free(&P);mbedtls_mpi_free(&G);mbedtls_mpi_free(&X);mbedtls_mpi_free(&GC);mbedtls_mpi_free(&GS);mbedtls_mpi_free(&SH);
    if(rcmd==0xac){ gSend=1; gRecv=1; return user; }  // Session offen lassen
    close(s); gSock=-1; return nil;
}

+ (BOOL)lastLoginRejected { return gLoginRejected; }

// Serielle Queue: die Session (Socket+Shannon) darf nur von EINEM Thread genutzt werden.
static dispatch_queue_t spotQ(void){
    static dispatch_queue_t q; static dispatch_once_t o;
    dispatch_once(&o, ^{ q=dispatch_queue_create("mesh.spot.session", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// LoginCredentials bauen: Feld 10=username, 20=typ (1=STORED,3=TOKEN), 30=auth_data.
static NSData* credStored(NSString*user,NSData*creds){ NSMutableData*c=[NSMutableData data]; pstr(c,10,user); pvarf(c,20,1); pbytes(c,30,creds); return c; }
static NSData* credToken(NSString*token){ NSMutableData*c=[NSMutableData data]; pvarf(c,20,3); pbytes(c,30,[token dataUsingEncoding:NSUTF8StringEncoding]); return c; }

+ (void)loginWithToken:(NSString *)token completion:(void(^)(BOOL,NSString*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSString *err=nil; NSString *user=[self doLoginCred:credToken(token) err:&err];
        if(user) gToken=token;
        dispatch_async(dispatch_get_main_queue(), ^{ done(user!=nil, user, err); });
    });
}

+ (BOOL)hasStoredCreds {
    NSData*c=[NSData dataWithContentsOfFile:@"/var/mobile/.spotify-creds"];
    NSString*u=[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-user" encoding:NSUTF8StringEncoding error:NULL];
    return c.length>0 && u.length>0;
}

+ (void)loginStoredWithCompletion:(void(^)(BOOL,NSString*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSData*c=[NSData dataWithContentsOfFile:@"/var/mobile/.spotify-creds"];
        NSString*su=[[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-user" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *err=nil, *u=nil;
        if(c.length && su.length) u=[self doLoginCred:credStored(su,c) err:&err];
        else err=@"keine gespeicherten Zugangsdaten";
        dispatch_async(dispatch_get_main_queue(), ^{ done(u!=nil, u, err); });
    });
}

// User-Token (Streaming + persönliche Daten) laden / über Refresh erneuern.
static void loadUserToken(void){
    NSString*ut=[[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-usertoken" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(ut.length) gToken=ut;
}
// Erneuert den Zugang über den Refresh-Token. Spotify tauscht den Refresh-Token dabei aus -> nie zwei Erneuerungen
// gleichzeitig: wer wartet und danach einen neuen Zugang vorfindet, nimmt den (sonst scheitert er mit dem alten Schlüssel).
static BOOL gRefreshDead=NO;            // Spotify hat den Refresh-Token abgelehnt -> nur dann neu koppeln
static NSTimeInterval gRefreshedAt=0;
static BOOL refreshUserToken(void){
    NSString*failed=gToken;                                   // der Zugang, der gerade abgelehnt wurde
    static NSObject*lock; static dispatch_once_t o; dispatch_once(&o,^{ lock=[NSObject new]; });
    @synchronized(lock){
        NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
        if(gToken.length && (![gToken isEqualToString:failed?:@""] || now-gRefreshedAt<20)) return YES;   // ein anderer war schneller
        NSString*rt=[[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-userrefresh" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(!rt.length){ gRefreshDead=YES; return NO; }
        // Playback-Token stammt vom librespot-Client (public PKCE) -> ohne Secret erneuern
        NSArray*hdr=@[@"Content-Type: application/x-www-form-urlencoded"];
        NSString*body=[NSString stringWithFormat:@"grant_type=refresh_token&refresh_token=%@&client_id=65b708073fc0480ea92a077233ca87bd",rt];
        int st=0; NSData*d=httpsReq(@"POST",@"accounts.spotify.com",@"/api/token",hdr,[body dataUsingEncoding:NSUTF8StringEncoding],&st);
        NSDictionary*j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        NSString*at=[j isKindOfClass:[NSDictionary class]]?j[@"access_token"]:nil, *nrt=[j isKindOfClass:[NSDictionary class]]?j[@"refresh_token"]:nil;
        slog(@"refreshUserToken HTTP %d -> %@", st, at.length?@"ok":@"fail");
        if(at.length){
            if(nrt.length)[nrt writeToFile:@"/var/mobile/.spotify-userrefresh" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [at writeToFile:@"/var/mobile/.spotify-usertoken" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            gToken=at; gRefreshedAt=now; gRefreshDead=NO; return YES;
        }
        if(st==400||st==401) gRefreshDead=YES;                // abgelehnt (nicht: kein Netz)
        return NO;
    }
}

static BOOL ensureApi(NSString**err){
    if(gSock<0){ if(err)*err=@"nicht eingeloggt"; return NO; }
    if(!gClientToken){ gClientToken=getClientToken(); }
    if(!gClientToken){ if(err)*err=@"kein client-token"; return NO; }
    if(!gSpclient){
        NSData*spd=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=spclient"]];
        gSpclient=spd?[NSJSONSerialization JSONObjectWithData:spd options:0 error:NULL][@"spclient"][0]:nil;
    }
    if(!gSpclient){ if(err)*err=@"kein spclient-Host"; return NO; }
    return YES;
}

// Session neu aufbauen (gespeicherte Zugangsdaten), wenn die AP-Verbindung abgerissen ist.
static BOOL reconnectStored(void){
    NSData*c=[NSData dataWithContentsOfFile:@"/var/mobile/.spotify-creds"];
    NSString*su=[[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-user" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!c.length||!su.length) return NO;
    if(gSock>=0){ close(gSock); gSock=-1; }
    NSString*e=nil; NSString*u=[MMSpotify doLoginCred:credStored(su,c) err:&e];
    slog(@"reconnect -> %@", u?u:@"fail");
    return u!=nil;
}
// Mercury mit Auto-Reconnect bei abgerissener Session.
static NSData* mercuryRC(NSString*uri){
    NSData*d=mercuryGet(uri);
    if(d.length) return d;
    slog(@"mercury leer -> reconnect");
    if(reconnectStored()) d=mercuryGet(uri);
    return d;
}

// Nur Metadaten (schnell) -> {title, artist, cover-URL}. Session muss offen sein.
+ (NSDictionary *)metaOnly:(NSString *)b62 err:(NSString **)err {
    if(gSock<0 && !reconnectStored()){ if(err)*err=@"nicht eingeloggt"; return nil; }
    unsigned char gidb[16]; base62ToGid(b62,gidb);
    NSData*meta=mercuryRC([NSString stringWithFormat:@"hm://metadata/4/track/%@",hexd(gidb,16)]);
    if(!meta.length){ if(err)*err=@"Metadaten"; return nil; }
    NSString*title=psub(meta,2)?[[NSString alloc] initWithData:psub(meta,2) encoding:NSUTF8StringEncoding]:@"?";
    NSString*artist=@""; NSArray*arts=psubs(meta,4); if(arts.count){NSData*an=psub(arts[0],2); if(an)artist=[[NSString alloc] initWithData:an encoding:NSUTF8StringEncoding];}
    NSString*cover=@""; NSData*album=psub(meta,3);
    if(album){NSData*cg=psub(album,17); if(cg){NSArray*imgs=psubs(cg,1); if(imgs.count){NSData*fid=psub(imgs.lastObject,1); if(fid)cover=[NSString stringWithFormat:@"https://i.scdn.co/image/%@",hexd(fid.bytes,(int)fid.length)];}}}
    return [NSDictionary dictionaryWithObjectsAndKeys:title,@"title",artist,@"artist",cover,@"cover",nil];
}

// ---- Cache: mehrere vorab geladene/entschlüsselte Tracks (LRU) ----
#define CACHE_MAX 2
static NSMutableDictionary *gCache=nil;   // trackId -> NSData (entschlüsseltes Ogg)
static NSMutableArray *gCacheOrder=nil;    // LRU, ältester zuerst
static NSMutableSet *gInflight=nil;        // Tracks, die gerade vorgeladen werden
static void cacheInit(void){ if(!gCache){ gCache=[NSMutableDictionary dictionary]; gCacheOrder=[NSMutableArray array]; gInflight=[NSMutableSet set]; } }
static NSData* cacheGet(NSString*tid){ @synchronized(gCache?:(gCache=[NSMutableDictionary dictionary])){ cacheInit(); NSData*d=gCache[tid]; if(d){ [gCacheOrder removeObject:tid]; [gCacheOrder addObject:tid]; } return d; } }
static void cachePut(NSString*tid,NSData*d){ @synchronized(gCache){ cacheInit(); if(gCache[tid])[gCacheOrder removeObject:tid]; gCache[tid]=d; [gCacheOrder addObject:tid]; while(gCacheOrder.count>CACHE_MAX){ NSString*old=gCacheOrder[0]; [gCacheOrder removeObjectAtIndex:0]; [gCache removeObjectForKey:old]; } } }
// ---- Offline-Disk-Cache (heruntergeladene Playlists) ----
static NSString* diskDir(void){ NSString*d=@"/var/mobile/.spotcache"; [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL]; return d; }
static NSString* diskPath(NSString*tid){ return [NSString stringWithFormat:@"%@/%@.ogg", diskDir(), tid]; }
static BOOL diskHas(NSString*tid){ return tid.length && [[NSFileManager defaultManager] fileExistsAtPath:diskPath(tid)]; }

// Volle Audio-Kette: Datei + AudioKey + CDN(voll) + Entschlüsseln -> entschlüsseltes Ogg (nil bei Fehler).
// Läuft IMMER auf spotQ (Socket ist single-threaded).
// Nur der SOCKET-Teil (Metadaten + AudioKey + CDN-Adresse). MUSS auf spotQ laufen (ein Socket).
// Liefert die CDN-URL + den 16-Byte-AES-Key. Der große Download passiert danach woanders.
+ (BOOL)resolveTrack:(NSString *)b62 cdn:(NSString **)cdnOut key:(NSData **)keyOut err:(NSString **)err {
    slog(@"resolve %@ (sock=%d)", b62, gSock);
    if(gSock<0 && !reconnectStored()){ if(err)*err=@"nicht eingeloggt"; return NO; }
    if(!ensureApi(err)){ slog(@"resolve ensureApi fail"); return NO; }
    unsigned char gidb[16]; base62ToGid(b62,gidb);
    NSData*meta=mercuryRC([NSString stringWithFormat:@"hm://metadata/4/track/%@",hexd(gidb,16)]);
    if(!meta.length){ if(err)*err=@"Metadaten"; return NO; }
    NSData*fileId=nil;int bestFmt=-1;unsigned char keyGid[16];memcpy(keyGid,gidb,16);
    for(NSData*af in psubs(meta,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
        if(fid&&(fmt==0||fmt==1||fmt==2)&&(int)fmt>bestFmt){bestFmt=(int)fmt;fileId=fid;}}
    if(!fileId){for(NSData*alt in psubs(meta,13)){NSData*ag=psub(alt,1);
        for(NSData*af in psubs(alt,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
            if(fid&&(fmt==0||fmt==1||fmt==2)&&(int)fmt>bestFmt){bestFmt=(int)fmt;fileId=fid;if(ag.length==16)memcpy(keyGid,ag.bytes,16);}}
        if(fileId)break;}}
    if(!fileId){ if(err)*err=@"kein spielbares File"; return NO; }

    static uint32_t gAkSeq=0; uint32_t myseq=++gAkSeq;   // eindeutige Sequenz pro Key-Anfrage (seriell auf spotQ -> kein Race)
    NSMutableData*akr=[NSMutableData data];[akr appendData:fileId];[akr appendBytes:keyGid length:16];
    uint32_t akseq=htonl(myseq);[akr appendBytes:&akseq length:4];uint16_t z=0;[akr appendBytes:&z length:2];
    sendpkt(0x0c,akr);
    unsigned char audiokey[16];int haveKey=0,cmd;
    for(int i=0;i<80;i++){NSData*r=recvpkt(&cmd);if(!r)break;if(cmd==0x04){sendpkt(0x49,r);continue;}
        if(cmd==0x0d && r.length>=20){ uint32_t rs=ntohl(*(const uint32_t*)r.bytes);
            if(rs!=myseq){ slog(@"audiokey stale seq %u != %u -> skip",(unsigned)rs,(unsigned)myseq); continue; }
            memcpy(audiokey,(const unsigned char*)r.bytes+4,16);haveKey=1;break; }
        if(cmd==0x0e){ uint32_t rs=(r.length>=4)?ntohl(*(const uint32_t*)r.bytes):myseq;
            if(rs!=myseq){ continue; }
            slog(@"AesKeyError");break; }}
    if(!haveKey){ if(err)*err=@"kein AudioKey"; return NO; }

    loadUserToken();
    NSString*srp=[NSString stringWithFormat:@"/storage-resolve/files/audio/interactive/%@",hexd(fileId.bytes,(int)fileId.length)];
    NSData*sr=spclientGet(srp);
    if(!sr){ if(refreshUserToken()) sr=spclientGet(srp); }
    NSString*cdn=nil;
    if(sr){ for(NSData*u in psubs(sr,2)){cdn=[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding];break;} }
    if(!cdn.length){ if(err)*err=@"keine CDN-URL"; return NO; }
    if(cdnOut)*cdnOut=cdn; if(keyOut)*keyOut=[NSData dataWithBytes:audiokey length:16];
    slog(@"resolve ok cdn=%@", cdn);
    return YES;
}

// Großer CDN-Download + AES-CTR-Entschlüsselung. Braucht KEINEN Socket -> darf abseits der spotQ laufen.
+ (NSData *)downloadDecrypt:(NSString *)cdn key:(NSData *)keyData err:(NSString **)err {
    NSData*enc=[NSData dataWithContentsOfURL:[NSURL URLWithString:cdn]];
    if(!enc.length){ if(err)*err=@"CDN leer"; return nil; }
    NSMutableData*out=[NSMutableData dataWithLength:enc.length];size_t moved=0;CCCryptorRef cr;
    CCCryptorCreateWithMode(kCCDecrypt,kCCModeCTR,kCCAlgorithmAES,ccNoPadding,AUDIO_IV,keyData.bytes,16,NULL,0,0,kCCModeOptionCTR_BE,&cr);
    CCCryptorUpdate(cr,enc.bytes,enc.length,out.mutableBytes,out.length,&moved);CCCryptorRelease(cr);
    return out;
}

+ (NSData *)loadAudioData:(NSString *)b62 err:(NSString **)err {
    NSString*cdn=nil; NSData*key=nil;
    if(![self resolveTrack:b62 cdn:&cdn key:&key err:err]) return nil;   // Socket-Teil (kurz)
    return [self downloadDecrypt:cdn key:key err:err];                   // großer Download
}

+ (BOOL)doPlay:(NSString *)b62 err:(NSString **)err {
    NSData*out=[self loadAudioData:b62 err:err];
    if(!out.length) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playOgg:out]; });
    return YES;
}

// Track im Voraus laden+entschlüsseln und in den Cache (für nahtlosen Übergang)
+ (void)prefetchTrack:(NSString *)trackId {
    if(!trackId.length) return;
    if(cacheGet(trackId) || diskHas(trackId)) return;   // schon im RAM oder heruntergeladen
    @synchronized(gCache){ cacheInit(); if([gInflight containsObject:trackId]) return; [gInflight addObject:trackId]; }
    dispatch_async(spotQ(), ^{
        if(!cacheGet(trackId)){ NSString*e=nil; NSData*d=[self loadAudioData:trackId err:&e];
            if(d.length){ cachePut(trackId,d); slog(@"prefetch bereit: %@", trackId); } else slog(@"prefetch fail: %@ (%@)",trackId,e); }
        @synchronized(gCache){ [gInflight removeObject:trackId]; }
    });
}

// ---- Offline: Tracks herunterladen / Status ----
+ (BOOL)isDownloaded:(NSString *)trackId { return diskHas(trackId); }
+ (BOOL)allDownloaded:(NSArray *)trackIds {
    if(!trackIds.count) return NO;
    for(NSString*t in trackIds) if(!diskHas(t)) return NO;
    return YES;
}
// ===== Globaler Download-Manager mit Warteschlange =====
// Mehrere Playlists werden hintereinander abgearbeitet (keine zwei Ketten gleichzeitig).
// Pro Track: kurzer Socket-Teil (resolve) auf spotQ, großer Download auf dlDataQ -> Playback bleibt frei.
// Status geht per Notification raus: MMDownloadProgress {done,total}, MMDownloadDone {ok}, MMDownloadFull.
static NSMutableArray *gDlQueue=nil; static BOOL gDlRunning=NO; static NSInteger gDlDone=0, gDlTotal=0; static NSInteger gDlFails=0;
static NSMutableSet *gDlSeen=nil;  // bereits in gDlTotal gezählte Track-IDs (gegen Doppelzählung über mehrere queue-Aufrufe)
// Background-Task: gibt dem Download beim Verlassen der App Gnadenfrist (auch ohne Musikwiedergabe)
static UIBackgroundTaskIdentifier gDlBg=(UIBackgroundTaskIdentifier)NSUIntegerMax;  // ==UIBackgroundTaskInvalid, aber als Compile-Time-Konstante
static void dlBgBegin(void){ dispatch_async(dispatch_get_main_queue(), ^{ if(gDlBg==UIBackgroundTaskInvalid) gDlBg=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ if(gDlBg!=UIBackgroundTaskInvalid){ [[UIApplication sharedApplication] endBackgroundTask:gDlBg]; gDlBg=UIBackgroundTaskInvalid; } }]; }); }
static void dlBgEnd(void){ dispatch_async(dispatch_get_main_queue(), ^{ if(gDlBg!=UIBackgroundTaskInvalid){ [[UIApplication sharedApplication] endBackgroundTask:gDlBg]; gDlBg=UIBackgroundTaskInvalid; } }); }
static dispatch_queue_t dlDataQ(void){ static dispatch_queue_t q; static dispatch_once_t o; dispatch_once(&o,^{ q=dispatch_queue_create("mesh.dl.data",DISPATCH_QUEUE_SERIAL); }); return q; }

+ (BOOL)isDownloading { @synchronized([MMSpotify class]){ return gDlRunning; } }
+ (void)postDlProgress {
    NSInteger d,t; @synchronized([MMSpotify class]){ d=gDlDone; t=gDlTotal; }
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadProgress" object:nil userInfo:@{@"done":@(d),@"total":@(t)}]; });
}
+ (void)queueDownloadTracks:(NSArray *)trackIds {
    if(![trackIds isKindOfClass:[NSArray class]] || !trackIds.count) return;
    BOOL start=NO;
    @synchronized([MMSpotify class]){
        if(!gDlQueue) gDlQueue=[NSMutableArray array];
        if(!gDlSeen) gDlSeen=[NSMutableSet set];
        for(NSString*tid in trackIds){
            if(![tid isKindOfClass:[NSString class]]||!tid.length) continue;
            if([gDlSeen containsObject:tid]) continue;   // schon in dieser Session gezählt
            [gDlSeen addObject:tid]; gDlTotal++;          // zählt in den Nenner (ganze Playlist)
            if(diskHas(tid)){ gDlDone++; }                // schon offline -> auch in den Zähler (Balken bleibt, springt nicht auf 0)
            else [gDlQueue addObject:tid];                // fehlt -> zum Herunterladen einreihen
        }
        if(!gDlRunning){ gDlRunning=YES; start=YES; }
    }
    [self postDlProgress];
    if(start){ dlBgBegin(); [self dlStep]; }
}
+ (void)dlFinishTrack:(NSString *)tid {
    @synchronized([MMSpotify class]){ if(gDlQueue.count && [gDlQueue[0] isEqualToString:tid]) [gDlQueue removeObjectAtIndex:0]; gDlDone++; }
    [self postDlProgress];
    // kleine Pause zwischen Tracks -> senkt Dauer-Stromzug/Wärme (schont schwachen Akku) und lässt Playback durch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)), dispatch_get_global_queue(0,0), ^{ [MMSpotify dlStep]; });
}
+ (void)dlStep {
    NSString*tid=nil; BOOL finished=NO;
    @synchronized([MMSpotify class]){ if(gDlQueue.count==0){ gDlRunning=NO; finished=YES; } else tid=gDlQueue[0]; }
    if(finished){
        NSInteger okc; @synchronized([MMSpotify class]){ okc=gDlDone; gDlDone=0; gDlTotal=0; [gDlSeen removeAllObjects]; }
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadDone" object:nil userInfo:@{@"ok":@(okc)}]; });
        dlBgEnd();
        return;
    }
    dispatch_async(spotQ(), ^{   // NUR der kurze Socket-Teil blockiert spotQ
        @autoreleasepool {
            if(diskHas(tid)){ [MMSpotify dlFinishTrack:tid]; return; }
            if([MMSpotify freeDiskBytes] < 80*1024*1024){   // Platte voll -> abbrechen
                @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; [gDlSeen removeAllObjects]; }
                dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadFull" object:nil userInfo:nil]; });
                dlBgEnd();
                return;
            }
            NSString*cdn=nil; NSData*key=nil; NSString*e=nil;
            if(![MMSpotify resolveTrack:tid cdn:&cdn key:&key err:&e]){
                gDlFails++;
                slog(@"dl resolve fail #%ld %@ (%@)",(long)gDlFails,tid,e);
                BOOL keyIssue = (e && [e rangeOfString:@"AudioKey"].location!=NSNotFound) || (e && [e rangeOfString:@"eingeloggt"].location!=NSNotFound);
                if(keyIssue){
                    // Spotify-Rate-Limit: NICHT überspringen, sondern denselben Track mit Backoff erneut.
                    if(gDlFails>=12){   // trotz Backoff/Reconnect dauerhaft -> sauber stoppen
                        if(gSock>=0){ close(gSock); gSock=-1; }
                        @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; [gDlSeen removeAllObjects]; }
                        gDlFails=0; slog(@"dl ABBRUCH nach 12 Key-Fehlern");
                        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMDownloadError" object:nil userInfo:nil]; });
                        dlBgEnd();
                        return;
                    }
                    if(gDlFails%3==0){ if(gSock>=0){ close(gSock); gSock=-1; } slog(@"dl reconnect (frisches Key-Kontingent)"); }  // alle 3 Fehler neu verbinden
                    double backoff=MIN((double)gDlFails,6.0)*2.5;   // 2.5s..15s hochzählen
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(backoff*NSEC_PER_SEC)), dispatch_get_global_queue(0,0), ^{ [MMSpotify dlStep]; });  // SELBER Track erneut (nicht aus Queue)
                    return;
                }
                gDlFails=0; [MMSpotify dlFinishTrack:tid]; return;   // echtes Track-Problem -> überspringen
            }
            gDlFails=0;   // Erfolg -> Fehlerzähler zurücksetzen
            dispatch_async(dlDataQ(), ^{   // großer Download OHNE spotQ zu blockieren
                @autoreleasepool {
                    NSString*e2=nil; NSData*d=[MMSpotify downloadDecrypt:cdn key:key err:&e2];
                    if(d.length) [d writeToFile:diskPath(tid) atomically:YES];
                    [MMSpotify dlFinishTrack:tid];
                }
            });
        }
    });
}
+ (void)removeDownloads:(NSArray *)trackIds {
    for(NSString*t in trackIds){ if(diskHas(t)) [[NSFileManager defaultManager] removeItemAtPath:diskPath(t) error:NULL]; }
}

// ---- Offline-Playlists dauerhaft merken (für Auto-Resume) ----
static NSString *offlinePath(void){ return [diskDir() stringByAppendingPathComponent:@"offline.plist"]; }
+ (void)markOffline:(NSString *)name trackIds:(NSArray *)trackIds {
    if(!trackIds.count) return;
    @synchronized([MMSpotify class]){
        NSMutableArray *arr=[[NSArray arrayWithContentsOfFile:offlinePath()] mutableCopy]?:[NSMutableArray array];
        for(NSInteger i=(NSInteger)arr.count-1;i>=0;i--){ if([arr[i][@"ids"] isEqualToArray:trackIds] || [arr[i][@"name"] isEqualToString:name?:@""]) [arr removeObjectAtIndex:i]; }
        [arr addObject:@{@"name":name?:@"", @"ids":trackIds}];
        [[NSFileManager defaultManager] createDirectoryAtPath:diskDir() withIntermediateDirectories:YES attributes:nil error:NULL];
        [arr writeToFile:offlinePath() atomically:YES];
    }
}
+ (void)unmarkOffline:(NSArray *)trackIds {
    @synchronized([MMSpotify class]){
        NSMutableArray *arr=[[NSArray arrayWithContentsOfFile:offlinePath()] mutableCopy]; if(!arr) return;
        for(NSInteger i=(NSInteger)arr.count-1;i>=0;i--){ if([arr[i][@"ids"] isEqualToArray:trackIds]) [arr removeObjectAtIndex:i]; }
        [arr writeToFile:offlinePath() atomically:YES];
    }
}
+ (void)resumeOfflineDownloads {
    NSArray *arr=[NSArray arrayWithContentsOfFile:offlinePath()]; if(!arr.count) return;
    // GESAMTE Offline-Liste reichen (nicht nur fehlende): queueDownloadTracks zählt bereits geladene
    // in Zähler+Nenner -> Balken setzt beim Fortsetzen an der echten Prozentzahl an, nicht auf 0.
    NSMutableArray *all=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set]; NSUInteger miss=0;
    for(NSDictionary *e in arr){ if(![e isKindOfClass:[NSDictionary class]])continue;
        for(NSString *tid in e[@"ids"]){ if([tid isKindOfClass:[NSString class]] && tid.length && ![seen containsObject:tid]){ [seen addObject:tid]; [all addObject:tid]; if(!diskHas(tid)) miss++; } } }
    if(miss){ slog(@"resume offline: %lu fehlende von %lu Tracks weiterladen", (unsigned long)miss, (unsigned long)all.count); [self queueDownloadTracks:all]; }
}
+ (long long)freeDiskBytes {
    NSDictionary*a=[[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    NSNumber*n=a[NSFileSystemFreeSize];
    return n?[n longLongValue]:0;
}
+ (long long)cacheBytes {
    NSFileManager*fm=[NSFileManager defaultManager];
    NSArray*files=[fm contentsOfDirectoryAtPath:diskDir() error:NULL];
    long long sum=0;
    for(NSString*f in files){ if(![f hasSuffix:@".ogg"]) continue; NSDictionary*a=[fm attributesOfItemAtPath:[diskDir() stringByAppendingPathComponent:f] error:NULL]; sum+=[a[NSFileSize] longLongValue]; }
    return sum;
}

+ (void)fetchTrack:(NSString *)trackId completion:(void(^)(NSDictionary*,NSString*))done {
    dispatch_async(spotQ(), ^{
        NSString*err=nil; NSDictionary*info=[self metaOnly:trackId err:&err];
        dispatch_async(dispatch_get_main_queue(), ^{ done(info, err); });
    });
}

+ (void)playTrack:(NSString *)trackId completion:(void(^)(BOOL,NSString*))done {
    // Cache-Hit (RAM vorgeladen / Disk heruntergeladen) -> sofort abspielen, kein Netz
    NSData*cd=cacheGet(trackId);
    if(!cd && diskHas(trackId)){ cd=[NSData dataWithContentsOfFile:diskPath(trackId)]; if(cd.length){ cachePut(trackId,cd); slog(@"playTrack Disk-Hit %@",trackId); } }
    if(cd){ gLoading=NO; slog(@"playTrack Cache-Hit %@", trackId);
        dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio playOgg:cd]; if(done)done(YES,nil); });
        return;
    }
    gLoading=YES;
    dispatch_async(dispatch_get_main_queue(), ^{ [MMAudio stop]; });  // alten Track sofort stoppen
    dispatch_async(spotQ(), ^{
        NSString*err=nil; NSData*d=[self loadAudioData:trackId err:&err];
        if(d.length) cachePut(trackId,d);   // gespielten Track auch cachen (zurück = sofort)
        gLoading=NO;
        dispatch_async(dispatch_get_main_queue(), ^{ if(d.length)[MMAudio playOgg:d]; if(done)done(d.length>0,err); });
    });
}

+ (BOOL)isLoading { return gLoading; }

// ---- mbedTLS-HTTPS (iOS-6-TLS zu accounts/api.spotify.com ist zu alt -> selber TLS 1.2) ----
static int mmEntropy(void*d,unsigned char*o,size_t n){ (void)d; for(size_t i=0;i<n;i++)o[i]=arc4random()&0xff; return 0; }
static NSData* dechunk(NSData*d){
    NSMutableData*out=[NSMutableData data]; const unsigned char*b=d.bytes; NSUInteger n=d.length,p=0;
    while(p<n){ NSUInteger e=p; while(e<n && b[e]!='\r')e++; if(e>=n)break;
        char tmp[16]; NSUInteger len=e-p; if(len>15)len=15; memcpy(tmp,b+p,len); tmp[len]=0;
        long sz=strtol(tmp,NULL,16); p=e+2; if(sz<=0)break; if(p+(NSUInteger)sz>n)sz=(long)(n-p);
        [out appendBytes:b+p length:sz]; p+=sz+2; }
    return out;
}
// method GET/POST, extra = Array von Header-Zeilen ("Key: Value"), body optional. statusOut optional.
static NSData* httpsReq(NSString*method,NSString*host,NSString*path,NSArray*extra,NSData*body,int*statusOut){
    if(statusOut)*statusOut=0;
    mbedtls_net_context srv; mbedtls_ssl_context ssl; mbedtls_ssl_config conf; mbedtls_ctr_drbg_context ctr;
    mbedtls_net_init(&srv); mbedtls_ssl_init(&ssl); mbedtls_ssl_config_init(&conf); mbedtls_ctr_drbg_init(&ctr);
    NSData*result=nil; const char*h=[host UTF8String];
    if(mbedtls_ctr_drbg_seed(&ctr,mmEntropy,NULL,(const unsigned char*)"mmspot",6)!=0) goto done;
    if(mbedtls_net_connect(&srv,h,"443",MBEDTLS_NET_PROTO_TCP)!=0){ slog(@"tls: connect %@ fail",host); goto done; }
    if(mbedtls_ssl_config_defaults(&conf,MBEDTLS_SSL_IS_CLIENT,MBEDTLS_SSL_TRANSPORT_STREAM,MBEDTLS_SSL_PRESET_DEFAULT)!=0) goto done;
    mbedtls_ssl_conf_authmode(&conf,MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_rng(&conf,mbedtls_ctr_drbg_random,&ctr);
    if(mbedtls_ssl_setup(&ssl,&conf)!=0) goto done;
    mbedtls_ssl_set_hostname(&ssl,h);
    mbedtls_ssl_set_bio(&ssl,&srv,mbedtls_net_send,mbedtls_net_recv,NULL);
    { int hs; while((hs=mbedtls_ssl_handshake(&ssl))!=0){ if(hs!=MBEDTLS_ERR_SSL_WANT_READ&&hs!=MBEDTLS_ERR_SSL_WANT_WRITE){ slog(@"tls: handshake %@ fail -0x%04x",host,-hs); goto done; } } }
    { NSMutableString*req=[NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n",method,path,host];
      for(NSString*x in extra)[req appendFormat:@"%@\r\n",x];
      [req appendFormat:@"Content-Length: %lu\r\n\r\n",(unsigned long)body.length];
      NSMutableData*rd=[[req dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
      if(body.length)[rd appendData:body];
      const unsigned char*wp=rd.bytes; size_t wl=rd.length,wo=0;
      while(wo<wl){ int w=mbedtls_ssl_write(&ssl,wp+wo,wl-wo); if(w<=0){ if(w==MBEDTLS_ERR_SSL_WANT_READ||w==MBEDTLS_ERR_SSL_WANT_WRITE)continue; goto done; } wo+=w; } }
    { NSMutableData*resp=[NSMutableData data]; unsigned char buf[4096];
      for(;;){ int rr=mbedtls_ssl_read(&ssl,buf,sizeof(buf)); if(rr==MBEDTLS_ERR_SSL_WANT_READ||rr==MBEDTLS_ERR_SSL_WANT_WRITE)continue; if(rr<=0)break; [resp appendBytes:buf length:rr]; }
      NSData*sep=[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
      NSRange sr=[resp rangeOfData:sep options:0 range:NSMakeRange(0,resp.length)];
      if(sr.location!=NSNotFound){
        NSString*hstr=[[NSString alloc] initWithData:[resp subdataWithRange:NSMakeRange(0,sr.location)] encoding:NSUTF8StringEncoding];
        if(statusOut){ NSArray*pp=[hstr componentsSeparatedByString:@" "]; if(pp.count>1)*statusOut=[pp[1] intValue]; }
        NSData*bd=[resp subdataWithRange:NSMakeRange(sr.location+4,resp.length-sr.location-4)];
        if([hstr rangeOfString:@"chunked" options:NSCaseInsensitiveSearch].location!=NSNotFound) bd=dechunk(bd);
        result=bd;
      }
    }
done:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&srv); mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&conf); mbedtls_ctr_drbg_free(&ctr);
    return result;
}

// Standard-Base64 (mit Padding) für Basic-Auth.
static NSString* b64std(NSData*data){
    static const char*t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char*b=data.bytes; NSUInteger n=data.length; NSMutableString*s=[NSMutableString string];
    for(NSUInteger i=0;i<n;i+=3){ int rem=(int)(n-i); unsigned v=(unsigned)b[i]<<16;
        if(rem>1)v|=(unsigned)b[i+1]<<8; if(rem>2)v|=(unsigned)b[i+2];
        [s appendFormat:@"%c",t[(v>>18)&63]]; [s appendFormat:@"%c",t[(v>>12)&63]];
        [s appendFormat:@"%c",(rem>1)?t[(v>>6)&63]:'=']; [s appendFormat:@"%c",(rem>2)?t[v&63]:'=']; }
    return s;
}
// Client-Credentials App-Token (ID+Secret) — für Katalog/Suche, ohne User-Login. Gecacht + erneuert.
#define KEY_ID_PATH  @"/var/mobile/.spotify-clientid"
#define KEY_SEC_PATH @"/var/mobile/.spotify-secret"
static NSString* gAppToken=nil; static NSTimeInterval gAppExp=0;
static NSString* readTrim(NSString*path){
    return [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
// Fragt bei Spotify einen App-Token an. st = HTTP-Status (0 = keine Verbindung).
static NSDictionary* requestAppToken(NSString*cid,NSString*sec,int*st){
    NSString*basic=b64std([[NSString stringWithFormat:@"%@:%@",cid,sec] dataUsingEncoding:NSUTF8StringEncoding]);
    NSArray*hdr=@[[@"Authorization: Basic " stringByAppendingString:basic],@"Content-Type: application/x-www-form-urlencoded"];
    NSData*d=httpsReq(@"POST",@"accounts.spotify.com",@"/api/token",hdr,[@"grant_type=client_credentials" dataUsingEncoding:NSUTF8StringEncoding],st);
    id j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    slog(@"appToken: HTTP %d", *st);
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}
static NSString* appTokenSync(void){
    if(gAppToken && [[NSDate date] timeIntervalSince1970] < gAppExp-60) return gAppToken;
    NSString*cid=readTrim(KEY_ID_PATH), *sec=readTrim(KEY_SEC_PATH);
    if(!cid.length||!sec.length) return nil;
    int st=0; NSDictionary*j=requestAppToken(cid,sec,&st);
    NSString*at=j[@"access_token"]; NSNumber*ex=j[@"expires_in"];
    if(at.length){ gAppToken=at; gAppExp=[[NSDate date] timeIntervalSince1970]+(ex?ex.doubleValue:3600); }
    return gAppToken;
}
+ (BOOL)hasSearchKey { return readTrim(KEY_ID_PATH).length && readTrim(KEY_SEC_PATH).length; }
+ (void)saveSearchKeyId:(NSString *)cid secret:(NSString *)sec completion:(void(^)(BOOL ok, NSString *error))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        int st=0; NSDictionary*j=requestAppToken(cid,sec,&st);
        NSString*at=j[@"access_token"], *err=nil;
        if(at.length){
            NSDictionary*attr=@{NSFilePosixPermissions:@0600};   // nur die App darf den Schlüssel lesen
            NSFileManager*fm=[NSFileManager defaultManager];
            [fm createFileAtPath:KEY_ID_PATH contents:[cid dataUsingEncoding:NSUTF8StringEncoding] attributes:attr];
            [fm createFileAtPath:KEY_SEC_PATH contents:[sec dataUsingEncoding:NSUTF8StringEncoding] attributes:attr];
            NSNumber*ex=j[@"expires_in"]; gAppToken=at; gAppExp=[[NSDate date] timeIntervalSince1970]+(ex?ex.doubleValue:3600);
        }
        else if(st==0) err=NSLocalizedString(@"No connection to Spotify.",nil);
        else if(st==400||st==401) err=NSLocalizedString(@"Spotify doesn't recognize this key. Please check Client ID and Secret.",nil);
        else err=[NSString stringWithFormat:NSLocalizedString(@"Spotify error %d.",nil),st];
        dispatch_async(dispatch_get_main_queue(), ^{ done(at.length>0, err); });
    });
}
+ (void)removeSearchKey {
    [[NSFileManager defaultManager] removeItemAtPath:KEY_ID_PATH error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:KEY_SEC_PATH error:NULL];
    gAppToken=nil; gAppExp=0;
}

// ---- Suche: Web-API mit App-Token (Client-Credentials, nur Katalog, keine Nutzerdaten). Schlüssel liegt NICHT in der App,
//      sondern optional in /var/mobile/.spotify-clientid + .spotify-secret. Fehlt er -> Suche meldet "nicht verfügbar". ----
+ (void)webGet:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSString*at=appTokenSync();
        NSArray*hdr=at.length?@[[@"Authorization: Bearer " stringByAppendingString:at]]:@[];
        int st=0; NSData*d=httpsReq(@"GET",@"api.spotify.com",[@"/v1/" stringByAppendingString:path],hdr,nil,&st);
        if(!at.length) st=401;
        slog(@"webGet %@ -> HTTP %d, %lu B: %.120s", path, st, (unsigned long)d.length, d.length?[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String:"(nil)");
        NSDictionary*j=(d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        if(![j isKindOfClass:[NSDictionary class]]) j=nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(j, st); });
    });
}

// ======================================================================
// Interne Spotify-Server (spclient) — die Web-API (api.spotify.com) gibt dem Login-Token (Client 65b708) nur 429.
// Liefert dieselbe JSON-Form wie die Web-API, damit die Oberfläche unverändert bleibt.
// ======================================================================
#define SP_HOST @"spclient.wg.spotify.com"
static NSString* spUser(void){
    return [[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-user" encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
// HTTPS gegen spclient mit dem Login-Token; bei 401 einmal erneuern und wiederholen.
static NSData* spReq(NSString*method,NSString*path,NSData*body,NSString*ctype,NSString*accept,int*st){
    if(!gToken.length) loadUserToken();
    NSData*(^go)(void)=^NSData*{
        NSMutableArray*h=[NSMutableArray array];
        if(gToken.length)[h addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
        [h addObject:[@"Accept: " stringByAppendingString:accept]];
        if(ctype)[h addObject:[@"Content-Type: " stringByAppendingString:ctype]];
        return httpsReq(method,SP_HOST,path,h,body,st);
    };
    NSData*d=go();
    if((*st==401||!gToken.length) && refreshUserToken()) d=go();
    slog(@"sp %@ %.80@ -> HTTP %d (%lu B)", method, path, *st, (unsigned long)d.length);
    return d;
}
static NSDictionary* spJSON(NSString*path,int*st){
    NSData*d=spReq(@"GET",path,nil,nil,@"application/json",st);
    id j=(*st==200&&d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}
static NSString* b64ToHex(NSString*b64){   // Playlist-"picture" (Base64) -> Hex für i.scdn.co
    if(![b64 isKindOfClass:[NSString class]]||!b64.length) return nil;
    static const char*t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableData*out=[NSMutableData data]; unsigned acc=0; int bits=0;
    for(NSUInteger i=0;i<b64.length;i++){ unichar c=[b64 characterAtIndex:i]; if(c=='=')break;
        const char*p=strchr(t,(char)c); if(!p||!c) continue;
        acc=(acc<<6)|(unsigned)(p-t); bits+=6; if(bits>=8){ bits-=8; unsigned char b=(acc>>bits)&0xff; [out appendBytes:&b length:1]; } }
    return hexd(out.bytes,(int)out.length);
}
static NSString* trackIdFromUri(NSString*u){ return ([u isKindOfClass:[NSString class]]&&[u hasPrefix:@"spotify:track:"])?[u substringFromIndex:14]:nil; }
static NSString* spStr(NSData*d){ return d?([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]?:@""):@""; }

// Titelinfos gesammelt (eine Anfrage pro 100 Titel) -> Web-API-Track-Dicts in Eingabereihenfolge.
static NSArray* spTracks(NSArray*ids){
    NSMutableDictionary*byId=[NSMutableDictionary dictionary];
    for(NSUInteger off=0;off<ids.count;off+=100){
        NSArray*chunk=[ids subarrayWithRange:NSMakeRange(off,MIN((NSUInteger)100,ids.count-off))];
        NSMutableData*req=[NSMutableData data];
        for(NSString*tid in chunk){ NSMutableData*q=[NSMutableData data]; pvarf(q,1,10);   // 10 = TRACK_V4
            NSMutableData*er=[NSMutableData data]; pstr(er,1,[@"spotify:track:" stringByAppendingString:tid]); pmsg(er,2,q); pmsg(req,2,er); }
        int st=0; NSData*d=spReq(@"POST",@"/extended-metadata/v0/extended-metadata",req,@"application/protobuf",@"application/protobuf",&st);
        if(st!=200||!d.length) continue;
        for(NSData*arr in psubs(d,2)) for(NSData*ed in psubs(arr,3)){
            NSString*tid=trackIdFromUri(spStr(psub(ed,2))); NSData*any=psub(ed,3); NSData*tr=any?psub(any,2):nil;
            if(!tid||!tr.length) continue;
            NSString*name=spStr(psub(tr,2)); NSString*artist=@"";
            NSArray*arts=psubs(tr,4); if(arts.count) artist=spStr(psub(arts[0],2));
            NSString*cover=nil; NSData*alb=psub(tr,3); NSData*cg=alb?psub(alb,17):nil;
            for(NSData*im in (cg?psubs(cg,1):@[])){ NSData*fid=psub(im,1); if(!fid) continue;
                NSString*u=[@"https://i.scdn.co/image/" stringByAppendingString:hexd(fid.bytes,(int)fid.length)];
                if(!cover||pvarval(im,2)==0) cover=u; }   // Größe 0 = DEFAULT (~300px)
            byId[tid]=@{@"id":tid,@"name":name,@"artists":@[@{@"name":artist}],@"album":@{@"images":cover?@[@{@"url":cover}]:@[]}};
        }
    }
    NSMutableArray*out=[NSMutableArray array];
    for(NSString*tid in ids){ NSDictionary*t=byId[tid]; if(t)[out addObject:t]; }
    return out;
}
static NSDictionary* qparams(NSString*path){
    NSMutableDictionary*q=[NSMutableDictionary dictionary]; NSRange r=[path rangeOfString:@"?"];
    if(r.location==NSNotFound) return q;
    for(NSString*kv in [[path substringFromIndex:r.location+1] componentsSeparatedByString:@"&"]){
        NSArray*p=[kv componentsSeparatedByString:@"="]; if(p.count==2) q[p[0]]=p[1]; }
    return q;
}
// Lieblingssongs: komplette Sammlung (wenige Anfragen à 300), neueste zuerst; 5 Min im RAM.
static NSArray* gLiked=nil; static NSTimeInterval gLikedAt=0;
static NSArray* spLikedIds(int*st){
    @synchronized([MMSpotify class]){
        if(gLiked && [[NSDate date] timeIntervalSince1970]-gLikedAt<300){ *st=200; return gLiked; }
        NSString*user=spUser(); if(!user.length){ *st=401; return nil; }
        NSMutableArray*items=[NSMutableArray array]; NSData*tok=nil;
        for(int page=0;page<40;page++){
            NSMutableData*req=[NSMutableData data]; pstr(req,1,user); pstr(req,2,@"collection");
            if(tok) pbytes(req,3,tok); pvarf(req,4,300);
            NSString*ct=@"application/vnd.collection-v2.spotify.proto";
            NSData*d=spReq(@"POST",@"/collection/v2/paging",req,ct,ct,st);
            if(*st!=200) return nil;
            for(NSData*it in psubs(d,1)){ NSString*tid=trackIdFromUri(spStr(psub(it,1))); if(tid && !psub(it,3)) [items addObject:@[tid,@(pvarval(it,2))]]; }
            tok=psub(d,2); if(!tok.length) break;
        }
        [items sortUsingComparator:^NSComparisonResult(NSArray*a,NSArray*b){ return [b[1] compare:a[1]]; }];
        NSMutableArray*ids=[NSMutableArray array]; for(NSArray*it in items)[ids addObject:it[0]]; gLiked=ids; gLikedAt=[[NSDate date] timeIntervalSince1970]; *st=200;
        return gLiked;
    }
}
static NSDictionary* trackPage(NSArray*ids,NSUInteger off,NSUInteger lim,NSUInteger total,NSString*nextBase){
    NSArray*slice=(off<ids.count)?[ids subarrayWithRange:NSMakeRange(off,MIN(lim,ids.count-off))]:@[];
    NSMutableArray*items=[NSMutableArray array]; for(NSDictionary*t in spTracks(slice)) [items addObject:@{@"track":t}];
    id next=(off+lim<total)?[NSString stringWithFormat:@"%@offset=%lu",nextBase,(unsigned long)(off+lim)]:[NSNull null];
    return @{@"items":items,@"next":next,@"total":@(total)};
}
// Übersetzt Web-API-GET-Pfade auf spclient. handled=NO -> Pfad unbekannt, normale Web-API nehmen.
static NSDictionary* spInternalGet(NSString*path,int*st,BOOL*handled){
    *handled=YES; NSDictionary*q=qparams(path);
    NSUInteger off=(NSUInteger)[q[@"offset"] integerValue], lim=q[@"limit"]?(NSUInteger)[q[@"limit"] integerValue]:50;
    NSString*user=spUser();
    if([path hasPrefix:@"me/playlists"]){
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/playlist/v2/user/%@/rootlist?decorate=revision,attributes,length,owner&from=0&length=%lu",user,(unsigned long)lim],st);
        if(!j) return nil;
        NSArray*its=j[@"contents"][@"items"], *meta=j[@"contents"][@"metaItems"];
        NSMutableArray*out=[NSMutableArray array];
        // Spotify lässt "length" bei leeren Playlists weg (0 = Standardwert). Nur wenn überhaupt Längen kommen, fehlende als leer werten.
        BOOL haveLen=NO; for(id mi in meta) if([mi isKindOfClass:[NSDictionary class]] && [mi[@"length"] isKindOfClass:[NSNumber class]]){ haveLen=YES; break; }
        for(NSUInteger i=0;i<[its count];i++){
            NSString*u=its[i][@"uri"]; if(![u isKindOfClass:[NSString class]]||![u hasPrefix:@"spotify:playlist:"]) continue;   // Ordner-Marker überspringen
            NSDictionary*mi=(i<[meta count]&&[meta[i] isKindOfClass:[NSDictionary class]])?meta[i]:nil, *a=mi[@"attributes"];
            id len=mi[@"length"];
            if(([len isKindOfClass:[NSNumber class]] && [len integerValue]==0) || (haveLen && !len)) continue;   // leere Playlists gar nicht zeigen
            NSString*hex=b64ToHex(a[@"picture"]);
            NSMutableDictionary*pl=[@{@"id":[u substringFromIndex:17],@"name":[a[@"name"] isKindOfClass:[NSString class]]?a[@"name"]:@"Playlist",
                             @"images":hex?@[@{@"url":[@"https://i.scdn.co/image/" stringByAppendingString:hex]}]:@[]} mutableCopy];
            if([len isKindOfClass:[NSNumber class]]) pl[@"tracks"]=@{@"total":len};
            [out addObject:pl];
        }
        return @{@"items":out};
    }
    if([path hasPrefix:@"playlists/"]){
        NSString*pid=[[path substringFromIndex:10] componentsSeparatedByString:@"?"][0];
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/playlist/v2/playlist/%@?decorate=length&from=%lu&length=%lu",pid,(unsigned long)off,(unsigned long)lim],st);
        if(!j) return nil;
        NSMutableArray*ids=[NSMutableArray array];
        for(NSDictionary*it in j[@"contents"][@"items"]){ NSString*tid=[it isKindOfClass:[NSDictionary class]]?trackIdFromUri(it[@"uri"]):nil; if(tid)[ids addObject:tid]; }
        NSUInteger total=[j[@"length"] unsignedIntegerValue];
        NSDictionary*pg=trackPage(ids,0,ids.count,ids.count,@"");
        id next=(off+lim<total)?[NSString stringWithFormat:@"playlists/%@?offset=%lu",pid,(unsigned long)(off+lim)]:[NSNull null];
        return @{@"tracks":@{@"items":pg[@"items"],@"next":next,@"total":@(total)}};
    }
    if([path hasPrefix:@"me/tracks"]){
        NSArray*ids=spLikedIds(st); if(!ids) return nil;
        return trackPage(ids,off,lim,ids.count,@"me/tracks?");
    }
    if([path hasPrefix:@"me/player/recently-played"]){
        NSDictionary*j=spJSON([NSString stringWithFormat:@"/recently-played/v3/user/%@/recently-played?format=json&limit=%lu&filter=default",user,(unsigned long)lim],st);
        if(!j) return nil;
        NSMutableArray*ids=[NSMutableArray array];
        for(NSDictionary*c in j[@"playContexts"]){ NSString*tid=[c isKindOfClass:[NSDictionary class]]?trackIdFromUri(c[@"lastPlayedTrackUri"]):nil; if(tid&&![ids containsObject:tid])[ids addObject:tid]; }
        return trackPage(ids,0,ids.count,ids.count,@"");
    }
    if([path hasPrefix:@"me/top/"]){ *st=404; return nil; }   // kein interner Ersatz bekannt -> Bereich bleibt ausgeblendet
    *handled=NO; return nil;
}

// Web-API mit Methode (GET/PUT/DELETE/POST) über den User-Daten-Token.
+ (void)apiUser:(NSString *)method path:(NSString *)path body:(NSData *)body completion:(void(^)(NSDictionary *json, NSInteger status))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        if([method isEqualToString:@"GET"]){   // erst interne Server; nur unbekannte Pfade gehen an die Web-API
            int ist=0; BOOL handled=NO; NSDictionary*ij=spInternalGet(path,&ist,&handled);
            if(handled){
                if(ist==401 && gRefreshDead) dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil]; });
                dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(ij, ij?200:(ist?ist:503)); });
                return;
            }
        }
        if(!gToken.length) loadUserToken();
        __block int st=0;
        NSData*(^go)(void)=^NSData*{
            NSMutableArray*h=[NSMutableArray array]; if(gToken.length)[h addObject:[@"Authorization: Bearer " stringByAppendingString:gToken]];
            if(body.length)[h addObject:@"Content-Type: application/json"];
            int s2=0; NSData*r=httpsReq(method,@"api.spotify.com",[@"/v1/" stringByAppendingString:path],h,body,&s2); st=s2; return r; };
        NSData*d=go();
        if(st==401 && refreshUserToken()) d=go();   // Token abgelaufen -> still erneuern
        // Refresh klappt nicht mehr -> App startet selbst den Code-Login
        if(st==401 && gRefreshDead) dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAuthExpired" object:nil]; });
        slog(@"apiUser %@ %@ -> HTTP %d (%lu B)", method, path, st, (unsigned long)d.length);
        NSDictionary*j=(d.length)?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
        if(![j isKindOfClass:[NSDictionary class]]) j=nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if(done)done(j, st); });
    });
}
// Stale-while-revalidate: erst Disk-Cache, dann Netz. Nur GET.
static NSString* apiCachePath(NSString*path){ return [NSString stringWithFormat:@"%@/api_%lu.json", diskDir(), (unsigned long)path.hash]; }
+ (void)apiUserCached:(NSString *)path completion:(void(^)(NSDictionary *json, NSInteger status, BOOL fresh))done {
    NSData*cd=[NSData dataWithContentsOfFile:apiCachePath(path)];
    id cj=cd.length?[NSJSONSerialization JSONObjectWithData:cd options:0 error:NULL]:nil;
    NSDictionary*cached=[cj isKindOfClass:[NSDictionary class]]?cj:nil;
    if(cached && done) done(cached, 200, NO);
    [self apiUser:@"GET" path:path body:nil completion:^(NSDictionary*j, NSInteger st){
        BOOL ok=(st>=200&&st<300)&&j;
        if(ok){
            if(cached && [j isEqual:cached]) return;   // unverändert -> UI bleibt wie sie ist
            NSData*out=[NSJSONSerialization dataWithJSONObject:j options:0 error:NULL];
            if(out.length) [out writeToFile:apiCachePath(path) atomically:YES];
            if(done) done(j, st, YES);
        } else if(!cached){ if(done) done(nil, st, YES); }   // nur ohne Cache Fehler melden
        else slog(@"apiUserCached %@ -> HTTP %d, zeige letzte Daten", path, (int)st);
    }];
}

+ (BOOL)hasUserToken {
    NSString*ut=[NSString stringWithContentsOfFile:@"/var/mobile/.spotify-usertoken" encoding:NSUTF8StringEncoding error:NULL];
    return ut.length>0;
}

// Folgt der "next"-URL quer durch alle Seiten (me/tracks: j.items/j.next ; playlists/{id}: j.tracks.items/j.tracks.next).
+ (void)apiUserAllItems:(NSString *)path completion:(void(^)(NSArray *items, NSInteger status))done {
    NSMutableArray*acc=[NSMutableArray array];
    __block void (^step)(NSString*) = nil;
    step = [^(NSString *p){
        [self apiUser:@"GET" path:p body:nil completion:^(NSDictionary*j, NSInteger st){
            NSDictionary*page=[j isKindOfClass:[NSDictionary class]]?j:nil;
            if(page && ![page[@"items"] isKindOfClass:[NSArray class]] && [page[@"tracks"] isKindOfClass:[NSDictionary class]]) page=page[@"tracks"];  // Playlist: items liegen unter .tracks
            id items=page[@"items"];
            if([items isKindOfClass:[NSArray class]]) [acc addObjectsFromArray:items];
            id next=page[@"next"];
            if([next isKindOfClass:[NSString class]] && [next length]){
                NSString*rel=next; NSRange r=[next rangeOfString:@"/v1/"];
                if(r.location!=NSNotFound) rel=[next substringFromIndex:r.location+4];   // volle URL -> relativer Pfad
                step(rel);
            } else { if(done)done(acc.count?acc:((st>=200&&st<300)?acc:nil), st); step=nil; }   // fertig -> Zyklus auflösen
        }];
    } copy];
    step(path);
}

// ---- Login mit Code über ein anderes Gerät (OAuth Device Flow, wie bei Smart-TVs) ----
#define DEVICE_CLIENT @"65b708073fc0480ea92a077233ca87bd"
#define DEVICE_SCOPE  @"streaming%20user-read-private%20user-read-email%20user-library-read%20user-library-modify%20playlist-read-private%20playlist-read-collaborative%20playlist-modify-private%20playlist-modify-public%20user-read-recently-played%20user-top-read"

static NSDictionary* formPost(NSString*path,NSString*body,int*st){
    NSArray*hdr=@[@"Content-Type: application/x-www-form-urlencoded",@"Accept: application/json"];
    NSData*d=httpsReq(@"POST",@"accounts.spotify.com",path,hdr,[body dataUsingEncoding:NSUTF8StringEncoding],st);
    id j=d.length?[NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    return [j isKindOfClass:[NSDictionary class]]?j:nil;
}

+ (void)deviceLoginStart:(void(^)(NSDictionary*info,NSString*err))done {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        int st=0; NSDictionary*j=formPost(@"/oauth2/device/authorize",
            [NSString stringWithFormat:@"client_id=%@&scope=%@",DEVICE_CLIENT,DEVICE_SCOPE],&st);
        slog(@"device/authorize HTTP %d -> %@", st, j[@"user_code"]?@"code ok":j[@"error"]);
        NSString*err=nil;
        if(![j[@"device_code"] length]||![j[@"user_code"] length]) err=st?[NSString stringWithFormat:@"Spotify: %@",j[@"error_description"]?:@(st)]:@"keine Verbindung zu Spotify";
        dispatch_async(dispatch_get_main_queue(), ^{ done(err?nil:j, err); });
    });
}

+ (void)deviceLoginPoll:(NSDictionary*)info cancelled:(BOOL(^)(void))cancelled completion:(void(^)(NSString*token,NSString*err))done {
    NSString*code=info[@"device_code"];
    __block double interval=MAX([info[@"interval"] doubleValue],2.0);
    double deadline=[NSDate timeIntervalSinceReferenceDate]+MAX([info[@"expires_in"] doubleValue],60.0);
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSString*token=nil,*err=nil;
        while(!token && !err){
            [NSThread sleepForTimeInterval:interval];
            if(cancelled && cancelled()){ err=@"abgebrochen"; break; }
            if([NSDate timeIntervalSinceReferenceDate]>deadline){ err=@"Code abgelaufen – bitte neu starten"; break; }
            int st=0; NSDictionary*j=formPost(@"/api/token",
                [NSString stringWithFormat:@"grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Adevice_code&device_code=%@&client_id=%@",code,DEVICE_CLIENT],&st);
            NSString*at=j[@"access_token"], *e=j[@"error"];
            if(at.length){
                token=at; gToken=at;
                [at writeToFile:@"/var/mobile/.spotify-usertoken" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                NSString*rt=j[@"refresh_token"];
                if(rt.length)[rt writeToFile:@"/var/mobile/.spotify-userrefresh" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                slog(@"device login: token ok (refresh %@)", rt.length?@"ja":@"nein");
            }
            else if([e isEqualToString:@"authorization_pending"]) continue;
            else if([e isEqualToString:@"slow_down"]) interval+=5;
            else if([e isEqualToString:@"access_denied"]) err=@"Anmeldung am Handy abgelehnt";
            else if([e isEqualToString:@"expired_token"]) err=@"Code abgelaufen – bitte neu starten";
            else if(st!=0 && e.length) err=[NSString stringWithFormat:@"Spotify: %@",j[@"error_description"]?:e];
            // st==0: Netzproblem -> einfach weiter versuchen
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(token, err); });
    });
}
// ---- Netz-Erkennung (SystemConfiguration, "gibt es eine Route ins Internet?") ----
static SCNetworkReachabilityRef gReach;
static BOOL reachFlags(SCNetworkReachabilityFlags f){
    if(!(f&kSCNetworkReachabilityFlagsReachable)) return NO;
    if((f&kSCNetworkReachabilityFlagsConnectionRequired) && !(f&kSCNetworkReachabilityFlagsConnectionOnTraffic)) return NO;
    return YES;
}
static SCNetworkReachabilityRef reachRef(void){
    if(!gReach){ struct sockaddr_in a; memset(&a,0,sizeof a); a.sin_len=sizeof a; a.sin_family=AF_INET;
        gReach=SCNetworkReachabilityCreateWithAddress(NULL,(const struct sockaddr*)&a); }
    return gReach;
}
+ (BOOL)networkReachable {
    SCNetworkReachabilityFlags f=0;
    return SCNetworkReachabilityGetFlags(reachRef(),&f) && reachFlags(f);
}
static BOOL gWasReachable=YES;
static void reachChanged(SCNetworkReachabilityRef r,SCNetworkReachabilityFlags f,void*info){
    BOOL ok=reachFlags(f); if(ok==gWasReachable) return;
    gWasReachable=ok; slog(@"Netz %@", ok?@"wieder da":@"weg");
    if(ok && [MMSpotify hasStoredCreds]) dispatch_async(spotQ(), ^{ if(gSock<0) reconnectStored(); });   // Session still neu aufbauen
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MMNetworkChanged" object:nil userInfo:@{@"reachable":@(ok)}];
}
+ (void)startNetworkWatch {
    static dispatch_once_t o; dispatch_once(&o, ^{
        gWasReachable=[self networkReachable];
        SCNetworkReachabilitySetCallback(reachRef(),reachChanged,NULL);
        SCNetworkReachabilityScheduleWithRunLoop(reachRef(),CFRunLoopGetMain(),kCFRunLoopCommonModes);
    });
}
// Abmelden (am Ende, damit alle Zustände oben deklariert sind)
+ (void)logoutCompletion:(void(^)(void))done {
    [MMAudio stop];
    @synchronized([MMSpotify class]){ [gDlQueue removeAllObjects]; gDlRunning=NO; gDlDone=0; gDlTotal=0; [gDlSeen removeAllObjects]; }
    dispatch_async(spotQ(), ^{   // Socket gehört der spotQ
        if(gSock>=0){ close(gSock); gSock=-1; }
        gToken=nil; gClientToken=nil; gSpclient=nil; gLiked=nil; gLikedAt=0; gRefreshDead=NO; gRefreshedAt=0; gLoginRejected=NO;
        @synchronized([MMSpotify class]){ [gCache removeAllObjects]; [gCacheOrder removeAllObjects]; [gInflight removeAllObjects]; }
        NSFileManager*fm=[NSFileManager defaultManager];
        for(NSString*f in @[@".spotify-creds",@".spotify-user",@".spotify-usertoken",@".spotify-userrefresh",@".spotify-token",
                            @".spotify-datatoken",@".spotify-datarefresh",@".spotify-log"])
            [fm removeItemAtPath:[@"/var/mobile/" stringByAppendingString:f] error:NULL];
        [fm removeItemAtPath:@"/var/mobile/.spotcache" error:NULL];   // Downloads, Playlisten, Cover, API-Antworten
        gLog=nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString*bid=[[NSBundle mainBundle] bundleIdentifier];
            if(bid) [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bid];   // Warteschlange, letzter Song …
            [[NSUserDefaults standardUserDefaults] synchronize];
            if(done) done();
        });
    });
}

@end
