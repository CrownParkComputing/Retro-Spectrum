package com.crownpark.retro_spectrum

import android.content.Intent
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

/**
 * Flutter host activity for retro_spectrum.
 *
 * Implements the [GamepadsCompatibleActivity] interface that the
 * `gamepads_android` plugin requires so it can wire raw Android
 * KeyEvent/MotionEvent streams into the Dart-side `Gamepads.normalizedEvents`
 * stream consumed by [GamepadService].
 *
 * File access: SAF only. The user picks a parent folder once via
 * ACTION_OPEN_DOCUMENT_TREE (the file_picker package's
 * getDirectoryPath does this on Android), Android grants a
 * persistable URI permission for that tree, and the bridge channels
 * here expose it back to Dart for recursive walks and file reads.
 * No MANAGE_EXTERNAL_STORAGE, no broad legacy permission.
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {

    /* SAF tree handle, set by Dart after a successful folder pick.
     * Used by [walkSafTree] and [readSafFile] below. */
    private var safTreeUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        /* Storage Access Framework bridge. Two methods:
         *
         *   setSafTree(uriString) -> null
         *     Tell the host which tree the user picked. Android already
         *     holds the persistable permission; we just record the URI
         *     so the walk/read methods can use it.
         *
         *   walkSafTree() -> [{name, uri, isDirectory, size, mime}]
         *     Recursive walk of the tree. Returns a list of plain maps.
         *
         *   readSafFile(uriString) -> Uint8List
         *     Read a single file from the tree.
         */
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAF_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSafTree" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("bad_args", "uri required", null)
                    } else {
                        safTreeUri = Uri.parse(uriString)
                        result.success(null)
                    }
                }
                "walkSafTree" -> {
                    val tree = safTreeUri
                    if (tree == null) {
                        result.error("no_tree", "setSafTree first", null)
                    } else {
                        try {
                            result.success(walkSafTree(tree))
                        } catch (t: Throwable) {
                            result.error("saf_failed", t.message ?: "walk failed", null)
                        }
                    }
                }
                "readSafFile" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("bad_args", "uri required", null)
                    } else {
                        try {
                            val bytes = contentResolver.openInputStream(Uri.parse(uriString))
                                ?.use { it.readBytes() }
                            if (bytes == null) {
                                result.error("open_failed", "could not open file", null)
                            } else {
                                result.success(bytes)
                            }
                        } catch (t: Throwable) {
                            result.error("read_failed", t.message ?: "read failed", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Recursive DFS over the SAF tree, returning plain maps the Dart
     *  side can decode into a strongly-typed model. We cap depth and
     *  breadth to keep startup responsive when the user points us at
     *  a deep tree (e.g. /sdcard/Download/ with thousands of files). */
    private fun walkSafTree(root: Uri): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()
        val stack = ArrayDeque<Uri>()
        stack.addLast(root)
        var depth = 0
        val MAX_DEPTH = 6
        val MAX_ENTRIES = 5000
        while (stack.isNotEmpty() && out.size < MAX_ENTRIES && depth < MAX_DEPTH) {
            val dir = stack.removeLast()
            val children = queryChildren(dir)
            for (c in children) {
                if (out.size >= MAX_ENTRIES) break
                val id = c.uri.toString()
                if (!seen.add(id)) continue
                out.add(
                    mapOf(
                        "name" to c.name,
                        "uri" to id,
                        "isDirectory" to c.isDirectory,
                        "size" to c.size,
                        "mime" to c.mime,
                    ),
                )
                if (c.isDirectory) {
                    stack.addLast(c.uri)
                }
            }
            depth++
        }
        return out
    }

    private data class SafChild(
        val uri: Uri,
        val name: String,
        val isDirectory: Boolean,
        val size: Long,
        val mime: String,
    )

    private fun queryChildren(parent: Uri): List<SafChild> {
        val children = ArrayList<SafChild>()
        // The column names are stable but older SDKs don't expose them
        // as Document.COLUMN_DOCUMENT_URI constants; use the strings
        // directly so we build against a wide range of API levels.
        val projection = arrayOf(
            "document_id",
            "_display_name",
            "mime_type",
            "_size",
        )
        val sortOrder = "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} ASC"
        val resolver = contentResolver
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent, null,
        )
        resolver.query(
            childrenUri, projection, null, null, sortOrder,
        )?.use { c ->
            val iName = c.getColumnIndex("_display_name")
            val iUri = c.getColumnIndex("document_id")
            val iMime = c.getColumnIndex("mime_type")
            val iSize = c.getColumnIndex("_size")
            while (c.moveToNext()) {
                val uri = c.getString(iUri) ?: continue
                val name = c.getString(iName) ?: continue
                val mime = c.getString(iMime) ?: ""
                val size = if (c.isNull(iSize)) 0L else c.getLong(iSize)
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                children.add(SafChild(Uri.parse(uri), name, isDir, size, mime))
            }
        }
        return children
    }

    /* Keyboard / motion handler boilerplate for the gamepads plugin.
     * Unchanged from the original Retro-Amiga implementation. */
    private var keyHandler: ((KeyEvent) -> Boolean)? = null
    private var motionHandler: ((MotionEvent) -> Boolean)? = null

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?
    ) {
        getSystemService(InputManager::class.java)
            .registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyHandler = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionHandler = handler
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val handled = keyHandler?.invoke(event) ?: false
        return handled || super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val handled = motionHandler?.invoke(event) ?: false
        return handled || super.dispatchGenericMotionEvent(event)
    }

    companion object {
        private const val SAF_CHANNEL = "retro_spectrum/saf"
    }
}
