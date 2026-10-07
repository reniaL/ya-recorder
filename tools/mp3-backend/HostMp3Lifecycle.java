package io.github.renial.ya_recorder;

import java.io.File;
import java.util.concurrent.TimeUnit;

/** Runs production backend and JNI bytecode on a Linux JVM with synthetic PCM.
 * Accelerated input is not Android microphone or device performance evidence.
 */
public final class HostMp3Lifecycle {
    private static final class ToneSource implements PcmSource {
        volatile long samples;
        volatile long target = 44100 * 2 + 37;
        boolean running;
        long due;
        int starts, stops, releases;

        public void onCaptureThread() {}
        public void start() { running = true; starts++; due = 0; }
        public int read(short[] buffer) {
            if (!running || samples == target || System.nanoTime() < due) return 0;
            int count = (int) Math.min(buffer.length, target - samples);
            for (int i = 0; i < count; i++) {
                buffer[i] = (short) (12000 * Math.sin(2 * Math.PI * 440 * (samples + i) / 44100));
            }
            samples += count;
            due = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(5);
            return count;
        }
        public void stop() { running = false; stops++; }
        public void release() { releases++; }
    }

    private static void awaitSamples(ToneSource source) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (source.samples < source.target && System.nanoTime() < deadline) Thread.sleep(2);
        if (source.samples != source.target) throw new AssertionError("PCM capture did not reach target");
    }

    public static void main(String[] args) throws Exception {
        ToneSource source = new ToneSource();
        Mp3RecordingBackend backend = new Mp3RecordingBackend(() -> source, AndroidMp3Encoder::new,
            new Mp3Config(44100, 4410, 16, 5000));
        File output = new File(args[0]);
        try {
            backend.prepare(output);
            backend.start();
            awaitSamples(source);
            backend.pause();
            long pausedMs = backend.getElapsedMs();
            long pausedSamples = source.samples;
            Thread.sleep(40);
            if (source.samples != pausedSamples || backend.getElapsedMs() != pausedMs) {
                throw new AssertionError("Pause captured audio or advanced duration");
            }
            source.target += 44100 * 3 + 23;
            backend.resume();
            awaitSamples(source);
            backend.stop();
            backend.stop();
            backend.release();
            if (source.samples != 220560 || source.starts != 2 || source.stops != 2 || source.releases != 1 ||
                    backend.getElapsedMs() != source.samples * 1000 / 44100 || output.length() <= 0) {
                throw new AssertionError("Unexpected sample duration, lifecycle or output");
            }
            System.out.println("{\"samples\":" + source.samples + ",\"durationMs\":" + backend.getElapsedMs()
                + ",\"sourceStarts\":2,\"sourceStops\":2,\"sourceReleases\":1}");
        } finally { backend.release(); }
    }
}
