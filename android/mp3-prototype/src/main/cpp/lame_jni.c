#include "stream_encoder.h"
#include <jni.h>
#include <stdint.h>

#define JNI_NAME(name) Java_io_github_renial_ya_1recorder_mp3prototype_LameEncoder_##name

JNIEXPORT jlong JNICALL JNI_NAME(open)(JNIEnv *env, jobject self, jstring path, jint bitrate, jint quality) {
    (void) self;
    if (!path) return 0;
    const char *text = (*env)->GetStringUTFChars(env, path, NULL);
    if (!text) return 0;
    rec07_encoder *encoder = rec07_open(text, bitrate, quality);
    (*env)->ReleaseStringUTFChars(env, path, text);
    return (jlong) (intptr_t) encoder;
}

JNIEXPORT jint JNICALL JNI_NAME(encode)(JNIEnv *env, jobject self, jlong handle, jshortArray pcm, jint count) {
    (void) self;
    if (!handle || !pcm || count <= 0 || count > REC07_CHUNK_SAMPLES || count > (*env)->GetArrayLength(env, pcm)) return -1;
    jshort *samples = (*env)->GetShortArrayElements(env, pcm, NULL);
    if (!samples) return -1;
    int result = rec07_encode((rec07_encoder *) (intptr_t) handle, samples, count);
    (*env)->ReleaseShortArrayElements(env, pcm, samples, JNI_ABORT);
    return result;
}

JNIEXPORT jint JNICALL JNI_NAME(finish)(JNIEnv *env, jobject self, jlong handle) {
    (void) env; (void) self;
    return rec07_finish((rec07_encoder *) (intptr_t) handle);
}

JNIEXPORT void JNICALL JNI_NAME(close)(JNIEnv *env, jobject self, jlong handle) {
    (void) env; (void) self;
    rec07_close((rec07_encoder *) (intptr_t) handle);
}

JNIEXPORT jstring JNICALL JNI_NAME(version)(JNIEnv *env, jobject self) {
    (void) self;
    return (*env)->NewStringUTF(env, rec07_version());
}
