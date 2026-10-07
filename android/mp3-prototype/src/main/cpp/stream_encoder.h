#ifndef REC07_STREAM_ENCODER_H
#define REC07_STREAM_ENCODER_H
#include <stdint.h>

/* One encoder, owned by one encoding thread. Fixed buffers, no entire PCM file. */
typedef struct rec07_encoder rec07_encoder;
enum { REC07_SAMPLE_RATE = 44100, REC07_CHUNK_SAMPLES = 4410 };
rec07_encoder *rec07_open(const char *path, int bitrate_kbps, int quality);
int rec07_encode(rec07_encoder *encoder, const int16_t *pcm, int samples);
int rec07_finish(rec07_encoder *encoder);
void rec07_close(rec07_encoder *encoder);
const char *rec07_version(void);
#endif
