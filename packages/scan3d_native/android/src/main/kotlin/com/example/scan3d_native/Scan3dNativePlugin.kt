package com.example.scan3d_native

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.opengl.GLSurfaceView
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class Scan3dNativePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var appContext: Context
    private val engine = ScanEngine()
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "scan3d/control")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "scan3d/frames")
        events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory("scan3d/ar_view", ArViewFactory(engine))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        engine.close()
    }

    // ---- Activity ----
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        engine.activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        engine.activity = null
    }

    // ---- Methods ----
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkSupport" -> {
                val a = ArCoreApk.getInstance().checkAvailability(appContext)
                result.success(mapOf("status" to a.name, "supported" to (a.isSupported || a.isTransient)))
            }
            "requestPermission" -> requestCamera(result)
            "prepare" -> result.success(engine.prepare())
            "setScanning" -> {
                engine.scanning = call.arguments as? Boolean ?: false
                result.success(null)
            }
            "resumeSession" -> { engine.resume(); result.success(null) }
            "pauseSession" -> { engine.pause(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun requestCamera(result: MethodChannel.Result) {
        if (appContext.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val activity = engine.activity
        if (activity == null) {
            result.error("no_activity", "No foreground activity to request permission", null)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_CAMERA) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    // ---- Events ----
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { engine.sink = sink }
    override fun onCancel(arguments: Any?) { engine.sink = null }

    companion object {
        private const val REQUEST_CAMERA = 0x5CA3
    }
}

class ArViewFactory(private val engine: ScanEngine) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ArPlatformView(context, engine)
}

class ArPlatformView(context: Context, private val engine: ScanEngine) : PlatformView {
    private val glView = GLSurfaceView(context).apply {
        preserveEGLContextOnPause = true
        setEGLContextClientVersion(2)
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        setRenderer(engine.renderer)
        renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
    }

    init {
        engine.attachView(glView)
    }

    override fun getView() = glView

    override fun dispose() {
        engine.detachView(glView)
    }
}
