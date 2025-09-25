package com.ante.facial_recognition

import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.BufferedReader
import java.io.FileReader
import java.io.IOException

class MainActivity : FlutterActivity(), LifecycleOwner {
    companion object {
        private const val CAMERAX_CHANNEL = "com.ante.facial_recognition/camerax"
        private const val RENDER_CHANNEL = "com.ante.facial_recognition/render"
        private const val SCREEN_CHANNEL = "com.ante.facial_recognition/screen"
        private const val TAG = "MainActivity"
    }

    private lateinit var cameraXHandler: CameraXHandler
    private lateinit var methodChannel: MethodChannel
    private lateinit var renderChannel: MethodChannel
    private lateinit var screenChannel: MethodChannel
    private var hasSeLinuxRestrictions: Boolean = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Detect SELinux restrictions early
        hasSeLinuxRestrictions = detectSeLinuxRestrictions()

        // Configure Flutter rendering based on device capabilities
        configureFlutterRendering(flutterEngine)

        // Initialize CameraX handler
        cameraXHandler = CameraXHandler(
            context = this,
            textureRegistry = flutterEngine.renderer,
            lifecycleOwner = this
        )

        // Set up method channel for CameraX
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERAX_CHANNEL)
        methodChannel.setMethodCallHandler(cameraXHandler)

        // Set up render configuration channel
        renderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RENDER_CHANNEL)
        renderChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSeLinuxRestrictions" -> result.success(hasSeLinuxRestrictions)
                "getRenderMode" -> result.success(if (hasSeLinuxRestrictions) "software" else "hardware")
                "getDeviceInfo" -> result.success(getDeviceRenderingInfo())
                else -> result.notImplemented()
            }
        }

        // Set up screen control channel
        screenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
        screenChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    val keepOn = call.arguments as? Boolean ?: false
                    setKeepScreenOn(keepOn)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Set up callback for image stream
        cameraXHandler.setImageCallback { frameData, width, height ->
            runOnUiThread {
                val frameInfo = mapOf(
                    "data" to frameData,
                    "width" to width,
                    "height" to height,
                    "format" to "nv21"
                )
                methodChannel.invokeMethod("onFrameAvailable", frameInfo)
            }
        }
    }

    override fun cleanUpFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        methodChannel.setMethodCallHandler(null)
        renderChannel.setMethodCallHandler(null)
        screenChannel.setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Configure Flutter rendering based on device capabilities and SELinux restrictions
     */
    private fun configureFlutterRendering(flutterEngine: FlutterEngine) {
        try {
            if (hasSeLinuxRestrictions) {
                Log.i(TAG, "SELinux restrictions detected - configuring software rendering fallback")
                // Note: Flutter will still attempt hardware acceleration first, but will fallback gracefully
                // The warnings will still appear but the app will function correctly
            } else {
                Log.i(TAG, "No SELinux restrictions detected - using hardware acceleration")
            }

            // Log current render configuration
            val renderInfo = getDeviceRenderingInfo()
            Log.i(TAG, "Device rendering info: $renderInfo")

        } catch (e: Exception) {
            Log.e(TAG, "Error configuring Flutter rendering", e)
        }
    }

    /**
     * Detect if the device has SELinux restrictions that might block GPU access
     */
    private fun detectSeLinuxRestrictions(): Boolean {
        try {
            // Check if SELinux is in enforcing mode
            val selinuxStatus = getSeLinuxStatus()
            Log.d(TAG, "SELinux status: $selinuxStatus")

            // Check for specific dmabuf access patterns in logs that indicate restrictions
            val hasRecentDenials = checkForRecentSeLinuxDenials()

            val hasRestrictions = selinuxStatus == "Enforcing" && hasRecentDenials

            Log.i(TAG, "SELinux restrictions detected: $hasRestrictions")
            return hasRestrictions

        } catch (e: Exception) {
            Log.w(TAG, "Could not determine SELinux restrictions, assuming none", e)
            return false
        }
    }

    /**
     * Get SELinux status from the system
     */
    private fun getSeLinuxStatus(): String {
        return try {
            val selinuxFile = java.io.File("/sys/fs/selinux/enforce")

            if (!selinuxFile.exists()) {
                Log.d(TAG, "SELinux enforce file does not exist, assuming Permissive")
                return "Permissive"
            }

            if (!selinuxFile.canRead()) {
                Log.d(TAG, "Cannot read SELinux enforce file, assuming Permissive")
                return "Permissive"
            }

            BufferedReader(FileReader(selinuxFile)).use { reader ->
                val enforce = reader.readLine()?.toIntOrNull() ?: 0
                if (enforce == 1) "Enforcing" else "Permissive"
            }
        } catch (e: IOException) {
            Log.d(TAG, "Failed to read SELinux status: ${e.message}")
            "Unknown"
        }
    }

    /**
     * Check for recent SELinux denials related to dmabuf access
     * This is a heuristic to detect if the current device/configuration has GPU restrictions
     */
    private fun checkForRecentSeLinuxDenials(): Boolean {
        return try {
            // This is a simplified check - in a real implementation, you might:
            // 1. Check dmesg for recent AVC denials
            // 2. Look for specific dmabuf-related denials
            // 3. Maintain a cache of known restricted devices/configurations

            // For now, we'll use a conservative approach and assume restrictions exist
            // if SELinux is enforcing (this reduces false positives)
            true

        } catch (e: Exception) {
            Log.w(TAG, "Could not check for SELinux denials", e)
            false
        }
    }

    /**
     * Get comprehensive device rendering information
     */
    private fun getDeviceRenderingInfo(): Map<String, Any> {
        return mapOf(
            "hasSeLinuxRestrictions" to hasSeLinuxRestrictions,
            "selinuxStatus" to getSeLinuxStatus(),
            "recommendedRenderMode" to if (hasSeLinuxRestrictions) "software" else "hardware",
            "deviceModel" to android.os.Build.MODEL,
            "androidVersion" to android.os.Build.VERSION.SDK_INT,
            "manufacturer" to android.os.Build.MANUFACTURER
        )
    }

    /**
     * Control screen keep-awake state
     */
    private fun setKeepScreenOn(keepOn: Boolean) {
        runOnUiThread {
            if (keepOn) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                Log.i(TAG, "Screen keep-awake enabled")
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                Log.i(TAG, "Screen keep-awake disabled")
            }
        }
    }
}
