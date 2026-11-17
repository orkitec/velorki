package com.orkitec.velorki.wear

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember

/**
 * The watch app: one screen over the one session. The only prompt it raises
 * is the heart rate permission, when a workout first wants the sensor, which
 * is after the rider switched the watch on in the phone's settings and
 * opened this app or started a ride.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val session = Wear.session(this)
        setContent {
            val state by session.state.collectAsState()
            val asked = remember { mutableStateOf(false) }
            val permissions = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestMultiplePermissions(),
            ) { granted ->
                if (granted[heartRatePermission] == true) session.accessGranted()
            }
            LaunchedEffect(state.problem) {
                if (state.problem == Problem.HealthAccess && !asked.value) {
                    asked.value = true
                    permissions.launch(
                        buildList {
                            add(heartRatePermission)
                            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
                        }.toTypedArray(),
                    )
                }
            }
            RideScreen(state, session)
        }
    }

    override fun onResume() {
        super.onResume()
        // In front, Android lets the ride's foreground service start, which
        // it may have refused while the app was in the background.
        val state = Wear.session(this).state.value
        if (state.riding || state.measuring) RideService.start(this)
    }
}
