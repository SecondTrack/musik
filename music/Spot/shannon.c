// shannon.c — 1:1-Port von rust-shannon (plietar/librespot). Alle Operationen byte-exakt.
#include "shannon.h"
#include <string.h>

#define N 16
#define FOLD 16
#define INITKONST 0x6996c53aU
#define KEYP 13

static uint32_t sbox1(uint32_t w){
    w ^= (w<<5  | w>>(32-5))  | (w<<7  | w>>(32-7));
    w ^= (w<<19 | w>>(32-19)) | (w<<22 | w>>(32-22));
    return w;
}
static uint32_t sbox2(uint32_t w){
    w ^= (w<<7  | w>>(32-7))  | (w<<22 | w>>(32-22));
    w ^= (w<<5  | w>>(32-5))  | (w<<19 | w>>(32-19));
    return w;
}
#define ROTL(w,x) (((w)<<(x)) | ((w)>>(32-(x))))
static uint32_t rdLE(const uint8_t*b){ return (uint32_t)b[0] | (uint32_t)b[1]<<8 | (uint32_t)b[2]<<16 | (uint32_t)b[3]<<24; }
static void     wrLE(uint8_t*b,uint32_t v){ b[0]=v; b[1]=v>>8; b[2]=v>>16; b[3]=v>>24; }

static void cycle(shn_ctx*c){
    uint32_t t = c->R[12] ^ c->R[13] ^ c->konst;
    t = sbox1(t) ^ ROTL(c->R[0],1);
    for(int i=1;i<N;i++) c->R[i-1]=c->R[i];
    c->R[N-1]=t;
    t = sbox2(c->R[2] ^ c->R[15]);
    c->R[0] ^= t;
    c->sbuf = t ^ c->R[8] ^ c->R[12];
}
static void genkonst(shn_ctx*c){ c->konst = c->R[0]; }
static void diffuse(shn_ctx*c){ for(int i=0;i<FOLD;i++) cycle(c); }

static void loadkey(shn_ctx*c,const uint8_t*key,int len){
    int i=0;
    for(; i+4<=len; i+=4){ c->R[KEYP] ^= rdLE(key+i); cycle(c); }
    if(i<len){ uint8_t x[4]={0,0,0,0}; for(int j=0;i+j<len;j++) x[j]=key[i+j]; c->R[KEYP]^=rdLE(x); cycle(c); }
    c->R[KEYP] ^= (uint32_t)len;
    cycle(c);
    memcpy(c->CRC,c->R,sizeof(c->R));
    diffuse(c);
    for(int k=0;k<16;k++) c->R[k]^=c->CRC[k];
}

void shn_key(shn_ctx*c,const uint8_t*key,int keylen){
    memset(c,0,sizeof(*c)); c->konst=INITKONST;
    c->R[0]=1; c->R[1]=1; for(int i=2;i<16;i++) c->R[i]=c->R[i-1]+c->R[i-2];
    loadkey(c,key,keylen);
    genkonst(c);
    memcpy(c->initR,c->R,sizeof(c->R));   // savestate
}
void shn_nonce(shn_ctx*c,const uint8_t*nonce,int len){
    memcpy(c->R,c->initR,sizeof(c->R));   // reloadstate
    c->konst=INITKONST;
    loadkey(c,nonce,len);
    genkonst(c);
    c->nbuf=0;
}
void shn_nonce_u32(shn_ctx*c,uint32_t n){ uint8_t b[4]={n>>24,n>>16,n>>8,n}; shn_nonce(c,b,4); }

static void crcfunc(shn_ctx*c,uint32_t i){
    uint32_t t = c->CRC[0]^c->CRC[2]^c->CRC[15]^i;
    for(int j=1;j<N;j++) c->CRC[j-1]=c->CRC[j];
    c->CRC[N-1]=t;
}
static void macfunc(shn_ctx*c,uint32_t i){ crcfunc(c,i); c->R[KEYP]^=i; }

// mode: 0=encrypt, 1=decrypt
static void process(shn_ctx*c,uint8_t*buf,int n,int decryptMode){
    int pos=0;
    // übrig gebliebene Teilwort-Bytes aus vorherigem Aufruf
    if(c->nbuf!=0){
        while(c->nbuf>0){
            if(pos>=n) return;               // noch kein ganzes Wort
            uint8_t b=buf[pos];
            if(decryptMode){ b ^= (c->sbuf >> (32-c->nbuf)) & 0xFF; c->mbuf ^= (uint32_t)b << (32-c->nbuf); }
            else           { c->mbuf ^= (uint32_t)b << (32-c->nbuf); b ^= (c->sbuf >> (32-c->nbuf)) & 0xFF; }
            buf[pos]=b; pos++;
            c->nbuf-=8;
            macfunc(c,c->mbuf);
        }
    }
    // ganze Wörter
    int whole = (n-pos) & ~0x3;
    int end = pos+whole;
    for(; pos<end; pos+=4){
        cycle(c);
        uint32_t t=rdLE(buf+pos);
        if(decryptMode){ t ^= c->sbuf; macfunc(c,t); }
        else           { macfunc(c,t); t ^= c->sbuf; }
        wrLE(buf+pos,t);
    }
    // Rest-Bytes
    if(pos<n){
        cycle(c);
        c->mbuf=0; c->nbuf=32;
        for(; pos<n; pos++){
            uint8_t b=buf[pos];
            if(decryptMode){ b ^= (c->sbuf >> (32-c->nbuf)) & 0xFF; c->mbuf ^= (uint32_t)b << (32-c->nbuf); }
            else           { c->mbuf ^= (uint32_t)b << (32-c->nbuf); b ^= (c->sbuf >> (32-c->nbuf)) & 0xFF; }
            buf[pos]=b;
            c->nbuf-=8;
        }
    }
}
void shn_encrypt(shn_ctx*c,uint8_t*buf,int n){ process(c,buf,n,0); }
void shn_decrypt(shn_ctx*c,uint8_t*buf,int n){ process(c,buf,n,1); }

void shn_finish(shn_ctx*c,uint8_t*buf,int n){
    if(c->nbuf!=0) macfunc(c,c->mbuf);
    cycle(c);
    c->R[KEYP] ^= INITKONST ^ ((uint32_t)c->nbuf<<3);
    c->nbuf=0;
    for(int i=0;i<N;i++) c->R[i]^=c->CRC[i];
    diffuse(c);
    int pos=0;
    for(; pos+4<=n; pos+=4){ cycle(c); wrLE(buf+pos,c->sbuf); }
    if(pos<n){ cycle(c); for(int i=0;pos<n;pos++,i++) buf[pos]=(c->sbuf>>(8*i))&0xFF; }
}
