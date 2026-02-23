package com.kitahack.see

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val IMAGE_CHANNEL = "image_converter_channel"
    private val AUDIO_CHANNEL = "audio_output_channel"
    private val TAG = "SEE_AEC"

    // Native AudioTrack for VOICE_COMMUNICATION playback (enables AEC)
    private var audioTrack: AudioTrack? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Image converter channel (existing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMAGE_CHANNEL).setMethodCallHandler { call, result ->
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

        // ★ Audio output channel — uses VOICE_COMMUNICATION for proper AEC
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    try {
                        initAudioTrack()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "init error: ${e.message}")
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                "feed" -> {
                    try {
                        val pcmData = call.argument<ByteArray>("pcmData")
                        if (pcmData != null && audioTrack != null) {
                            audioTrack!!.write(pcmData, 0, pcmData.size)
                            result.success(pcmData.size)
                        } else {
                            result.success(0)
                        }
                    } catch (e: Exception) {
                        result.error("FEED_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        stopAudioTrack()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                "flush" -> {
                    // Hard barge-in: flush audio buffer immediately
                    try {
                        audioTrack?.pause()
                        audioTrack?.flush()
                        audioTrack?.play()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FLUSH_ERROR", e.message, null)
                    }
                }
                "setSpeakerOn" -> {
                    try {
                        val on = call.argument<Boolean>("on") ?: true
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.isSpeakerphoneOn = on
                        Log.d(TAG, "Speakerphone: $on")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SPEAKER_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initAudioTrack() {
        // Release existing track if any
        stopAudioTrack()

        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // ★ KEY: Set mode to IN_COMMUNICATION — this enables AEC globally
        am.mode = AudioManager.MODE_IN_COMMUNICATION

        Log.d(TAG, "AudioManager: MODE_IN_COMMUNICATION")

        val sampleRate = 24000 // Gemini outputs 24kHz
        val channelConfig = AudioFormat.CHANNEL_OUT_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat) * 2

        // ★ KEY: Use USAGE_VOICE_COMMUNICATION — this tells Android's AEC
        // which audio stream to subtract from the mic input
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setChannelMask(channelConfig)
            .setEncoding(audioFormat)
            .build()

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        val sessionId = audioTrack!!.audioSessionId
        Log.d(TAG, "AudioTrack created: session=$sessionId, buffer=$bufferSize")

        // ★ Attach AEC to this audio session
        if (AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(sessionId)
            aec?.enabled = true
            Log.d(TAG, "AEC enabled: ${aec?.enabled}")
        } else {
            Log.w(TAG, "AEC not available on this device")
        }

        // Attach noise suppressor too
        if (NoiseSuppressor.isAvailable()) {
            ns = NoiseSuppressor.create(sessionId)
            ns?.enabled = true
            Log.d(TAG, "NoiseSuppressor enabled: ${ns?.enabled}")
        }

        audioTrack!!.play()

        // ★ Force audio to LOUDSPEAKER (not earpiece)
        // MODE_IN_COMMUNICATION defaults to earpiece — must explicitly route to speaker
        forceToLoudSpeaker(am)

        // Maximize voice call volume for blind users
        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
        am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol, 0)
        Log.d(TAG, "AudioTrack playing — volume=$maxVol")
    }

    /// Force audio routing to the built-in loudspeaker
    private fun forceToLoudSpeaker(am: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // ★ Android 12+ (API 31): Use modern setCommunicationDevice API
            // Find the built-in speaker device
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val speaker = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            if (speaker != null) {
                val success = am.setCommunicationDevice(speaker)
                Log.d(TAG, "setCommunicationDevice(BUILTIN_SPEAKER): $success")
            } else {
                Log.w(TAG, "No BUILTIN_SPEAKER found! Falling back to setSpeakerphoneOn")
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = true
            }
        } else {
            // Legacy: Android 11 and below
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = true
            Log.d(TAG, "Legacy: setSpeakerphoneOn=true")
        }
    }

    private fun stopAudioTrack() {
        try {
            audioTrack?.stop()
            audioTrack?.release()
            audioTrack = null
            aec?.release()
            aec = null
            ns?.release()
            ns = null

            // Restore normal audio mode and clear device routing
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = false
            }
            am.mode = AudioManager.MODE_NORMAL
            Log.d(TAG, "AudioTrack released, mode restored to NORMAL")
        } catch (e: Exception) {
            Log.e(TAG, "stopAudioTrack error: ${e.message}")
        }
    }

    override fun onDestroy() {
        stopAudioTrack()
        super.onDestroy()
    }
    
    private fun convertYuvToJpeg(
        width: Int, height: Int,
        yPlane: ByteArray, uPlane: ByteArray?, vPlane: ByteArray?,
        yRowStride: Int, uvPixelStride: Int, quality: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        
        // Copy Y plane
        if (yRowStride == width) {
            System.arraycopy(yPlane, 0, nv21, 0, width * height)
        } else {
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
        
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val outputStream = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, outputStream)
        
        return outputStream.toByteArray()
    }
}
