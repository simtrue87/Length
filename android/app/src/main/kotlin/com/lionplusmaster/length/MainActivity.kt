// Length 앱 메인 액티비티. 캐퍼빌리티·ARCore 세션 MethodChannel을 등록한다.
package com.lionplusmaster.length

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.lionplusmaster.length/capability")
            .setMethodCallHandler(CapabilityHandler(applicationContext))
        MethodChannel(messenger, "com.lionplusmaster.length/arcore")
            .setMethodCallHandler(ArcoreSessionHandler(this))
    }
}
