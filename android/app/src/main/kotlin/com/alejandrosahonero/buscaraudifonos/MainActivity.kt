package com.alejandrosahonero.buscaraudifonos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var classicDiscovery: ClassicDiscovery? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val discovery = ClassicDiscovery(applicationContext)
        classicDiscovery = discovery
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ClassicDiscovery.CHANNEL)
            .setStreamHandler(discovery)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LocationServices.CHANNEL)
            .setMethodCallHandler(LocationServices(applicationContext))
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        classicDiscovery?.onCancel(null)
        classicDiscovery = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
