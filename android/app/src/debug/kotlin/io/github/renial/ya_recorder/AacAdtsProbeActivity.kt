package io.github.renial.ya_recorder

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Debug-only, foreground probe. Never writes the production recording index. */
class AacAdtsProbeActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private var permissionResult: MethodChannel.Result? = null
    private var worker: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ya_recorder/aac_adts_probe")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 808)
                    }
                }
                "capture" -> {
                    if (worker != null) result.error("busy", "Capture already running", null)
                    else capture(result)
                }
                "saveReport" -> {
                    val directory = File(filesDir, "aac-adts-probe").apply { mkdirs() }
                    File(directory, "last-report.json").writeText(call.arguments as String)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == 808) {
            permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        } else super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun phase(value: String) = main.post { channel.invokeMethod("phase", value) }

    private fun capture(result: MethodChannel.Result) {
        worker = Thread {
            val recorder = AacRecordingBackend(RecordingFormat.AAC)
            try {
                val directory = File(filesDir, "aac-adts-probe").apply { mkdirs() }
                val file = File(directory, "sample-${System.currentTimeMillis()}.aac")
                val temporaryFile = File(directory, "${file.name}.part")
                recorder.prepare(temporaryFile)
                recorder.start()
                var start = SystemClock.elapsedRealtime()
                phase("录音前半段：请说出 1、2、3、4")
                Thread.sleep(4000)
                recorder.pause()
                var activeMs = SystemClock.elapsedRealtime() - start
                phase("暂停 2 秒：此时声音不应进入文件")
                Thread.sleep(2000)
                recorder.resume()
                start = SystemClock.elapsedRealtime()
                phase("录音后半段：请说出 5、6、7、8")
                Thread.sleep(4000)
                recorder.stop()
                activeMs += SystemClock.elapsedRealtime() - start
                check(temporaryFile.renameTo(file)) { "Unable to finalize probe sample" }
                phase("完整解码验证")
                val media = AacAdtsProbeMedia.inspect(file)
                val report = media + mapOf(
                    "filePath" to file.absolutePath,
                    "fileSizeBytes" to file.length(),
                    "activeCaptureMs" to activeMs,
                    "pauseMs" to 2000,
                    "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "androidApi" to Build.VERSION.SDK_INT,
                    "requestedBitrate" to 128000,
                    "requestedSampleRate" to 44100,
                )
                main.post { result.success(report) }
            } catch (error: Exception) {
                main.post { result.error("probe-failed", error.toString(), null) }
            } finally {
                recorder.release()
                main.post { worker = null }
            }
        }.also { it.start() }
    }

    override fun onPause() {
        // This harness does not test background recording; abort when leaving it.
        worker?.interrupt()
        super.onPause()
    }

    override fun onDestroy() {
        worker?.interrupt()
        channel.setMethodCallHandler(null)
        super.onDestroy()
    }
}
