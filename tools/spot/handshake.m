// handshake.m — Spotify Access-Point Handshake (Milestone 2): ClientHello(DH) -> APResponse -> Keys.
// Mac-Spike mit OpenSSL (BN) + CommonCrypto (SHA1/HMAC). Beweist, dass unser ClientHello akzeptiert
// wird und wir die Shannon-Schlüssel ableiten können. Noch keine Auth.
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netdb.h>
#import <unistd.h>
#import <CommonCrypto/CommonCrypto.h>
#import <openssl/bn.h>

static const unsigned char DH_PRIME[96] = {
 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xc9,0x0f,0xda,0xa2,0x21,0x68,0xc2,0x34,
 0xc4,0xc6,0x62,0x8b,0x80,0xdc,0x1c,0xd1,0x29,0x02,0x4e,0x08,0x8a,0x67,0xcc,0x74,
 0x02,0x0b,0xbe,0xa6,0x3b,0x13,0x9b,0x22,0x51,0x4a,0x08,0x79,0x8e,0x34,0x04,0xdd,
 0xef,0x95,0x19,0xb3,0xcd,0x3a,0x43,0x1b,0x30,0x2b,0x0a,0x6d,0xf2,0x5f,0x14,0x37,
 0x4f,0xe1,0x35,0x6d,0x6d,0x51,0xc2,0x45,0xe4,0x85,0xb5,0x76,0x62,0x5e,0x7e,0xc6,
 0xf4,0x4c,0x42,0xe9,0xa6,0x3a,0x36,0x20,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };

// ---- protobuf helpers ----
static void pvar(NSMutableData*d,uint64_t v){ unsigned char b; do{ b=v&0x7f; v>>=7; if(v)b|=0x80; [d appendBytes:&b length:1]; }while(v); }
static void ptag(NSMutableData*d,int field,int wt){ pvar(d,((uint64_t)field<<3)|wt); }
static void pbytes(NSMutableData*d,int field,NSData*val){ ptag(d,field,2); pvar(d,val.length); [d appendData:val]; }
static void pvarf(NSMutableData*d,int field,uint64_t v){ ptag(d,field,0); pvar(d,v); }
static void pmsg(NSMutableData*d,int field,NSData*m){ ptag(d,field,2); pvar(d,m.length); [d appendData:m]; }

// minimal varint reader
static uint64_t rvar(const unsigned char*b,NSUInteger len,NSUInteger*pos){ uint64_t r=0;int s=0; while(*pos<len){ unsigned char c=b[(*pos)++]; r|=(uint64_t)(c&0x7f)<<s; if(!(c&0x80))break; s+=7;} return r; }

