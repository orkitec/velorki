package com.orkitec.velorki

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * Adds the `velorki/files` channel to the standard Flutter activity.
 *
 * Android hands an "open with" intent over as a `content://` URI. `app_links`
 * reports the URI but cannot read it: only a process holding the intent's
 * temporary read grant can, and that is this activity. `openInputStream`
 * therefore reads the URI through the `ContentResolver` and returns the bytes
 * to Dart, which sniffs and decodes them.
 *
 * The channel name and method names are mirrored in
 * `lib/features/import_export/data/incoming_file_service.dart`.
 *
 * `FlutterFragmentActivity` rather than `FlutterActivity` because Health
 * Connect asks for its permissions through `registerForActivityResult`, which
 * needs a `ComponentActivity`; see the `health` package README, "Android 14".
 * Nothing else in the app cares which of the two it is.
 */
class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL = "velorki/files"
        const val METHOD_OPEN_INPUT_STREAM = "openInputStream"

        /** Refuse anything larger than this; a GPX of 32 MB is not a bike route. */
        const val MAX_BYTES = 32 * 1024 * 1024
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_OPEN_INPUT_STREAM -> openInputStream(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openInputStream(arguments: Any?, result: MethodChannel.Result) {
        val uriString = arguments as? String
        if (uriString.isNullOrEmpty()) {
            result.error("invalid_argument", "expected a URI string", null)
            return
        }
        try {
            val uri = android.net.Uri.parse(uriString)
            val bytes = contentResolver.openInputStream(uri).use { stream ->
                if (stream == null) {
                    result.error("unreadable", "no stream for $uriString", null)
                    return
                }
                stream.readBytes(MAX_BYTES)
            }
            result.success(bytes)
        } catch (e: SecurityException) {
            // The read grant that came with the intent has already expired.
            result.error("denied", e.message, null)
        } catch (e: IOException) {
            result.error("unreadable", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("invalid_argument", e.message, null)
        }
    }

    /** Reads at most [limit] bytes, so a huge file cannot exhaust the heap. */
    private fun java.io.InputStream.readBytes(limit: Int): ByteArray {
        val buffer = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(64 * 1024)
        while (true) {
            val read = read(chunk)
            if (read < 0) break
            if (buffer.size() + read > limit) {
                throw IOException("file is larger than $limit bytes")
            }
            buffer.write(chunk, 0, read)
        }
        return buffer.toByteArray()
    }
}
