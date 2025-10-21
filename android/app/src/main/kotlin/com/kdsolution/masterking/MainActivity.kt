//package com.kdsolution.masterking
//
//import io.flutter.embedding.android.FlutterFragmentActivity
//
//class MainActivity: FlutterFragmentActivity() {
//}

package com.kdsolution.masterking

import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge mode for Android 15 (SDK 35) and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) { // SDK 31 or higher
            WindowCompat.setDecorFitsSystemWindows(window, false)
        }
    }
}
