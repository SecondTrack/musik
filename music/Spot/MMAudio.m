#import "MMAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

// stb_vorbis direkt einbinden (kein separates Kompilat -> keine Doppel-Symbole).
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

#define NUMBUF 3
#define BUFFRAMES 8192   // Frames pro Puffer

static AudioQueueRef gAQ=NULL;
static stb_vorbis *gV=NULL;
static NSData *gOgg=nil;        // festhalten: stb_vorbis liest direkt aus diesem Speicher
static int gCh=2;
static double gSampleRate=44100.0, gDuration=0.0, gBaseTime=0.0;
static BOOL gRunning=NO, gPaused=NO;

// ---- Analyse fürs Visualisieren: pro Block (1024 Frames) Pegel, Bass und 64 Wellenpunkte.
// Abgelegt nach absoluter Frame-Position, damit die Anzeige zur HÖRBAREN Stelle passt (Puffer laufen ~0,4 s voraus).
#define VBLK 1024
#define VRING 128
#define VPTS 64
static long  gFed=0;                       // bisher dekodierte Frames (absolut, ab Songanfang)
static long  gVIdx[VRING];
static float gVLvl[VRING], gVBass[VRING], gVWave[VRING][VPTS];
static float gLp=0;                        // Tiefpass-Zustand für Bass
static void analyze(const short*s,int frames,int ch){
    for(int off=0; off+VBLK<=frames; off+=VBLK){
        long blk=(gFed+off)/VBLK; int slot=(int)(blk%VRING);
        double sum=0,bs=0; const short*p=s+off*ch;
        for(int i=0;i<VBLK;i++){
            float v=0; for(int c=0;c<ch;c++) v+=p[i*ch+c]; v/=(32768.f*ch);
            sum+=v*v; gLp+=0.02f*(v-gLp); bs+=gLp*gLp;
            if(i%(VBLK/VPTS)==0) gVWave[slot][i/(VBLK/VPTS)]=v;
        }
        gVLvl[slot]=sqrtf(sum/VBLK); gVBass[slot]=sqrtf(bs/VBLK); gVIdx[slot]=blk;
    }
    gFed+=frames;
}

static void fillCb(void *ud, AudioQueueRef q, AudioQueueBufferRef buf){
    if(!gV || !gRunning){ buf->mAudioDataByteSize=0; return; }
    short *out=(short*)buf->mAudioData;
    int capShorts=buf->mAudioDataBytesCapacity/(int)sizeof(short);
    int got=stb_vorbis_get_samples_short_interleaved(gV,gCh,out,capShorts); // got = Frames pro Kanal
    if(got<=0){ // Ende
        buf->mAudioDataByteSize=0;
        gRunning=NO;
        AudioQueueStop(q,false);  // asynchron auslaufen lassen
        dispatch_async(dispatch_get_main_queue(), ^{   // Track zu Ende -> Auto-Advance
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioDidFinish" object:nil];
        });
        return;
    }
    analyze(out,got,gCh);
    buf->mAudioDataByteSize=got*gCh*(int)sizeof(short);
    AudioQueueEnqueueBuffer(q,buf,0,NULL);
}

@implementation MMAudio

