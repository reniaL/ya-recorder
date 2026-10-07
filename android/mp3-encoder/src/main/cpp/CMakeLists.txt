cmake_minimum_required(VERSION 3.22)
project(rec07_lame C)

set(ARCHIVE "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/lame/lame-4.0.tar.gz")
file(SHA256 "${ARCHIVE}" ARCHIVE_SHA256)
if(NOT ARCHIVE_SHA256 STREQUAL "3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb")
    message(FATAL_ERROR "LAME source archive checksum mismatch")
endif()
file(ARCHIVE_EXTRACT INPUT "${ARCHIVE}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/upstream")
set(LAME "${CMAKE_CURRENT_BINARY_DIR}/upstream/lame-4.0")
configure_file(lame_config.h.in config.h @ONLY)

# The upstream VBR-tag mask shifts a negative signed integer. Keep the pinned
# archive intact and apply the documented one-line fix to a generated copy.
file(READ "${LAME}/libmp3lame/VbrTag.c" VBR_TAG_SOURCE)
string(FIND "${VBR_TAG_SOURCE}" "~(-1 << (n))" MASK_OFFSET)
if(MASK_OFFSET EQUAL -1)
    message(FATAL_ERROR "LAME VBR tag patch no longer applies")
endif()
string(REPLACE "~(-1 << (n))" "~(~0u << (n))" VBR_TAG_SOURCE "${VBR_TAG_SOURCE}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/VbrTag_project.c" "${VBR_TAG_SOURCE}")

set(LAME_SOURCES
    bitstream.c encoder.c fft.c gain_analysis.c id3tag.c lame.c
    newmdct.c presets.c psymodel.c quantize.c quantize_pvt.c reservoir.c
    set_get.c tables.c takehiro.c util.c vbrquantize.c version.c mpglib_interface.c)
list(TRANSFORM LAME_SOURCES PREPEND "${LAME}/libmp3lame/")
add_library(rec07_lame SHARED ${LAME_SOURCES} "${CMAKE_CURRENT_BINARY_DIR}/VbrTag_project.c" stream_encoder.c lame_jni.c)
set_source_files_properties(stream_encoder.c lame_jni.c PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Werror")
target_include_directories(rec07_lame PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}" "${LAME}" "${LAME}/include" "${LAME}/libmp3lame")
target_compile_definitions(rec07_lame PRIVATE HAVE_CONFIG_H)
target_compile_options(rec07_lame PRIVATE -O2 -fvisibility=hidden)
target_link_options(rec07_lame PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")
target_link_libraries(rec07_lame PRIVATE m)
