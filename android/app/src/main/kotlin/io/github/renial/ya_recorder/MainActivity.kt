package io.github.renial.ya_recorder

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	private var recordingPlatformBridge: RecordingPlatformBridge? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		recordingPlatformBridge = RecordingPlatformBridge(
			this,
			flutterEngine.dartExecutor.binaryMessenger,
		)
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
		recordingPlatformBridge?.dispose()
		recordingPlatformBridge = null
		super.onDestroy()
	}
}