+ (void)playOgg:(NSData *)ogg {
    [self stop];
    if(ogg.length<=167) return;
    // Playback-Session: spielt auch bei Stummschalter & im Hintergrund/gesperrt weiter
    AVAudioSession*as=[AVAudioSession sharedInstance];
    [as setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [as setActive:YES error:NULL];
    gOgg=ogg;
    int err=0;
    gV=stb_vorbis_open_memory((const unsigned char*)ogg.bytes+167,(int)ogg.length-167,&err,NULL);
    if(!gV){ gOgg=nil; return; }
    stb_vorbis_info info=stb_vorbis_get_info(gV);
    gCh=info.channels>0?info.channels:2;
    gSampleRate=info.sample_rate>0?info.sample_rate:44100.0;
    gDuration=stb_vorbis_stream_length_in_seconds(gV);
    gBaseTime=0; gFed=0; gLp=0; memset(gVIdx,0xff,sizeof(gVIdx));

    AudioStreamBasicDescription a; memset(&a,0,sizeof(a));
    a.mSampleRate=info.sample_rate;
    a.mFormatID=kAudioFormatLinearPCM;
    a.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    a.mBitsPerChannel=16;
    a.mChannelsPerFrame=gCh;
    a.mFramesPerPacket=1;
    a.mBytesPerFrame=2*gCh;
    a.mBytesPerPacket=2*gCh;

    gRunning=YES; gPaused=NO;
    if(AudioQueueNewOutput(&a,fillCb,NULL,NULL,NULL,0,&gAQ)!=0){ [self stop]; return; }
    for(int i=0;i<NUMBUF;i++){
        AudioQueueBufferRef b=NULL;
        AudioQueueAllocateBuffer(gAQ,BUFFRAMES*2*gCh,&b);
        fillCb(NULL,gAQ,b);
    }
    AudioQueueStart(gAQ,NULL);
}

+ (void)stop {
    gRunning=NO;
    if(gAQ){ AudioQueueStop(gAQ,true); AudioQueueDispose(gAQ,true); gAQ=NULL; }
    if(gV){ stb_vorbis_close(gV); gV=NULL; }
    gOgg=nil; gPaused=NO;
}

+ (void)setPaused:(BOOL)paused {
    if(!gAQ) return;
    gPaused=paused;
    if(paused) AudioQueuePause(gAQ); else AudioQueueStart(gAQ,NULL);
}

+ (BOOL)isPlaying { return gRunning && !gPaused; }

+ (double)duration { return gDuration; }

+ (double)currentTime {
    if(!gAQ) return gBaseTime;
    AudioTimeStamp ts; memset(&ts,0,sizeof(ts));
    OSStatus r=AudioQueueGetCurrentTime(gAQ,NULL,&ts,NULL);
    double t=gBaseTime;
    if(r==0 && (ts.mFlags & kAudioTimeStampSampleTimeValid)) t+=ts.mSampleTime/(gSampleRate>0?gSampleRate:44100.0);
    if(t<0) t=0; if(gDuration>0 && t>gDuration) t=gDuration;
    return t;
}

+ (void)seekTo:(double)seconds {
    if(!gV) return;
    if(seconds<0)seconds=0; if(gDuration>0&&seconds>gDuration)seconds=gDuration;
    if(gAQ){ AudioQueueStop(gAQ,true); AudioQueueDispose(gAQ,true); gAQ=NULL; }
    stb_vorbis_seek(gV,(unsigned int)(seconds*gSampleRate));
    gBaseTime=seconds; gRunning=YES; gPaused=NO; gFed=(long)(seconds*gSampleRate); memset(gVIdx,0xff,sizeof(gVIdx));
    AudioStreamBasicDescription a; memset(&a,0,sizeof(a));
    a.mSampleRate=gSampleRate; a.mFormatID=kAudioFormatLinearPCM;
    a.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    a.mBitsPerChannel=16; a.mChannelsPerFrame=gCh; a.mFramesPerPacket=1; a.mBytesPerFrame=2*gCh; a.mBytesPerPacket=2*gCh;
    if(AudioQueueNewOutput(&a,fillCb,NULL,NULL,NULL,0,&gAQ)!=0) return;
    for(int i=0;i<NUMBUF;i++){ AudioQueueBufferRef b=NULL; AudioQueueAllocateBuffer(gAQ,BUFFRAMES*2*gCh,&b); fillCb(NULL,gAQ,b); }
    AudioQueueStart(gAQ,NULL);
}

+ (BOOL)visual:(float *)level bass:(float *)bass wave:(float *)wave {
    if(!gAQ || gPaused || !gRunning) return NO;
    long blk=(long)([self currentTime]*gSampleRate)/VBLK; int slot=(int)(blk%VRING);
    if(blk<0 || gVIdx[slot]!=blk) return NO;
    if(level)*level=gVLvl[slot]; if(bass)*bass=gVBass[slot];
    if(wave) memcpy(wave,gVWave[slot],sizeof(float)*VPTS);
    return YES;
}

@end
