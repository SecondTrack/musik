// spotlogin.m — Milestone 3 komplett: Handshake -> Shannon -> Login mit OAuth-Token -> APWelcome.
// Liest den Token aus ~/.spotify-token (von spotauth). Beweist, dass wir eingeloggt sind.
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netdb.h>
#import <unistd.h>
#import <CommonCrypto/CommonCrypto.h>
#import <openssl/bn.h>
#import "shannon.h"

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
static NSData* sub(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)return v;}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return nil;}

static int rd_all(int s,unsigned char*b,int n){int t=0;while(t<n){int r=(int)read(s,b+t,n-t);if(r<=0)return -1;t+=r;}return 0;}

int main(){ @autoreleasepool{
    NSString*tokPath=[NSHomeDirectory() stringByAppendingPathComponent:@".spotify-token"];
    NSString*token=[[NSString stringWithContentsOfFile:tokPath encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!token.length){printf("Kein Token in ~/.spotify-token — erst: /tmp/spotauth\n");return 1;}
    printf("Token geladen (%lu Zeichen)\n",(unsigned long)token.length);

    NSData*ad=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=accesspoint"]];
    NSArray*aps=[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"];

    BN_CTX*ctx=BN_CTX_new();BIGNUM*p=BN_bin2bn(DH_PRIME,96,NULL);BIGNUM*g=BN_new();BN_set_word(g,2);
    unsigned char xb[95];for(int i=0;i<95;i++)xb[i]=arc4random()&0xff;BIGNUM*x=BN_bin2bn(xb,95,NULL);
    BIGNUM*gc=BN_new();BN_mod_exp(gc,g,x,p,ctx);unsigned char gcb[96];BN_bn2binpad(gc,gcb,96);

    NSMutableData*bi=[NSMutableData data];pvarf(bi,10,0);pvarf(bi,30,1);pvarf(bi,40,117300517);
    NSMutableData*dh=[NSMutableData data];pbytes(dh,10,[NSData dataWithBytes:gcb length:96]);pvarf(dh,20,1);
    NSMutableData*lch=[NSMutableData data];pmsg(lch,10,dh);
    unsigned char nonce[16];for(int i=0;i<16;i++)nonce[i]=arc4random()&0xff;
    NSMutableData*ch=[NSMutableData data];pmsg(ch,10,bi);pvarf(ch,30,0);pmsg(ch,50,lch);
    pbytes(ch,60,[NSData dataWithBytes:nonce length:16]);unsigned char pad=0x1e;pbytes(ch,70,[NSData dataWithBytes:&pad length:1]);
    uint32_t size=2+4+(uint32_t)ch.length;NSMutableData*pkt=[NSMutableData data];unsigned char hdr[2]={0,4};[pkt appendBytes:hdr length:2];
    uint32_t be=htonl(size);[pkt appendBytes:&be length:4];[pkt appendData:ch];

    int s=-1;for(NSString*ap in aps){NSArray*hp=[ap componentsSeparatedByString:@":"];struct hostent*he=gethostbyname([hp[0] UTF8String]);if(!he)continue;
     int t=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in sa;memset(&sa,0,sizeof(sa));sa.sin_family=AF_INET;sa.sin_port=htons([hp[1] intValue]);memcpy(&sa.sin_addr,he->h_addr,he->h_length);
     if(connect(t,(struct sockaddr*)&sa,sizeof(sa))==0){printf("AP: %s\n",ap.UTF8String);s=t;break;}close(t);}
    if(s<0){printf("kein AP\n");return 1;}
    write(s,pkt.bytes,pkt.length);NSMutableData*acc=[NSMutableData dataWithData:pkt];

    unsigned char lb[4];if(rd_all(s,lb,4)){printf("read size fail\n");return 1;}uint32_t blen=ntohl(*(uint32_t*)lb)-4;
    NSMutableData*body=[NSMutableData dataWithLength:blen];if(rd_all(s,body.mutableBytes,blen)){printf("read body fail\n");return 1;}
    [acc appendBytes:lb length:4];[acc appendData:body];
    NSData*gs=sub(sub(sub(sub(body,10),10),10),10);
    if(!gs){printf("gs fehlt\n");return 1;}
    printf("Handshake ok (gs %lu B)\n",(unsigned long)gs.length);

    BIGNUM*gsb=BN_bin2bn(gs.bytes,(int)gs.length,NULL);BIGNUM*sh=BN_new();BN_mod_exp(sh,gsb,x,p,ctx);unsigned char shb[96];BN_bn2binpad(sh,shb,96);
    NSMutableData*data=[NSMutableData data];
    for(unsigned char i=1;i<=5;i++){NSMutableData*m=[NSMutableData dataWithData:acc];[m appendBytes:&i length:1];unsigned char mac[20];CCHmac(kCCHmacAlgSHA1,shb,96,m.bytes,m.length,mac);[data appendBytes:mac length:20];}
    const unsigned char*dd=data.bytes;unsigned char cmac[20];CCHmac(kCCHmacAlgSHA1,dd,20,acc.bytes,acc.length,cmac);

    NSMutableData*dhr=[NSMutableData data];pbytes(dhr,10,[NSData dataWithBytes:cmac length:20]);
    NSMutableData*lcr=[NSMutableData data];pmsg(lcr,10,dhr);
    NSMutableData*resp=[NSMutableData data];
    pmsg(resp,10,lcr);                 // login_crypto_response
    pmsg(resp,20,[NSData data]);       // pow_response (leer, aber required!)
    pmsg(resp,30,[NSData data]);       // crypto_response (leer, aber required!)
    uint32_t rs=htonl(4+(uint32_t)resp.length);NSMutableData*rpkt=[NSMutableData data];[rpkt appendBytes:&rs length:4];[rpkt appendData:resp];
    write(s,rpkt.bytes,rpkt.length);
    printf("Plaintext-Response gesendet, Shannon-Keys aktiv\n");

    // Shannon: send=data[20..52], recv=data[52..84]
    shn_ctx snd,rcv;shn_key(&snd,dd+20,32);shn_key(&rcv,dd+52,32);

    // ClientResponseEncrypted
    NSData*tokD=[token dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData*cred=[NSMutableData data];pvarf(cred,20,3);pbytes(cred,30,tokD); // typ=SPOTIFY_TOKEN, auth_data=token
    NSMutableData*sys=[NSMutableData data];pvarf(sys,10,0);pvarf(sys,60,2);         // cpu_family=UNKNOWN, os=OSX
    NSMutableData*cre=[NSMutableData data];pmsg(cre,10,cred);pmsg(cre,50,sys);

    // Paket: [0xab][u16 len][payload]  -> Shannon encrypt (nonce 0) + 4B MAC
    NSMutableData*lp=[NSMutableData data];unsigned char c=0xab;[lp appendBytes:&c length:1];
    uint16_t pl=htons((uint16_t)cre.length);[lp appendBytes:&pl length:2];[lp appendData:cre];
    shn_nonce_u32(&snd,0);shn_encrypt(&snd,lp.mutableBytes,(int)lp.length);
    unsigned char smac[4];shn_finish(&snd,smac,4);
    write(s,lp.bytes,lp.length);write(s,smac,4);
    printf("Login gesendet (cmd 0xab, %lu B) — warte auf Antwort…\n",(unsigned long)cre.length);

    // Antwort lesen: recv nonce 0, header(3) + payload + 4 MAC
    shn_nonce_u32(&rcv,0);
    unsigned char h[3];int hr=rd_all(s,h,3);
    if(hr){printf("keine Antwort (Server hat getrennt -> ClientResponsePlaintext evtl. abgelehnt)\n");return 1;}
    printf("Header roh (verschlüsselt): %02x %02x %02x\n",h[0],h[1],h[2]);
    shn_decrypt(&rcv,h,3);
    int rcmd=h[0];int rlen=(h[1]<<8)|h[2];
    printf("Header entschlüsselt: cmd=0x%02x len=%d\n",rcmd,rlen);
    if(rlen>4096){printf("len unplausibel -> Shannon recv-Key/Nonce falsch\n");return 1;}
    unsigned char*pay=malloc(rlen>0?rlen:1);
    if(rlen){ int got=0; while(got<rlen){int r=(int)read(s,pay+got,rlen-got); if(r<=0)break; got+=r;}
        printf("payload gelesen: %d/%d\n",got,rlen); if(got<rlen){printf("Verbindung zu\n");} shn_decrypt(&rcv,pay,got>rlen?rlen:got); }
    unsigned char rmac[4];rd_all(s,rmac,4);
    printf("Antwort: cmd=0x%02x len=%d\n",rcmd,rlen);
    if(rcmd==0xac){printf("\n🎉 APWelcome — EINGELOGGT! Milestone 3 geschafft.\n");}
    else if(rcmd==0xad){printf("\n❌ AuthFailure (Token/Scope?). Payload: %.*s\n",rlen>80?80:rlen,pay);}
    else printf("\nUnerwartetes cmd 0x%02x (evtl. Shannon-MAC/Key falsch)\n",rcmd);
    close(s);return 0;
}}
