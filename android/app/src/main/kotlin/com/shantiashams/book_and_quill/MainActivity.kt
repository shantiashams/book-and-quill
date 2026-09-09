package com.shantiashams.book_and_quill

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val documentRequest = 7401
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContents: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "book_and_quill/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDataDirectory" -> result.success(filesDir.absolutePath)
                    "exportBook", "importBook" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "A document picker is already open.", null)
                            return@setMethodCallHandler
                        }
                        val exporting = call.method == "exportBook"
                        val contents = call.argument<String>("contents")
                        if (exporting && contents == null) {
                            result.error("INVALID_DOCUMENT", "The book has no contents.", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        pendingContents = if (exporting) contents else null
                        val intent = Intent(if (exporting) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (exporting) "application/octet-stream" else "*/*")
                        if (exporting) intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename") ?: "Book.qbook")
                        try {
                            startActivityForResult(intent, documentRequest)
                        } catch (error: Exception) {
                            pendingResult = null
                            pendingContents = null
                            result.error("DOCUMENT_PICKER", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Used by the Flutter activity document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != documentRequest) return
        val result = pendingResult ?: return
        val contents = pendingContents
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingResult = null
            pendingContents = null
            result.success(if (contents == null) null else false)
            return
        }
        // Keep the pending request until I/O completes. Remote document
        // providers can block, so never read/write them on the platform thread.
        ioExecutor.execute {
            try {
                val response: Any = if (contents != null) {
                    val stream = contentResolver.openOutputStream(uri, "wt")
                        ?: throw IllegalStateException("Cannot write the selected document.")
                    stream.bufferedWriter(Charsets.UTF_8).use { it.write(contents) }
                    true
                } else {
                    val stream = contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("Cannot read the selected document.")
                    stream.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size().toLong() + count > 32L * 1024 * 1024) {
                                throw IllegalArgumentException("This book exceeds the 32 MB import limit.")
                            }
                            output.write(buffer, 0, count)
                        }
                        output.toString("UTF-8")
                    }
                }
                completeDocument(result) { result.success(response) }
            } catch (error: Exception) {
                completeDocument(result) { result.error("DOCUMENT_IO", error.message, null) }
            }
        }
    }

    private fun completeDocument(result: MethodChannel.Result, complete: () -> Unit) {
        runOnUiThread {
            if (pendingResult === result) {
                pendingResult = null
                pendingContents = null
                complete()
            }
        }
    }

    override fun onDestroy() {
        pendingResult?.error("ACTIVITY_CLOSED", "The document picker was closed.", null)
        pendingResult = null
        pendingContents = null
        ioExecutor.shutdown()
        super.onDestroy()
    }
}
