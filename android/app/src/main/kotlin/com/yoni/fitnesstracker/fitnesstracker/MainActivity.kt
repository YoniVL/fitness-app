package com.yoni.fitnesstracker.fitnesstracker

import com.yoni.fitnesstracker.fitnesstracker.wear.WearBridgePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(WearBridgePlugin())
    }
}
