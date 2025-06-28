package org.revengi.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val myChannel = "flutter.native/helper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            myChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val deviceInfo: HashMap<String, String> = getDeviceInfo()
                    if (deviceInfo.isNotEmpty()) {
                        result.success(deviceInfo)
                    } else {
                        result.error("UNAVAILABLE", "Device info not available.", null)
                    }
                }
                "getTotalRAM" -> {
                    val totalRAM = getTotalRAM(this)
                    result.success(totalRAM)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getDeviceInfo(): HashMap<String, String> {
        val deviceInfo = HashMap<String, String>()
        deviceInfo["version"] = System.getProperty("os.version")!!.toString()
        deviceInfo["device"] = Build.DEVICE
        deviceInfo["model"] = Build.MODEL
        deviceInfo["product"] = Build.PRODUCT
        deviceInfo["manufacturer"] = Build.MANUFACTURER
        deviceInfo["sdkVersion"] = Build.VERSION.SDK_INT.toString()
        deviceInfo["id"] = Build.ID
        return deviceInfo
    }

    private fun getTotalRAM(context: Context): Long {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem
    }
}
