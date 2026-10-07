# LAME source dependency

Pinned upstream release: **4.0**, source only; the original archive is unmodified.

- Project: https://lame.sourceforge.io/
- Release: https://sourceforge.net/projects/lame/files/lame/4.0/
- Archive: https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz?download=1
- SHA-256: `3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb`
- License: GNU Library General Public License version 2 or later, as stated in
  upstream source headers. The original license is included in `COPYING` and
  in the complete corresponding source archive.

The archive is checked and extracted into the build directory. Builds do not
download native dependencies. The project supplies its own CMake configuration
and JNI wrapper; no abandoned Android wrapper or prebuilt `.so` is used.
The encoder uses portable C without assembler/SSE or the optional MP3 decoder.

Project change: a generated copy of `libmp3lame/VbrTag.c` changes
`~(-1 << (n))` to `~(~0u << (n))` in `SHIFT_IN_BITS_VALUE`. This preserves the
low-bit mask while avoiding undefined signed-negative left shift, reported by
NDK Clang. CMake and the host smoke runner both assert that the original text
exists before applying this one-line change. All other upstream sources are
compiled unchanged. The modification is maintained in the accompanying build
scripts, dated 2026-10-07, by the ya-recorder project.

The prototype packages the encoder and wrapper as `librec07_lame.so`. Keep this
notice, license, full source archive and build instructions with the experiment.
Production integration and distribution requirements are a later work item.
