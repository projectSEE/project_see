package com.kitahack.see

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "image_converter_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "convertYuvToJpeg" -> {
                    try {
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val yPlane = call.argument<ByteArray>("yPlane")
                        val uPlane = call.argument<ByteArray>("uPlane")
                        val vPlane = call.argument<ByteArray>("vPlane")
                        val yRowStride = call.argument<Int>("yRowStride") ?: width
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                        val quality = call.argument<Int>("quality") ?: 50
                        
                        if (yPlane == null) {
                            result.error("INVALID_DATA", "Y plane is null", null)
                            return@setMethodCallHandler
                        }
                        
                        val jpegBytes = convertYuvToJpeg(
                            width, height, 
                            yPlane, uPlane, vPlane,
                            yRowStride, uvPixelStride, quality
                        )
                        
                        result.success(jpegBytes)
                    } catch (e: Exception) {
                        result.error("CONVERSION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun convertYuvToJpeg(
        width: Int, height: Int,
        yPlane: ByteArray, uPlane: ByteArray?, vPlane: ByteArray?,
        yRowStride: Int, uvPixelStride: Int, quality: Int
    ): ByteArray {
        // Convert YUV420 to NV21 format for YuvImage
        val nv21 = ByteArray(width * height * 3 / 2)
        
        // Copy Y plane
        if (yRowStride == width) {
            System.arraycopy(yPlane, 0, nv21, 0, width * height)
        } else {
            // Handle stride
            for (row in 0 until height) {
                System.arraycopy(yPlane, row * yRowStride, nv21, row * width, width)
            }
        }
        
        // Interleave U and V planes into NV21 format (VU order)
        val uvOffset = width * height
        if (uPlane != null && vPlane != null) {
            val uvWidth = width / 2
            val uvHeight = height / 2
            
            var uvIndex = 0
            for (row in 0 until uvHeight) {
                for (col in 0 until uvWidth) {
                    val uIndex = row * (uPlane.size / uvHeight) + col * uvPixelStride
                    val vIndex = row * (vPlane.size / uvHeight) + col * uvPixelStride
                    
                    if (vIndex < vPlane.size && uIndex < uPlane.size) {
                        nv21[uvOffset + uvIndex++] = vPlane[vIndex]
                        nv21[uvOffset + uvIndex++] = uPlane[uIndex]
                    }
                }
            }
        }
        
        // Convert NV21 to JPEG
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val outputStream = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, outputStream)
        
        return outputStream.toByteArray()
    }
}
