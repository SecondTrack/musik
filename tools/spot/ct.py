#!/usr/bin/env python3
# ct.py — fragt Spotifys client-token an und zeigt, ob direkt ein Token kommt oder eine Challenge.
import urllib.request, urllib.error
def var(n):
    out=b''
    while True:
        b=n&0x7f; n>>=7
        out+=bytes([b|0x80]) if n else bytes([b])
        if not n: break
    return out
def tag(f,wt): return var((f<<3)|wt)
def s(f,val):
    b=val.encode() if isinstance(val,str) else val
    return tag(f,2)+var(len(b))+b
def vf(f,n): return tag(f,0)+var(n)
def msg(f,b): return tag(f,2)+var(len(b))+b
def rv(d,i):
    n=0;sh=0
    while True:
        b=d[i]; i+=1; n|=(b&0x7f)<<sh
        if not b&0x80: break
        sh+=7
    return n,i

cid="65b708073fc0480ea92a077233ca87bd"
ver="1.2.52.442.g01c3f6ee"
device_id="0123456789abcdef0123456789abcdef01234567"   # 40 hex, stabil
# NativeDesktopMacOSData: system_version(1), hw_model(2), compiled_cpu_type(3)
macos=s(1,"13.4.0")+s(2,"MacBookPro18,3")+s(3,"arm64")
psd=msg(3,macos)                      # PlatformSpecificData.desktop_macos (feld 3)
conn=msg(1,psd)+s(2,device_id)        # ConnectivitySdkData: platform(1), device_id(2)
cdr=s(1,ver)+s(2,cid)+msg(3,conn)     # ClientDataRequest: version(1), client_id(2), connectivity(3)
req=vf(1,1)+msg(2,cdr)
r=urllib.request.Request("https://clienttoken.spotify.com/v1/clienttoken",data=req,
  headers={"Content-Type":"application/x-protobuf","Accept":"application/x-protobuf"})
try:
    data=urllib.request.urlopen(r,timeout=12).read(); code=200
except urllib.error.HTTPError as e:
    code=e.code; data=e.read()
print("HTTP",code,"resp",len(data),"bytes")
pos=0
while pos<len(data):
    t,pos=rv(data,pos); f=t>>3; wt=t&7
    if wt==0:
        val,pos=rv(data,pos); print(" field",f,"=",val, "(1=GRANTED, 2=CHALLENGE)" if f==1 else "")
    elif wt==2:
        l,pos=rv(data,pos); ch=data[pos:pos+l]; pos+=l
        print(" field",f,"len",l,repr(ch[:40]))
        if f in (2,3):
            p2=0
            while p2<len(ch):
                tt,p2=rv(ch,p2); ff=tt>>3; ww=tt&7
                if ww==2:
                    ll,p2=rv(ch,p2); print("    sub",ff,repr(ch[p2:p2+ll][:70])); p2+=ll
                elif ww==0:
                    vv,p2=rv(ch,p2); print("    sub",ff,"=",vv)
                else: break
    else: break
