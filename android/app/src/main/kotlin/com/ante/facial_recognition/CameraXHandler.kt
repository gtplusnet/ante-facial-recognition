package com.ante.facial_recognition

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.util.Size
import android.view.Surface
import androidx.annotation.NonNull
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class CameraXHandler(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val lifecycleOwner: LifecycleOwner
) : MethodCallHandler {

    companion object {
        private const val RATIO_4_3_VALUE = 4.0 / 3.0
        private const val RATIO_16_9_VALUE = 16.0 / 9.0
        private const val TARGET_RESOLUTION_WIDTH = 1920
        private const val TARGET_RESOLUTION_HEIGHT = 1080
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: androidx.camera.core.Camera? = null
    private var preview: Preview? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var imageCallback: ((ByteArray, Int, Int) -> Unit)? = null
    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var isProcessingFrame = false

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initializeCamera" -> initializeCamera(result)
            "startImageStream" -> startImageStream(result)
            "stopImageStream" -> stopImageStream(result)
            "switchCamera" -> switchCamera(result)
            "setFlashMode" -> setFlashMode(call, result)
            "dispose" -> dispose(result)
            "checkCameraPermission" -> checkCameraPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun checkCameraPermission(result: Result) {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        result.success(hasPermission)
    }

    private fun initializeCamera(result: Result) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

                // Create texture for camera preview
                textureEntry = textureRegistry.createSurfaceTexture()
                val textureId = textureEntry!!.id()

                bindCameraUseCases()

                val response = mapOf(
                    "textureId" to textureId,
                    "previewWidth" to TARGET_RESOLUTION_WIDTH,
                    "previewHeight" to TARGET_RESOLUTION_HEIGHT
                )
                result.success(response)
            } catch (e: Exception) {
                result.error("CAMERA_ERROR", "Failed to initialize camera: ${e.message}", null)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: return

        // Set up camera selector
        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(lensFacing)
            .build()

        // Set up preview use case
        preview = Preview.Builder()
            .setTargetResolution(Size(TARGET_RESOLUTION_WIDTH, TARGET_RESOLUTION_HEIGHT))
            .build()
            .also {
                textureEntry?.surfaceTexture()?.let { surfaceTexture ->
                    val surface = Surface(surfaceTexture)
                    it.setSurfaceProvider { request ->
                        request.provideSurface(surface, cameraExecutor) { }
                    }
                }
            }

        // Set up image analysis for face detection
        imageAnalyzer = ImageAnalysis.Builder()
            .setTargetResolution(Size(TARGET_RESOLUTION_WIDTH, TARGET_RESOLUTION_HEIGHT))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        // Unbind all use cases before rebinding
        cameraProvider.unbindAll()

        // Bind use cases to camera
        camera = cameraProvider.bindToLifecycle(
            lifecycleOwner,
            cameraSelector,
            preview,
            imageAnalyzer
        )
    }

    private fun startImageStream(result: Result) {
        imageAnalyzer?.setAnalyzer(cameraExecutor, ImageAnalysis.Analyzer { imageProxy ->
            if (!isProcessingFrame) {
                isProcessingFrame = true
                processImage(imageProxy)
            } else {
                imageProxy.close()
            }
        })
        result.success(null)
    }

    private fun processImage(imageProxy: ImageProxy) {
        try {
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees

            // Convert YUV to NV21 byte array for compatibility with Flutter
            val nv21 = yuv420ToNv21(imageProxy)

            // Send frame data to Flutter
            imageCallback?.invoke(nv21, imageProxy.width, imageProxy.height)

        } finally {
            imageProxy.close()
            isProcessingFrame = false
        }
    }

    private fun yuv420ToNv21(imageProxy: ImageProxy): ByteArray {
        val planes = imageProxy.planes
        val ySize = planes[0].buffer.remaining()
        val uSize = planes[1].buffer.remaining()
        val vSize = planes[2].buffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)

        // Copy Y plane
        planes[0].buffer.get(nv21, 0, ySize)

        val pixelStride = planes[2].pixelStride

        if (pixelStride == 1) {
            // UV planes are already interleaved
            planes[1].buffer.get(nv21, ySize, uSize)
            planes[2].buffer.get(nv21, ySize + uSize, vSize)
        } else {
            // Need to interleave U and V
            var pos = ySize
            val uvBuffer1 = planes[1].buffer
            val uvBuffer2 = planes[2].buffer

            for (i in 0 until min(uSize, vSize)) {
                nv21[pos] = uvBuffer2.get(i) // V
                nv21[pos + 1] = uvBuffer1.get(i) // U
                pos += 2
            }
        }

        return nv21
    }

    private fun stopImageStream(result: Result) {
        imageAnalyzer?.clearAnalyzer()
        isProcessingFrame = false
        result.success(null)
    }

    private fun switchCamera(result: Result) {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
            CameraSelector.LENS_FACING_BACK
        } else {
            CameraSelector.LENS_FACING_FRONT
        }

        bindCameraUseCases()
        result.success(null)
    }

    private fun setFlashMode(call: MethodCall, result: Result) {
        val flashMode = call.argument<String>("mode")

        when (flashMode) {
            "on" -> camera?.cameraControl?.enableTorch(true)
            "off" -> camera?.cameraControl?.enableTorch(false)
            "auto" -> {
                // Auto mode implementation would require exposure state monitoring
                camera?.cameraControl?.enableTorch(false)
            }
        }

        result.success(null)
    }

    fun setImageCallback(callback: (ByteArray, Int, Int) -> Unit) {
        imageCallback = callback
    }

    private fun dispose(result: Result) {
        try {
            imageAnalyzer?.clearAnalyzer()
            cameraProvider?.unbindAll()
            textureEntry?.release()
            cameraExecutor.shutdown()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", "Failed to dispose camera: ${e.message}", null)
        }
    }

    fun aspectRatio(width: Int, height: Int): Int {
        val previewRatio = max(width, height).toDouble() / min(width, height)
        if (abs(previewRatio - RATIO_4_3_VALUE) <= abs(previewRatio - RATIO_16_9_VALUE)) {
            return AspectRatio.RATIO_4_3
        }
        return AspectRatio.RATIO_16_9
    }
}