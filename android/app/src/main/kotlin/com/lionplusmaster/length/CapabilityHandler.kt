// 디바이스 측정 캐퍼빌리티(AR/ToF/NPU/RAM) 감지 MethodChannel 핸들러.
package com.lionplusmaster.length

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Build
import com.google.ar.core.ArCoreApk
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CapabilityHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detect" -> result.success(detect())
            else -> result.notImplemented()
        }
    }

    private fun detect(): Map<String, Any?> {
        return mapOf(
            "arSupported" to isArCoreInstalled(),
            "lidarAvailable" to false,
            "tofAvailable" to hasDepthCamera(),
            "neuralEngineAvailable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
            "osVersion" to Build.VERSION.RELEASE,
            "ramMb" to totalRamMb(),
            "cameraIntrinsics" to emptyMap<String, Any>(),
        )
    }

    private fun isArCoreInstalled(): Boolean {
        val availability = ArCoreApk.getInstance().checkAvailability(context)
        return availability.isSupported
    }

    private fun hasDepthCamera(): Boolean {
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cm.cameraIdList.any { id ->
                val ch = cm.getCameraCharacteristics(id)
                val caps = ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                caps?.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_DEPTH_OUTPUT) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun totalRamMb(): Int {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return (info.totalMem / (1024L * 1024L)).toInt()
    }
}
