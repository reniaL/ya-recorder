package io.github.renial.ya_recorder.mp3prototype

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import org.json.JSONObject
import java.io.File

class PrototypeService : Service() {
    private var run: PrototypeRun? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            run?.requestStop()
            if (run == null) stopSelf()
            return START_NOT_STICKY
        }
        if (running || intent == null) return START_NOT_STICKY
        val config = PrototypeConfig(intent.getIntExtra("seconds", 10), intent.getBooleanExtra("tone", false),
            intent.getIntExtra("bitrate", 64), intent.getIntExtra("quality", 5), intent.getIntExtra("encoderDelayMs", 0))
        val directory = File(filesDir, "runs/${checkNotNull(intent.getStringExtra("runId"))}")
        val manager = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("rec07", "MP3 原型测试", NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this, "rec07")
        } else Notification.Builder(this)
        startForeground(7, builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("REC-07 MP3 原型正在运行").setContentText("返回测试应用可提前停止")
            .setOngoing(true).build())
        val wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ya-recorder:rec07-prototype")
        wakeLock.acquire((config.seconds + 120L) * 1000)
        val experiment = PrototypeRun(applicationContext, config, directory)
        run = experiment
        running = true
        Thread({
            try { experiment.execute() }
            catch (error: Throwable) {
                val report = JSONObject().put("status", "failed").put("error", "${error.javaClass.simpleName}: ${error.message}")
                try { File(directory, "result.json").writeText(report.toString(2)) }
                catch (_: Throwable) { android.util.Log.e("REC07", report.toString()) }
            } finally {
                if (wakeLock.isHeld) wakeLock.release()
                handler.post {
                    run = null
                    running = false
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }, "rec07-run").start()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        run?.requestStop()
        super.onDestroy()
    }

    companion object { @Volatile var running = false; private set }
}
