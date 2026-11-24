package com.example.scan3d_native

import android.app.Activity
import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.plugin.common.EventChannel
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * Owns the ARCore session. The GL thread renders the camera feed and, while
 * scanning, unprojects the ARCore depth map (or feature points on devices
 * without depth) into world-space points that are streamed to Flutter.
 */
class ScanEngine {
    var activity: Activity? = null
    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile var scanning = false

    private var session: Session? = null
    private var installRequested = false
    private var depthMode = false
    @Volatile private var resumed = false
    private var glView: GLSurfaceView? = null
    private val main = Handler(Looper.getMainLooper())

    val renderer = Renderer()

    private fun mode() = if (depthMode) "depth" else "features"
    private fun fail(msg: String) = mapOf("ok" to false, "message" to msg)

    fun prepare(): Map<String, Any?> {
        if (session != null) return mapOf("ok" to true, "mode" to mode())
        val act = activity ?: return fail("No foreground activity.")
        return try {
            if (ArCoreApk.getInstance().requestInstall(act, !installRequested) ==
                ArCoreApk.InstallStatus.INSTALL_REQUESTED
            ) {
                installRequested = true
                return fail("Install or update “Google Play Services for AR”, then tap Try again.")
            }
            val s = Session(act)
            val cfg = Config(s)
            depthMode = s.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            cfg.depthMode = if (depthMode) Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
            cfg.focusMode = Config.FocusMode.AUTO
            cfg.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            cfg.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            s.configure(cfg)
            session = s
            mapOf("ok" to true, "mode" to mode())
        } catch (e: UnavailableUserDeclinedInstallationException) {
            fail("ARCore installation was declined.")
        } catch (e: UnavailableDeviceNotCompatibleException) {
            fail("This device does not support ARCore.")
        } catch (e: Exception) {
            fail("Could not start ARCore: ${e.message}")
        }
    }

    fun attachView(view: GLSurfaceView) {
        glView = view
        resumed = false
        resume()
    }

    fun detachView(view: GLSurfaceView) {
        if (glView === view) {
            pause()
            glView = null
        }
    }

    fun resume() {
        val s = session ?: return
        if (resumed || glView == null) return
        try {
            s.resume()
            resumed = true
            glView?.onResume()
        } catch (e: CameraNotAvailableException) {
            main.post { sink?.error("camera", "Camera not available", null) }
        }
    }

    fun pause() {
        if (!resumed) return
        resumed = false
        glView?.onPause() // blocks until the GL thread stops calling update()
        session?.pause()
    }

