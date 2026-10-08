package io.github.renial.ya_recorder;

import io.github.renial.ya_recorder.mp3.LameEncoder;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;

/** Actual production prefix recovery for finalized-truncated and unflushed JNI output. */
public final class HostRecovery {
    public static void main(String[] args) throws Exception {
        File directory = new File(args[0]);
        byte[] complete = Files.readAllBytes(new File(directory, "recording-host.mp3.part").toPath());
        File truncated = new File(directory, "truncated.mp3.part");
        Files.write(truncated.toPath(), Arrays.copyOf(complete, complete.length - 73));
        File unflushed = new File(directory, "unflushed.mp3.part");
        LameEncoder encoder = new LameEncoder();
        long handle = encoder.open(unflushed.getAbsolutePath(), 64, 5);
        if (handle == 0) throw new AssertionError("Encoder did not initialize");
        try {
            for (int start = 0; start < 44100 * 5; start += 4410) {
                short[] samples = new short[4410];
                for (int i = 0; i < samples.length; i++) {
                    samples[i] = (short)(12000 * Math.sin(2 * Math.PI * 440 * (start + i) / 44100));
                }
                if (encoder.encode(handle, samples, samples.length) < 0) throw new AssertionError("Encode failed");
            }
        } finally { encoder.close(handle); } // Intentionally no finish/flush.
        for (File source : new File[]{truncated, unflushed}) {
            byte[] before = Files.readAllBytes(source.toPath());
            File repaired = new File(directory, source.getName() + ".repaired.mp3");
            Mp3FrameRecovery.INSTANCE.copyCompletePrefix(source, repaired);
            if (!Arrays.equals(before, Files.readAllBytes(source.toPath()))) {
                throw new AssertionError("Original residual changed");
            }
            if (repaired.length() <= 0 || repaired.length() > source.length()) {
                throw new AssertionError("Invalid recovered prefix length");
            }
        }
    }
}
