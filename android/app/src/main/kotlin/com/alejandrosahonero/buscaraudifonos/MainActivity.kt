package com.alejandrosahonero.buscaraudifonos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var classicDiscovery: ClassicDiscovery? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val discovery = ClassicDiscovery(applicationContext)
        classicDiscovery = discovery
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ClassicDiscovery.CHANNEL)
            .setStreamHandler(discovery)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        classicDiscovery?.onCancel(null)
        classicDiscovery = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
