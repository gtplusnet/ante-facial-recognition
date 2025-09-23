package com.ante.facial_recognition

import android.os.Bundle
import androidx.annotation.NonNull
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity(), LifecycleOwner {
    companion object {
        private const val CAMERAX_CHANNEL = "com.ante.facial_recognition/camerax"
    }

    private lateinit var cameraXHandler: CameraXHandler
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Initialize CameraX handler
        cameraXHandler = CameraXHandler(
            context = this,
            textureRegistry = flutterEngine.renderer,
            lifecycleOwner = this
        )

        // Set up method channel for CameraX
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERAX_CHANNEL)
        methodChannel.setMethodCallHandler(cameraXHandler)

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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
