// spotplay.m — Milestone 4+5: Login -> Mercury-Metadaten -> AudioKey -> Storage-Resolve -> CDN
// laden -> AES-CTR entschlüsseln -> OGG prüfen. Beweist, dass wir echtes Spotify-Audio bekommen.
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
static const unsigned char AUDIO_IV[16]={0x72,0xe0,0x67,0xfb,0xdd,0xcb,0xcf,0x77,0xeb,0xe8,0xbc,0x64,0x3f,0x63,0x0d,0x93};

static void pvar(NSMutableData*d,uint64_t v){unsigned char b;do{b=v&0x7f;v>>=7;if(v)b|=0x80;[d appendBytes:&b length:1];}while(v);}
static void ptag(NSMutableData*d,int f,int wt){pvar(d,((uint64_t)f<<3)|wt);}
static void pbytes(NSMutableData*d,int f,NSData*v){ptag(d,f,2);pvar(d,v.length);[d appendData:v];}
static void pstr(NSMutableData*d,int f,NSString*s){pbytes(d,f,[s dataUsingEncoding:NSUTF8StringEncoding]);}
static void pvarf(NSMutableData*d,int f,uint64_t v){ptag(d,f,0);pvar(d,v);}
static void pmsg(NSMutableData*d,int f,NSData*m){ptag(d,f,2);pvar(d,m.length);[d appendData:m];}
static uint64_t rvar(const unsigned char*b,NSUInteger len,NSUInteger*p){uint64_t r=0;int s=0;while(*p<len){unsigned char c=b[(*p)++];r|=(uint64_t)(c&0x7f)<<s;if(!(c&0x80))break;s+=7;}return r;}
static NSData* psub(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)return v;}
  else if(wt==0){uint64_t v=rvar(b,len,&pos);(void)v;}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return nil;}
// alle Vorkommen eines length-delimited Feldes
static NSArray* psubs(NSData*m,int want){NSMutableArray*out=[NSMutableArray array];const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==2){uint64_t l=rvar(b,len,&pos);NSData*v=[m subdataWithRange:NSMakeRange(pos,l)];pos+=l;if(f==want)[out addObject:v];}
  else if(wt==0){rvar(b,len,&pos);}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return out;}
static int64_t pvarval(NSData*m,int want){const unsigned char*b=m.bytes;NSUInteger len=m.length,pos=0;
 while(pos<len){uint64_t tag=rvar(b,len,&pos);int f=tag>>3,wt=tag&7;
  if(wt==0){uint64_t v=rvar(b,len,&pos);if(f==want)return v;}
  else if(wt==2){uint64_t l=rvar(b,len,&pos);pos+=l;}else if(wt==5)pos+=4;else if(wt==1)pos+=8;else break;}return -1;}

static int rd_all(int s,unsigned char*b,int n){int t=0;while(t<n){int r=(int)read(s,b+t,n-t);if(r<=0)return -1;t+=r;}return 0;}
static NSString* hexstr(const unsigned char*b,int n){NSMutableString*s=[NSMutableString string];for(int i=0;i<n;i++)[s appendFormat:@"%02x",b[i]];return s;}

