package com.alejandrosahonero.buscaraudifonos

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Bluetooth classic (BR/EDR) discovery, streamed to Dart while it is listened to.
 *
 * flutter_blue_plus only scans Low Energy, so a headset that speaks classic
 * Bluetooth alone never shows up there. Android's own inquiry finds it and
 * reports an RSSI with each sighting — but one inquiry lasts ~12 s and a
 * device answers at most once per inquiry, which is why Dart labels these
 * devices "slow signal".
 *
 * Listening starts an endless loop of inquiries; cancelling stops it. Each
 * event is a map: id, name, rssi, deviceClass, type.
 */
class ClassicDiscovery(private val context: Context) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var registered = false

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> onFound(intent)
                // An inquiry ends on its own after ~12 s. Keep the loop going for as
                // long as Dart is listening: the radar needs a reading every cycle.
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> if (sink != null) startInquiry()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (!registered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            // These broadcasts come from the Bluetooth stack's own process, so the
            // receiver has to be exported or Android 14+ drops them silently.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                context.registerReceiver(receiver, filter)
            }
            registered = true
        }
        startInquiry()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stopInquiry()
        if (registered) {
            try {
                context.unregisterReceiver(receiver)
            } catch (alreadyGone: IllegalArgumentException) {
                // Already unregistered.
            }
            registered = false
        }
    }

    // Permissions (BLUETOOTH_SCAN, or location below Android 12) are requested by
    // the Dart side before any scan starts. A SecurityException here means they
    // were revoked meanwhile: report it and let the BLE half carry on.
    @SuppressLint("MissingPermission")
    private fun startInquiry() {
        try {
            val adapter = adapter ?: return
            if (!adapter.isEnabled || adapter.isDiscovering) return
            adapter.startDiscovery()
        } catch (error: SecurityException) {
            sink?.error("permission", error.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopInquiry() {
        try {
            adapter?.cancelDiscovery()
        } catch (notAllowed: SecurityException) {
            // Nothing running that we could stop.
        }
    }

    @SuppressLint("MissingPermission")
    private fun onFound(intent: Intent) {
        val device: BluetoothDevice = (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
            }
        ) ?: return

        val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
        if (rssi == Short.MIN_VALUE) return

        // Name and type need BLUETOOTH_CONNECT on Android 12+. Without it the
        // device is still worth listing: Dart labels it from its class.
        val name: String = intent.getStringExtra(BluetoothDevice.EXTRA_NAME)
            ?: readName(device)
            ?: ""
        val type: Int = readType(device)
        val bluetoothClass: BluetoothClass? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_CLASS, BluetoothClass::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<BluetoothClass>(BluetoothDevice.EXTRA_CLASS)
            }

        sink?.success(
            mapOf(
                "id" to device.address,
                "name" to name,
                "rssi" to rssi.toInt(),
                "deviceClass" to (bluetoothClass?.deviceClass ?: 0),
                "type" to type,
            ),
        )
    }

    @SuppressLint("MissingPermission")
    private fun readName(device: BluetoothDevice): String? =
        try {
            device.name
        } catch (notAllowed: SecurityException) {
            null
        }

    @SuppressLint("MissingPermission")
    private fun readType(device: BluetoothDevice): Int =
        try {
            device.type
        } catch (notAllowed: SecurityException) {
            -1
        }

    companion object {
        const val CHANNEL = "buscaraudifonos/classic_discovery"
    }
}
