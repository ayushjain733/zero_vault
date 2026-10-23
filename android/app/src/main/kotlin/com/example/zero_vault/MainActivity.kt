package com.example.zero_vault // KEEP YOUR ORIGINAL PACKAGE NAME HERE

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blocks screenshots, screen recording, and Recent Apps previews
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}