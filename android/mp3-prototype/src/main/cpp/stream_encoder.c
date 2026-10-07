#include "stream_encoder.h"
#include "lame.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

struct rec07_encoder {
    lame_t lame;
    FILE *file;
    unsigned char mp3[REC07_CHUNK_SAMPLES * 5 / 4 + 7200];
    int finished;
    int failed;
};

static int write_bytes(rec07_encoder *encoder, int bytes) {
    if (bytes < 0 || fwrite(encoder->mp3, 1, (size_t) bytes, encoder->file) != (size_t) bytes) {
        encoder->failed = 1;
        return -1;
    }
    return bytes;
}

rec07_encoder *rec07_open(const char *path, int bitrate_kbps, int quality) {
    if (!path || (bitrate_kbps != 64 && bitrate_kbps != 96) || (quality != 2 && quality != 5)) return NULL;
    rec07_encoder *encoder = calloc(1, sizeof(*encoder));
    if (!encoder) return NULL;
    encoder->lame = lame_init();
    if (!encoder->lame) { rec07_close(encoder); return NULL; }
    lame_set_write_id3tag_automatic(encoder->lame, 0);
    if (lame_set_in_samplerate(encoder->lame, REC07_SAMPLE_RATE) < 0 ||
        lame_set_out_samplerate(encoder->lame, REC07_SAMPLE_RATE) < 0 ||
        lame_set_num_channels(encoder->lame, 1) < 0 ||
        lame_set_mode(encoder->lame, MONO) < 0 ||
        lame_set_VBR(encoder->lame, vbr_off) < 0 ||
        lame_set_brate(encoder->lame, bitrate_kbps) < 0 ||
        lame_set_quality(encoder->lame, quality) < 0 ||
        lame_set_bWriteVbrTag(encoder->lame, 1) < 0 ||
        lame_set_findReplayGain(encoder->lame, 0) < 0 ||
        lame_init_params(encoder->lame) < 0) {
        rec07_close(encoder); return NULL;
    }
    encoder->file = fopen(path, "wb");
    if (!encoder->file) { rec07_close(encoder); return NULL; }
    return encoder;
}

int rec07_encode(rec07_encoder *encoder, const int16_t *pcm, int samples) {
    if (!encoder || !pcm || samples <= 0 || samples > REC07_CHUNK_SAMPLES ||
        encoder->finished || encoder->failed) return -1;
    return write_bytes(encoder, lame_encode_buffer(encoder->lame, pcm, pcm, samples,
        encoder->mp3, sizeof(encoder->mp3)));
}

int rec07_finish(rec07_encoder *encoder) {
    if (!encoder || encoder->finished || encoder->failed) return -1;
    encoder->finished = 1;
    if (write_bytes(encoder, lame_encode_flush(encoder->lame, encoder->mp3, sizeof(encoder->mp3))) < 0) return -1;
    /* Replace LAME's reserved first frame with frame count/delay/padding info. */
    size_t tag_size = lame_get_lametag_frame(encoder->lame, encoder->mp3, sizeof(encoder->mp3));
    if (!tag_size || tag_size > sizeof(encoder->mp3) || fseek(encoder->file, 0, SEEK_SET) ||
        write_bytes(encoder, (int) tag_size) < 0 || fflush(encoder->file) || fsync(fileno(encoder->file))) {
        encoder->failed = 1;
        return -1;
    }
    int result = fclose(encoder->file);
    encoder->file = NULL;
    if (result) encoder->failed = 1;
    return result;
}

void rec07_close(rec07_encoder *encoder) {
    if (!encoder) return;
    if (encoder->file) fclose(encoder->file);
    if (encoder->lame) lame_close(encoder->lame);
    free(encoder);
}

const char *rec07_version(void) { return get_lame_version(); }
