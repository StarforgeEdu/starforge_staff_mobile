package com.starforge.staff

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val privacyChannel = "com.starforge.staff/privacy"
    private var protectsContent = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyContentProtection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "setProtected") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                protectsContent = call.argument<Boolean>("enabled") ?: false
                applyContentProtection()
                result.success(null)
            }
    }

    override fun onPause() {
        // Keep staff information out of the recent-apps snapshot. Active
        // screenshots remain available unless the current content is protected.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        applyContentProtection()
    }

    private fun applyContentProtection() {
        if (protectsContent) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