// ---- Client-Token (HTTPS POST, Anti-Bot-Schicht) ----
static NSString* getClientToken(void){
    NSMutableData*macos=[NSMutableData data];pstr(macos,1,@"13.4.0");pstr(macos,2,@"MacBookPro18,3");pstr(macos,3,@"arm64");
    NSMutableData*psd=[NSMutableData data];pmsg(psd,3,macos);
    NSMutableData*conn=[NSMutableData data];pmsg(conn,1,psd);pstr(conn,2,@"0123456789abcdef0123456789abcdef01234567");
    NSMutableData*cdr=[NSMutableData data];pstr(cdr,1,@"1.2.52.442.g01c3f6ee");pstr(cdr,2,@"65b708073fc0480ea92a077233ca87bd");pmsg(cdr,3,conn);
    NSMutableData*req=[NSMutableData data];pvarf(req,1,1);pmsg(req,2,cdr);
    NSMutableURLRequest*r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://clienttoken.spotify.com/v1/clienttoken"]];
    r.HTTPMethod=@"POST";[r setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];[r setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];r.HTTPBody=req;
    NSData*resp=[NSURLConnection sendSynchronousRequest:r returningResponse:NULL error:NULL];
    NSData*granted=psub(resp,2); NSData*tok=granted?psub(granted,1):nil;
    return tok?[[NSString alloc] initWithData:tok encoding:NSUTF8StringEncoding]:nil;
}
// ---- spclient HTTPS GET mit Bearer + client-token ----
static NSData* spclientGet(NSString*spc,NSString*path,NSString*bearer,NSString*ctoken){
    NSString*url=[NSString stringWithFormat:@"https://%@%@",spc,path];
    NSMutableURLRequest*r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [r setValue:[@"Bearer " stringByAppendingString:bearer] forHTTPHeaderField:@"Authorization"];
    [r setValue:ctoken forHTTPHeaderField:@"client-token"];
    NSHTTPURLResponse*hr=nil; NSData*d=[NSURLConnection sendSynchronousRequest:r returningResponse:&hr error:NULL];
    if(hr.statusCode!=200){printf("[spclient] %s -> HTTP %ld\n",path.UTF8String,(long)hr.statusCode);return nil;}
    return d;
}

// Shannon-Paket senden/empfangen
static uint32_t gSend=0,gRecv=0; static shn_ctx gSnd,gRcv; static int gSock;
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

// Mercury GET: schickt 0xb2 und sammelt die Antwort-Parts zum passenden seq. Gibt payload-Part[1] zurück.
static uint64_t gMercSeq=1;
static NSData* mercuryGet(NSString*uri){
    uint64_t seq=gMercSeq++;
    NSMutableData*hdr=[NSMutableData data];pstr(hdr,1,uri);pstr(hdr,3,@"GET");
    NSMutableData*pl=[NSMutableData data];
    uint16_t sl=htons(8);[pl appendBytes:&sl length:2];unsigned char sb[8];for(int i=0;i<8;i++)sb[i]=(seq>>(8*(7-i)))&0xff;[pl appendBytes:sb length:8];
    unsigned char flags=1;[pl appendBytes:&flags length:1];uint16_t cnt=htons(1);[pl appendBytes:&cnt length:2];
    uint16_t hl=htons((uint16_t)hdr.length);[pl appendBytes:&hl length:2];[pl appendData:hdr];
    sendpkt(0xb2,pl);
    // Antworten lesen bis Mercury-Response mit unserem seq
    for(int tries=0;tries<200;tries++){
        int cmd;NSData*r=recvpkt(&cmd);if(!r)return nil;
        if(cmd==0x04){ sendpkt(0x49,r); continue; }                 // Ping -> Pong
        if(cmd!=0xb2 && cmd!=0xb5) continue;                         // andere Pakete ignorieren
        const unsigned char*b=r.bytes;NSUInteger pos=0,len=r.length;
        int seqlen=(b[0]<<8)|b[1];pos=2;uint64_t rseq=0;for(int i=0;i<seqlen;i++)rseq=(rseq<<8)|b[pos++];
        pos++; // flags
        int parts=(b[pos]<<8)|b[pos+1];pos+=2;
        NSMutableArray*pp=[NSMutableArray array];
        for(int i=0;i<parts && pos+2<=len;i++){int plen=(b[pos]<<8)|b[pos+1];pos+=2;[pp addObject:[r subdataWithRange:NSMakeRange(pos,plen)]];pos+=plen;}
        if(rseq!=seq) continue;
        printf("[mercury] flags=%d parts=%d: ",b[2+seqlen],(int)pp.count);
        for(NSData*q in pp)printf("%luB ",(unsigned long)q.length);printf("\n");
        if(pp.count>=1){ int64_t st=pvarval(pp[0],4); printf("[mercury] header status=%lld (zigzag->%lld)\n",st,(st>>1)^-(st&1)); }
        if(pp.count>=2) return pp[1];
        if(pp.count>=1) return pp[0];
        return [NSData data];
    }
    return nil;
}

