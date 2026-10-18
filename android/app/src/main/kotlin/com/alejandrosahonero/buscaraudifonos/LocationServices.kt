package com.alejandrosahonero.buscaraudifonos

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's location toggle, as far as Bluetooth scanning cares about it.
 *
 * Up to Android 11 the system delivers no BLE scan results while location is
 * off — the scan starts fine and simply never finds anything. Android 12+ scans
 * with BLUETOOTH_SCAN (neverForLocation) and does not care.
 */
class LocationServices(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isRequiredForScan" -> result.success(Build.VERSION.SDK_INT <= Build.VERSION_CODES.R)
            "isEnabled" -> {
                val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                result.success(manager != null && isEnabled(manager))
            }
            "openSettings" -> {
                val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(
                    runCatching { context.startActivity(intent) }.isSuccess,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun isEnabled(manager: LocationManager): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }

    companion object {
        const val CHANNEL = "buscaraudifonos/location_services"
    }
}
