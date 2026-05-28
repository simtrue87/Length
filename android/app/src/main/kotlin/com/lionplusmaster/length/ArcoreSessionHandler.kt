// ARCore Session 라이크사이클(가용성 확인·설치 요청·생성·종료) MethodChannel 핸들러.
package com.lionplusmaster.length

import android.app.Activity
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Session
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ArcoreSessionHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var session: Session? = null
    private var userRequestedInstall = true

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> result.success(checkAvailability())
            "requestInstall" -> requestInstall(result)
            "createSession" -> createSession(result)
            "releaseSession" -> {
                releaseSession()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkAvailability(): String {
        return ArCoreApk.getInstance().checkAvailability(activity).name
    }

    private fun requestInstall(result: MethodChannel.Result) {
        try {
            val status = ArCoreApk.getInstance()
                .requestInstall(activity, userRequestedInstall)
            userRequestedInstall = false
            result.success(status.name)
        } catch (e: UnavailableException) {
            result.error("UNAVAILABLE", e.message, null)
        }
    }

    private fun createSession(result: MethodChannel.Result) {
        try {
            if (session == null) {
                session = Session(activity)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("SESSION_CREATE_FAILED", e.message, null)
        }
    }

    private fun releaseSession() {
        session?.close()
        session = null
    }
}
