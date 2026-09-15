package com.example.workfromphone

import com.example.workfromphone.container.ContainerPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContainerPlugin.register(flutterEngine, applicationContext)
    }
}