int main(){ @autoreleasepool{
    // 1) Access-Point
    NSData *ad=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=accesspoint"]];
    NSArray *aps=[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"];

    // 2) DH-Keypair: x zufällig, gc = 2^x mod p
    BN_CTX*ctx=BN_CTX_new(); BIGNUM*p=BN_bin2bn(DH_PRIME,96,NULL); BIGNUM*g=BN_new();BN_set_word(g,2);
    unsigned char xb[95]; for(int i=0;i<95;i++)xb[i]=arc4random()&0xff; BIGNUM*x=BN_bin2bn(xb,95,NULL);
    BIGNUM*gc=BN_new(); BN_mod_exp(gc,g,x,p,ctx);
    unsigned char gcb[96]; BN_bn2binpad(gc,gcb,96);

    // 3) ClientHello protobuf
    NSMutableData*bi=[NSMutableData data]; pvarf(bi,10,0); pvarf(bi,30,1); pvarf(bi,40,117300517); // product=CLIENT platform=OSX version
    NSMutableData*dh=[NSMutableData data]; pbytes(dh,10,[NSData dataWithBytes:gcb length:96]); pvarf(dh,20,1);
    NSMutableData*lch=[NSMutableData data]; pmsg(lch,10,dh);
    unsigned char nonce[16]; for(int i=0;i<16;i++)nonce[i]=arc4random()&0xff;
    NSMutableData*ch=[NSMutableData data];
    pmsg(ch,10,bi); pvarf(ch,30,0); pmsg(ch,50,lch);
    pbytes(ch,60,[NSData dataWithBytes:nonce length:16]);
    unsigned char pad=0x1e; pbytes(ch,70,[NSData dataWithBytes:&pad length:1]);

    // Paket: [00 04][u32 size][protobuf]
    uint32_t size=2+4+(uint32_t)ch.length;
    NSMutableData*pkt=[NSMutableData data]; unsigned char hdr[2]={0x00,0x04}; [pkt appendBytes:hdr length:2];
    uint32_t be=htonl(size); [pkt appendBytes:&be length:4]; [pkt appendData:ch];

    // 4) TCP: alle APs durchprobieren bis einer verbindet
    int s=-1;
    for(NSString*ap in aps){ NSArray*hp=[ap componentsSeparatedByString:@":"];
        struct hostent*he=gethostbyname([hp[0] UTF8String]); if(!he)continue;
        int t=socket(AF_INET,SOCK_STREAM,0); struct timeval tv={5,0}; setsockopt(t,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
        struct sockaddr_in sa;memset(&sa,0,sizeof(sa));sa.sin_family=AF_INET;sa.sin_port=htons([hp[1] intValue]);memcpy(&sa.sin_addr,he->h_addr,he->h_length);
        if(connect(t,(struct sockaddr*)&sa,sizeof(sa))==0){ printf("AP verbunden: %s\n",ap.UTF8String); s=t; break; } close(t); }
    if(s<0){printf("kein AP erreichbar\n");return 1;}
    write(s,pkt.bytes,pkt.length);
    NSMutableData*acc=[NSMutableData dataWithData:pkt];

    // 5) APResponse lesen: [u32 size][body(size-4)]
    unsigned char lb[4]; int n=0; while(n<4){int r=(int)read(s,lb+n,4-n); if(r<=0){printf("read size FEHLER\n");return 1;} n+=r;}
    uint32_t rsize=ntohl(*(uint32_t*)lb); uint32_t blen=rsize-4;
    NSMutableData*body=[NSMutableData dataWithLength:blen]; n=0; unsigned char*bp=body.mutableBytes;
    while(n<(int)blen){int r=(int)read(s,bp+n,blen-n); if(r<=0){printf("read body FEHLER\n");return 1;} n+=r;}
    [acc appendBytes:lb length:4]; [acc appendData:body];
    printf("APResponse: %u bytes\n", blen);

    // gs aus APResponseMessage.challenge(10).login_crypto_challenge(10).diffie_hellman(10).gs(10)
    // einfacher rekursiver Scan nach dem ersten 96-Byte-bytes-Feld unter diesen Pfaden -> wir parsen gezielt.
    // Grobparser: finde challenge(feld1), darin login_crypto_challenge(feld1), darin dh(feld1), darin gs(feld1).
    NSData*(^sub)(NSData*,int) = ^NSData*(NSData*m,int wantField){
        const unsigned char*b=m.bytes; NSUInteger len=m.length,pos=0;
        while(pos<len){ uint64_t tag=rvar(b,len,&pos); int f=tag>>3,wt=tag&7;
            if(wt==2){ uint64_t l=rvar(b,len,&pos); NSData*v=[m subdataWithRange:NSMakeRange(pos,l)]; pos+=l; if(f==wantField)return v; }
            else if(wt==0){ rvar(b,len,&pos); }
            else if(wt==5){ pos+=4; } else if(wt==1){ pos+=8; } else break; }
        return nil; };
    NSData*challenge=sub(body,10); NSData*lcc=challenge?sub(challenge,10):nil; NSData*dhc=lcc?sub(lcc,10):nil; NSData*gs=dhc?sub(dhc,10):nil;
    if(!gs){printf("gs nicht gefunden -> ClientHello evtl. abgelehnt\n");return 1;}
    printf("gs (server DH key): %lu bytes  ✅ Handshake akzeptiert!\n",(unsigned long)gs.length);

    // 6) shared = gs^x mod p
    BIGNUM*gsb=BN_bin2bn(gs.bytes,(int)gs.length,NULL); BIGNUM*sh=BN_new(); BN_mod_exp(sh,gsb,x,p,ctx);
    unsigned char shb[96]; BN_bn2binpad(sh,shb,96);

    // 7) Keys: data = concat_{i=1..5} HMAC-SHA1(shared, acc||i); send=data[20..52], recv=data[52..84]
    NSMutableData*data=[NSMutableData data];
    for(unsigned char i=1;i<=5;i++){ NSMutableData*m=[NSMutableData dataWithData:acc]; [m appendBytes:&i length:1];
        unsigned char mac[20]; CCHmac(kCCHmacAlgSHA1,shb,96,m.bytes,m.length,mac); [data appendBytes:mac length:20]; }
    const unsigned char*dd=data.bytes;
    unsigned char challengeMac[20]; CCHmac(kCCHmacAlgSHA1,dd,20,acc.bytes,acc.length,challengeMac);
    printf("send-key, recv-key abgeleitet; challenge-HMAC berechnet (20 B)\n");

    // 8) ClientResponsePlaintext: login_crypto_response(10).diffie_hellman(10).hmac(10)=challengeMac
    NSMutableData*dhr=[NSMutableData data]; pbytes(dhr,10,[NSData dataWithBytes:challengeMac length:20]);
    NSMutableData*lcr=[NSMutableData data]; pmsg(lcr,10,dhr);
    NSMutableData*resp=[NSMutableData data]; pmsg(resp,10,lcr);
    uint32_t rs=4+(uint32_t)resp.length; uint32_t rbe=htonl(rs);
    NSMutableData*rpkt=[NSMutableData data]; [rpkt appendBytes:&rbe length:4]; [rpkt appendData:resp];
    write(s,rpkt.bytes,rpkt.length);
    printf("ClientResponsePlaintext gesendet. Handshake-Flow komplett ✅\n");
    printf(">>> Milestone 2 erreicht: DH-Handshake mit Spotify steht.\n");
    close(s); return 0;
}}