    fun close() {
        pause()
        session?.close()
        session = null
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int {
        val wm = activity?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        return wm?.defaultDisplay?.rotation ?: 0
    }

    inner class Renderer : GLSurfaceView.Renderer {
        private val background = BackgroundRenderer()
        private var textureBoundTo: Session? = null
        private var viewW = 0
        private var viewH = 0
        private var geometryDirty = true
        private var lastEmit = 0L

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            background.createOnGlThread()
            textureBoundTo = null
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            viewW = width
            viewH = height
            geometryDirty = true
        }

        override fun onDrawFrame(gl: GL10?) {
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
            if (!resumed) return
            val s = session ?: return
            if (textureBoundTo !== s) {
                s.setCameraTextureName(background.textureId)
                textureBoundTo = s
                geometryDirty = true
            }
            if (geometryDirty && viewW > 0) {
                s.setDisplayGeometry(displayRotation(), viewW, viewH)
                geometryDirty = false
            }
            val frame = try { s.update() } catch (e: Throwable) { return }
            background.draw(frame)

            val now = SystemClock.uptimeMillis()
            if (now - lastEmit < EMIT_INTERVAL_MS) return
            lastEmit = now
            emit(frame)
        }

        private fun emit(frame: Frame) {
            val cam = frame.camera
            val payload = HashMap<String, Any>()
            payload["tracking"] = trackingName(cam)
            if (cam.trackingState == TrackingState.TRACKING) {
                val pose = cam.pose
                val z = pose.zAxis
                payload["camera"] = listOf(pose.tx().toDouble(), pose.ty().toDouble(), pose.tz().toDouble())
                payload["forward"] = listOf(-z[0].toDouble(), -z[1].toDouble(), -z[2].toDouble())
                if (scanning) {
                    val pts = if (depthMode) depthPoints(frame, cam) else featurePoints(frame)
                    if (pts != null && pts.isNotEmpty()) {
                        payload["points"] = pts
                        payload["source"] = mode()
                    }
                }
            }
            main.post { sink?.success(payload) }
        }

        /** Unprojects the ARCore depth image into world-space points. */
        private fun depthPoints(frame: Frame, cam: Camera): FloatArray? {
            val img = try {
                frame.acquireDepthImage16Bits()
            } catch (e: NotYetAvailableException) {
                return null
            } catch (e: Exception) {
                return null
            }
            try {
                val w = img.width
                val h = img.height
                val plane = img.planes[0]
                val buf = plane.buffer.order(ByteOrder.LITTLE_ENDIAN)
                val rowStride = plane.rowStride
                val pixStride = plane.pixelStride

                // Intrinsics are for the CPU image; the depth map has the same
                // aspect ratio at lower resolution, so scale them down.
                val intr = cam.imageIntrinsics
                val f = intr.focalLength
                val c = intr.principalPoint
                val dims = intr.imageDimensions
                val sx = w.toFloat() / dims[0]
                val sy = h.toFloat() / dims[1]
                val fx = f[0] * sx
                val fy = f[1] * sy
                val cx = c[0] * sx
                val cy = c[1] * sy

                val pose = cam.pose
                val out = FloatArray(((w + DEPTH_STEP - 1) / DEPTH_STEP) * ((h + DEPTH_STEP - 1) / DEPTH_STEP) * 3)
                val local = FloatArray(3)
                val world = FloatArray(3)
                var n = 0
                var v = 0
                while (v < h) {
                    var u = 0
                    while (u < w) {
                        val mm = buf.getShort(v * rowStride + u * pixStride).toInt() and 0xFFFF
                        if (mm != 0) {
                            val d = mm / 1000f
                            if (d in MIN_DEPTH_M..MAX_DEPTH_M) {
                                // Image coords → camera space (OpenGL convention: -Z forward, +Y up).
                                local[0] = (u - cx) * d / fx
                                local[1] = -(v - cy) * d / fy
                                local[2] = -d
                                pose.transformPoint(local, 0, world, 0)
                                out[n++] = world[0]
                                out[n++] = world[1]
                                out[n++] = world[2]
                            }
                        }
                        u += DEPTH_STEP
                    }
                    v += DEPTH_STEP
                }
                return out.copyOf(n)
            } finally {
                img.close()
            }
        }

        /** Sparse fallback for devices without the Depth API. */
        private fun featurePoints(frame: Frame): FloatArray? {
            val pc = try { frame.acquirePointCloud() } catch (e: Exception) { return null }
            try {
                val b = pc.points // x, y, z, confidence
                val count = b.remaining() / 4
                val out = FloatArray(count * 3)
                var n = 0
                for (i in 0 until count) {
                    if (b.get(i * 4 + 3) < 0.3f) continue
                    out[n++] = b.get(i * 4)
                    out[n++] = b.get(i * 4 + 1)
                    out[n++] = b.get(i * 4 + 2)
                }
                return out.copyOf(n)
            } finally {
                pc.release()
            }
        }

        private fun trackingName(cam: Camera): String = when (cam.trackingState) {
            TrackingState.TRACKING -> "normal"
            TrackingState.PAUSED -> when (cam.trackingFailureReason) {
                TrackingFailureReason.INSUFFICIENT_LIGHT -> "insufficient_light"
                TrackingFailureReason.EXCESSIVE_MOTION -> "excessive_motion"
                TrackingFailureReason.INSUFFICIENT_FEATURES -> "insufficient_features"
                TrackingFailureReason.CAMERA_UNAVAILABLE -> "unavailable"
                else -> "initializing"
            }
            else -> "unavailable"
        }
    }

    companion object {
        private const val EMIT_INTERVAL_MS = 250L
        private const val DEPTH_STEP = 2      // sample every 2nd depth pixel
        private const val MIN_DEPTH_M = 0.2f
        private const val MAX_DEPTH_M = 4.0f  // depth gets noisy beyond ~4 m
    }
}