int main(int argc,char**argv){ @autoreleasepool{
    NSString*trackB62 = argc>1?@(argv[1]):@"4cOdK2wGLETKBW3PvgPWqT"; // Default-Track
    NSString*token=[[NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".spotify-token"] encoding:NSUTF8StringEncoding error:NULL] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!token.length){printf("kein Token (erst /tmp/spotauth)\n");return 1;}

    // base62 -> 16-Byte gid
    const char*A="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    BN_CTX*ctx=BN_CTX_new();BIGNUM*gid=BN_new();BN_zero(gid);
    for(NSUInteger i=0;i<trackB62.length;i++){char c=[trackB62 characterAtIndex:i];const char*q=strchr(A,c);if(!q){printf("bad base62\n");return 1;}BN_mul_word(gid,62);BN_add_word(gid,(int)(q-A));}
    unsigned char gidb[16];BN_bn2binpad(gid,gidb,16);
    printf("Track %s -> gid %s\n",trackB62.UTF8String,hexstr(gidb,16).UTF8String);

    // ---- Login (wie spotlogin, bewiesen) ----
    NSData*ad=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=accesspoint"]];
    NSArray*aps=[NSJSONSerialization JSONObjectWithData:ad options:0 error:NULL][@"accesspoint"];
    BIGNUM*p=BN_bin2bn(DH_PRIME,96,NULL);BIGNUM*g=BN_new();BN_set_word(g,2);
    unsigned char xb[95];for(int i=0;i<95;i++)xb[i]=arc4random()&0xff;BIGNUM*x=BN_bin2bn(xb,95,NULL);
    BIGNUM*gc=BN_new();BN_mod_exp(gc,g,x,p,ctx);unsigned char gcb[96];BN_bn2binpad(gc,gcb,96);
    NSMutableData*bi=[NSMutableData data];pvarf(bi,10,0);pvarf(bi,30,1);pvarf(bi,40,117300517);
    NSMutableData*dh=[NSMutableData data];pbytes(dh,10,[NSData dataWithBytes:gcb length:96]);pvarf(dh,20,1);
    NSMutableData*lch=[NSMutableData data];pmsg(lch,10,dh);unsigned char nn[16];for(int i=0;i<16;i++)nn[i]=arc4random()&0xff;
    NSMutableData*ch=[NSMutableData data];pmsg(ch,10,bi);pvarf(ch,30,0);pmsg(ch,50,lch);pbytes(ch,60,[NSData dataWithBytes:nn length:16]);unsigned char pad=0x1e;pbytes(ch,70,[NSData dataWithBytes:&pad length:1]);
    uint32_t size=2+4+(uint32_t)ch.length;NSMutableData*pkt=[NSMutableData data];unsigned char hd[2]={0,4};[pkt appendBytes:hd length:2];uint32_t be=htonl(size);[pkt appendBytes:&be length:4];[pkt appendData:ch];
    int s=-1;for(NSString*ap in aps){NSArray*hp=[ap componentsSeparatedByString:@":"];struct hostent*he=gethostbyname([hp[0] UTF8String]);if(!he)continue;int t=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in sa;memset(&sa,0,sizeof(sa));sa.sin_family=AF_INET;sa.sin_port=htons([hp[1] intValue]);memcpy(&sa.sin_addr,he->h_addr,he->h_length);if(connect(t,(struct sockaddr*)&sa,sizeof(sa))==0){s=t;break;}close(t);}
    if(s<0){printf("kein AP\n");return 1;}
    write(s,pkt.bytes,pkt.length);NSMutableData*acc=[NSMutableData dataWithData:pkt];
    unsigned char lb[4];if(rd_all(s,lb,4)){printf("hs fail\n");return 1;}uint32_t blen=ntohl(*(uint32_t*)lb)-4;
    NSMutableData*body=[NSMutableData dataWithLength:blen];if(rd_all(s,body.mutableBytes,blen)){printf("hs body fail\n");return 1;}
    [acc appendBytes:lb length:4];[acc appendData:body];
    NSData*gs=psub(psub(psub(psub(body,10),10),10),10);if(!gs){printf("gs fehlt\n");return 1;}
    BIGNUM*gsb=BN_bin2bn(gs.bytes,(int)gs.length,NULL);BIGNUM*sh=BN_new();BN_mod_exp(sh,gsb,x,p,ctx);unsigned char shb[96];BN_bn2binpad(sh,shb,96);
    NSMutableData*data=[NSMutableData data];for(unsigned char i=1;i<=5;i++){NSMutableData*m=[NSMutableData dataWithData:acc];[m appendBytes:&i length:1];unsigned char mac[20];CCHmac(kCCHmacAlgSHA1,shb,96,m.bytes,m.length,mac);[data appendBytes:mac length:20];}
    const unsigned char*dd=data.bytes;unsigned char cmac[20];CCHmac(kCCHmacAlgSHA1,dd,20,acc.bytes,acc.length,cmac);
    NSMutableData*dhr=[NSMutableData data];pbytes(dhr,10,[NSData dataWithBytes:cmac length:20]);NSMutableData*lcr=[NSMutableData data];pmsg(lcr,10,dhr);
    NSMutableData*resp=[NSMutableData data];pmsg(resp,10,lcr);pmsg(resp,20,[NSData data]);pmsg(resp,30,[NSData data]);
    uint32_t rsz=htonl(4+(uint32_t)resp.length);NSMutableData*rpkt=[NSMutableData data];[rpkt appendBytes:&rsz length:4];[rpkt appendData:resp];write(s,rpkt.bytes,rpkt.length);
    gSock=s;shn_key(&gSnd,dd+20,32);shn_key(&gRcv,dd+52,32);
    // Login senden
    NSData*tokD=[token dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData*cred=[NSMutableData data];pvarf(cred,20,3);pbytes(cred,30,tokD);
    NSMutableData*sys=[NSMutableData data];pvarf(sys,10,0);pvarf(sys,60,2);
    NSMutableData*cre=[NSMutableData data];pmsg(cre,10,cred);pmsg(cre,50,sys);
    sendpkt(0xab,cre);
    int cmd;NSData*welc=nil;for(int i=0;i<10;i++){welc=recvpkt(&cmd);if(!welc){printf("login read fail\n");return 1;}if(cmd==0xac)break;if(cmd==0xad){printf("AuthFailure\n");return 1;}if(cmd==0x04)sendpkt(0x49,welc);}
    if(cmd!=0xac){printf("kein APWelcome\n");return 1;}
    printf("✅ eingeloggt\n");

    // ---- Client-Token + spclient-Host ----
    NSString*ctoken=getClientToken();
    if(!ctoken){printf("kein client-token\n");return 1;}
    printf("✅ client-token (%lu B)\n",(unsigned long)ctoken.length);
    NSData*spd=[NSData dataWithContentsOfURL:[NSURL URLWithString:@"https://apresolve.spotify.com/?type=spclient"]];
    NSString*spc=[NSJSONSerialization JSONObjectWithData:spd options:0 error:NULL][@"spclient"][0];
    printf("spclient: %s\n",spc.UTF8String);

    // ---- TEST: keymaster-Token fuer beliebige client_id ----
    NSString*KM=[[[NSProcessInfo processInfo] environment] objectForKey:@"KM"];
    if(KM.length){
        NSString*u=[NSString stringWithFormat:@"hm://keymaster/token/authenticated?scope=playlist-read-private,user-library-read,user-read-private,streaming&client_id=%@&device_id=0123456789abcdef0123456789abcdef01234567",KM];
        printf(">>> %s\n", u.UTF8String);
        NSData*km=mercuryGet(u);
        printf("keymaster -> %lu B\n", (unsigned long)km.length);
        if(km.length) printf("%s\n", [[NSString alloc] initWithData:km encoding:NSUTF8StringEncoding].UTF8String ?: "(binaer)");
        return 0;
    }

    // ---- TEST: Mercury-Suche ----
    NSString*Q=[[[NSProcessInfo processInfo] environment] objectForKey:@"Q"];
    if(Q.length){
        NSString*qe=[Q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSArray*uris=@[
          [NSString stringWithFormat:@"hm://searchview/km/v4/search/%@?limit=5&catalogue=premium&country=DE&locale=de",qe],
          [NSString stringWithFormat:@"hm://searchview/km/v3/search/%@?limit=5&country=DE",qe],
          [NSString stringWithFormat:@"hm://searchview/km/v2/search/%@",qe] ];
        for(NSString*u in uris){
            printf("\n>>> %s\n", u.UTF8String);
            NSData*sv=mercuryGet(u);
            printf("  -> %lu B\n", (unsigned long)sv.length);
            if(sv.length>2) printf("  %.300s\n", [[NSString alloc] initWithData:[sv subdataWithRange:NSMakeRange(0,sv.length<300?sv.length:300)] encoding:NSUTF8StringEncoding].UTF8String ?: "(binaer)");
        }
        return 0;
    }

    // ---- Track-Metadaten (spclient HTTPS) ----
    NSString*murl=[NSString stringWithFormat:@"hm://metadata/4/track/%@",hexstr(gidb,16)];
    printf("mercury: %s\n", murl.UTF8String);
    NSData*meta=mercuryGet(murl);
    if(!meta){printf("Metadaten (mercury) fehlgeschlagen\n");return 1;}
    [meta writeToFile:@"/tmp/meta.bin" atomically:YES];
    NSString*tname=psub(meta,2)?[[NSString alloc] initWithData:psub(meta,2) encoding:NSUTF8StringEncoding]:@"?";
    printf("Track-Metadaten: %lu B, name=\"%@\"\n",(unsigned long)meta.length,tname);
    // bestes OGG-File (format 2=320,1=160,0=96); bei Regionssperre in alternative(13) suchen
    NSData*fileId=nil;int bestFmt=-1; unsigned char keyGid[16]; memcpy(keyGid,gidb,16);
    for(NSData*af in psubs(meta,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
        if(fid&&(fmt==0||fmt==1||fmt==2)&&(int)fmt>bestFmt){bestFmt=(int)fmt;fileId=fid;}}
    if(!fileId){
        printf("Haupt-Track ohne OGG -> pruefe alternatives…\n");
        for(NSData*alt in psubs(meta,13)){
            NSData*altgid=psub(alt,1);
            for(NSData*af in psubs(alt,12)){int64_t fmt=pvarval(af,2);NSData*fid=psub(af,1);
                if(fid&&(fmt==0||fmt==1||fmt==2)&&(int)fmt>bestFmt){bestFmt=(int)fmt;fileId=fid;
                    if(altgid.length==16)memcpy(keyGid,altgid.bytes,16);}}
            if(fileId)break;
        }
    }
    if(!fileId){printf("kein OGG-File in Metadaten (auch nicht in alternatives)\n");return 1;}
    printf("file_id=%s (format %d) gid=%s\n",hexstr(fileId.bytes,(int)fileId.length).UTF8String,bestFmt,hexstr(keyGid,16).UTF8String);

    // ---- AudioKey ----
    NSMutableData*akr=[NSMutableData data];[akr appendData:fileId];[akr appendBytes:keyGid length:16];
    uint32_t akseq=htonl(0);[akr appendBytes:&akseq length:4];uint16_t z=0;[akr appendBytes:&z length:2];
    sendpkt(0x0c,akr);
    unsigned char audiokey[16];int haveKey=0;
    for(int i=0;i<50;i++){NSData*r=recvpkt(&cmd);if(!r)break;if(cmd==0x04){sendpkt(0x49,r);continue;}
        if(cmd==0x0d){memcpy(audiokey,(const unsigned char*)r.bytes+4,16);haveKey=1;break;}
        if(cmd==0x0e){printf("AesKeyError\n");return 1;}}
    if(!haveKey){printf("kein AudioKey\n");return 1;}
    printf("✅ AudioKey: %s\n",hexstr(audiokey,16).UTF8String);

    // ---- TEST: storage-resolve ohne OAuth-Token? ----
    if([[[NSProcessInfo processInfo] environment] objectForKey:@"SRTEST"]){
        NSString*srpath=[NSString stringWithFormat:@"/storage-resolve/files/audio/interactive/%@",hexstr(fileId.bytes,(int)fileId.length)];
        printf("\n[A] spclient MIT Bearer:\n");
        NSData*a=spclientGet(spc,srpath,token,ctoken); printf("  -> %lu B\n",(unsigned long)a.length);
        printf("[B] spclient OHNE Bearer (nur client-token):\n");
        NSString*urlB=[NSString stringWithFormat:@"https://%@%@",spc,srpath];
        NSMutableURLRequest*rb=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlB]];
        [rb setValue:ctoken forHTTPHeaderField:@"client-token"];
        NSHTTPURLResponse*hb=nil; NSData*bd=[NSURLConnection sendSynchronousRequest:rb returningResponse:&hb error:NULL];
        printf("  -> HTTP %ld, %lu B\n",(long)hb.statusCode,(unsigned long)bd.length);
        printf("[C] mercury hm://storage-resolve:\n");
        NSData*c=mercuryGet([NSString stringWithFormat:@"hm://storage-resolve/files/audio/interactive/%@",hexstr(fileId.bytes,(int)fileId.length)]);
        printf("  -> %lu B\n",(unsigned long)c.length);
        for(NSData*u in psubs(c,2)){printf("  mercury-cdn: %.60s…\n",[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding].UTF8String);break;}
        return 0;
    }

    // ---- Storage-Resolve -> CDN-URL (spclient HTTPS) ----
    NSData*sr=spclientGet(spc,[NSString stringWithFormat:@"/storage-resolve/files/audio/interactive/%@",hexstr(fileId.bytes,(int)fileId.length)],token,ctoken);
    if(!sr){printf("storage-resolve fail\n");return 1;}
    NSString*cdn=nil;for(NSData*u in psubs(sr,2)){cdn=[[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding];break;}
    if(!cdn){printf("keine CDN-URL (result=%lld)\n",pvarval(sr,1));return 1;}
    printf("✅ CDN: %.70s…\n",cdn.UTF8String);

    // ---- CDN laden (erste 64 KB) + AES-CTR entschlüsseln ----
    NSMutableURLRequest*req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:cdn]];
    // Voll-Download fuer Decoder-Test (kein Range)
    NSData*enc=[NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
    if(!enc.length){printf("CDN-Download leer\n");return 1;}
    printf("CDN geladen: %lu B\n",(unsigned long)enc.length);
    NSMutableData*out=[NSMutableData dataWithLength:enc.length];
    size_t moved=0;CCCryptorRef cr;CCCryptorCreateWithMode(kCCDecrypt,kCCModeCTR,kCCAlgorithmAES,ccNoPadding,AUDIO_IV,audiokey,16,NULL,0,0,kCCModeOptionCTR_BE,&cr);
    CCCryptorUpdate(cr,enc.bytes,enc.length,out.mutableBytes,out.length,&moved);CCCryptorRelease(cr);
    const unsigned char*o=out.bytes;int oggAt=-1;for(int i=0;i+4<(int)out.length;i++){if(o[i]=='O'&&o[i+1]=='g'&&o[i+2]=='g'&&o[i+3]=='S'){oggAt=i;break;}}
    [out writeToFile:@"/tmp/spot-decrypted.ogg" atomically:YES];
    if(oggAt>=0)printf("\n🎉🎉 ENTSCHLÜSSELT! 'OggS' bei Offset %d — echtes Spotify-Audio geladen & dekodiert!\n   -> /tmp/spot-decrypted.ogg\n",oggAt);
    else printf("\n⚠️ Kein OggS gefunden — AES-Key/IV oder Offset prüfen. Erste Bytes: %02x %02x %02x %02x\n",o[0],o[1],o[2],o[3]);
    close(s);return 0;
}}
