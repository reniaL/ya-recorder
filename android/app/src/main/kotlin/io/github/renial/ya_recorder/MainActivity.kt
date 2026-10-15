package io.github.renial.ya_recorder

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	private var recordingPlatformBridge: RecordingPlatformBridge? = null
	private var backupPlatformBridge: BackupPlatformBridge? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		recordingPlatformBridge = RecordingPlatformBridge(
			this,
			flutterEngine.dartExecutor.binaryMessenger,
		)
		backupPlatformBridge = BackupPlatformBridge(this, flutterEngine.dartExecutor.binaryMessenger)
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (backupPlatformBridge?.onActivityResult(requestCode, resultCode, data) == true) return
		super.onActivityResult(requestCode, resultCode, data)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		intent.getStringExtra("backupTaskId")?.let { backupPlatformBridge?.openTask(it) }
	}

	override fun onRequestPermissionsResult(
		requestCode: Int,
		permissions: Array<out String>,
		grantResults: IntArray,
	) {
		if (recordingPlatformBridge?.onRequestPermissionsResult(
				requestCode,
				permissions,
				grantResults,
			) == true
		) {
			return
		}
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
	}

	override fun onDestroy() {
		backupPlatformBridge?.dispose()
		backupPlatformBridge = null
		recordingPlatformBridge?.dispose()
		recordingPlatformBridge = null
		super.onDestroy()
	}
}
