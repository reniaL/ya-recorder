#define _POSIX_C_SOURCE 200809L
#include "stream_encoder.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <time.h>

static double monotonic_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * 1000.0 + now.tv_nsec / 1000000.0;
}

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    const long long total = atoll(argv[2]);
    if (total <= 0 || total > 7200LL * REC07_SAMPLE_RATE) return 2;
    /* Failed initialization must not create a misleading output. */
    assert(rec07_open(argv[1], 128, 5) == NULL);
    assert(rec07_open("/no-such-rec07-directory/audio.mp3", 64, 5) == NULL);
    rec07_encoder *encoder = rec07_open(argv[1], atoi(argv[3]), atoi(argv[4]));
    assert(encoder != NULL);
    short pcm[REC07_CHUNK_SAMPLES];
    assert(rec07_encode(encoder, pcm, 0) == -1);
    assert(rec07_encode(encoder, pcm, REC07_CHUNK_SAMPLES + 1) == -1);
    const double start = monotonic_ms();
    double max_block = 0;
    long max_rss_kb = 0;
    long first_rss_kb = 0;
    for (long long offset = 0; offset < total;) {
        const int count = (total - offset > REC07_CHUNK_SAMPLES) ? REC07_CHUNK_SAMPLES : (int) (total - offset);
        for (int i = 0; i < count; i++) pcm[i] = (short) (12000 * sin(2 * 3.141592653589793 * 440 * (offset + i) / REC07_SAMPLE_RATE));
        const double before = monotonic_ms();
        assert(rec07_encode(encoder, pcm, count) >= 0);
        const double elapsed = monotonic_ms() - before;
        if (elapsed > max_block) max_block = elapsed;
        offset += count;
        if (offset % (10 * REC07_SAMPLE_RATE) == 0 || offset == total) {
            struct rusage usage;
            getrusage(RUSAGE_SELF, &usage);
            if (!first_rss_kb) first_rss_kb = usage.ru_maxrss;
            if (usage.ru_maxrss > max_rss_kb) max_rss_kb = usage.ru_maxrss;
        }
    }
    const double before_finish = monotonic_ms();
    assert(rec07_finish(encoder) == 0);
    const double finish_ms = monotonic_ms() - before_finish;
    assert(rec07_finish(encoder) == -1);
    assert(rec07_encode(encoder, pcm, 1) == -1);
    rec07_close(encoder);
    /* A full disk must produce an error, never a successful flush. */
    encoder = rec07_open("/dev/full", 64, 5);
    assert(encoder != NULL);
    for (int i = 0; i < 20; i++) if (rec07_encode(encoder, pcm, REC07_CHUNK_SAMPLES) < 0) break;
    assert(rec07_finish(encoder) != 0);
    rec07_close(encoder);
    printf("{\"lameVersion\":\"%s\",\"samples\":%lld,\"wallMs\":%.3f,\"maxEncodeBlockMs\":%.3f,\"flushSyncMs\":%.3f,\"firstMaxRssKb\":%ld,\"maxRssKb\":%ld}\n",
        rec07_version(), total, before_finish - start, max_block, finish_ms, first_rss_kb, max_rss_kb);
    return 0;
}
