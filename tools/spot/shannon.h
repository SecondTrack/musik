// shannon.h — Shannon-Stream-Cipher (Hawkes/Rose), 1:1-Port von rust-shannon (librespot).
// Für Spotifys Paket-Verschlüsselung. Portabel (Mac-Spike + später iOS 6).
#ifndef MESH_SHANNON_H
#define MESH_SHANNON_H
#include <stdint.h>
typedef struct { uint32_t R[16], CRC[16], initR[16], konst, sbuf, mbuf; int nbuf; } shn_ctx;
void shn_key(shn_ctx *c, const uint8_t *key, int keylen);   // init + loadkey + savestate
void shn_nonce(shn_ctx *c, const uint8_t *nonce, int len);
void shn_nonce_u32(shn_ctx *c, uint32_t n);
void shn_encrypt(shn_ctx *c, uint8_t *buf, int n);
void shn_decrypt(shn_ctx *c, uint8_t *buf, int n);
void shn_finish(shn_ctx *c, uint8_t *mac, int n);
#endif
