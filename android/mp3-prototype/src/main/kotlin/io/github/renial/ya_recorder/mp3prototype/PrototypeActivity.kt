package io.github.renial.ya_recorder.mp3prototype

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.util.UUID

class PrototypeActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private var runId: String? = null
    private val ticker = object : Runnable {
        override fun run() {
            runId?.let { id ->
                val directory = File(filesDir, "runs/$id")
                val result = File(directory, "result.json")
                val progress = File(directory, "progress.json")
                val file = if (result.exists()) result else progress
                status.text = if (file.exists()) file.readText() else "原型运行中：$id"
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
        }
        layout.addView(TextView(this).apply { text = "REC-07 MP3 原型（独立测试应用）"; textSize = 20f })
        for ((label, seconds, tone) in listOf(
            Triple("麦克风录制 10 秒", 10, false), Triple("麦克风录制 1 小时", 3600, false),
            Triple("测试音编码 10 秒", 10, true), Triple("测试音编码 1 小时", 3600, true))) {
            layout.addView(Button(this).apply {
                text = label
                setOnClickListener { start(Intent().putExtra("seconds", seconds).putExtra("tone", tone)) }
            })
        }
        layout.addView(Button(this).apply {
            text = "提前停止并检查已录部分"
            setOnClickListener { startService(Intent(this@PrototypeActivity, PrototypeService::class.java).setAction("stop")) }
        })
        status = TextView(this).apply {
            text = "参数候选：44.1 kHz / 单声道 / CBR 64 kbps / quality 5。\n结果保存在应用私有 runs 目录。"
            setTextIsSelectable(true)
        }
        layout.addView(status)
        setContentView(ScrollView(this).apply { addView(layout) })
        runId = savedInstanceState?.getString("runId")
        handler.post(ticker)
        if (savedInstanceState == null) handleCommand(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCommand(intent)
    }

    private fun handleCommand(options: Intent) {
        if (options.getBooleanExtra("stoprun", false)) {
            startService(Intent(this, PrototypeService::class.java).setAction("stop"))
        } else if (options.getBooleanExtra("autorun", false)) start(options)
    }

    private fun start(options: Intent) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            status.text = "请授权麦克风后重新启动测试。"
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
            return
        }
        if (PrototypeService.running) {
            status.text = "已有原型正在运行，请等待结束或提前停止。"
            return
        }
        val id = options.getStringExtra("runId") ?: UUID.randomUUID().toString()
        if (!id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { status.text = "无效测试标识"; return }
        try {
            PrototypeConfig(options.getIntExtra("seconds", 10), options.getBooleanExtra("tone", false),
                options.getIntExtra("bitrate", 64), options.getIntExtra("quality", 5), options.getIntExtra("encoderDelayMs", 0))
        } catch (_: IllegalArgumentException) { status.text = "无效测试参数"; return }
        // Do not reuse a previous run directory or overwrite its recording/evidence.
        if (File(filesDir, "runs/$id").exists()) { status.text = "测试标识已存在"; return }
        runId = id
        val command = Intent(this, PrototypeService::class.java).putExtras(options).putExtra("runId", id)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(command) else startService(command)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("runId", runId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
