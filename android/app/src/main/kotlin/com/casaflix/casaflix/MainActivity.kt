package com.casaflix.casaflix

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.res.Configuration
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingApkPath: String? = null
    private var pictureInPictureEnabled = false
    private var pictureInPicturePlaying = true
    private var pictureInPictureWidth = 16
    private var pictureInPictureHeight = 9
    private var pictureInPictureReceiverRegistered = false
    private lateinit var deviceChannel: MethodChannel
    private val pictureInPictureReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != PICTURE_IN_PICTURE_CONTROL) return
            val action = intent.getStringExtra(PICTURE_IN_PICTURE_ACTION) ?: return
            if (::deviceChannel.isInitialized) {
                deviceChannel.invokeMethod("pictureInPictureAction", action)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
        registerPictureInPictureReceiver()
        deviceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> {
                    val uiModeManager = getSystemService(UI_MODE_SERVICE) as UiModeManager
                    val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                        packageManager.hasSystemFeature("android.software.leanback") ||
                        packageManager.hasSystemFeature("android.hardware.type.television")
                    result.success(isTv)
                }
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "setPictureInPictureEnabled" -> {
                    val requested = call.argument<Boolean>("enabled") ?: false
                    pictureInPictureEnabled =
                        requested && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                    val width = call.argument<Int>("width") ?: 16
                    val height = call.argument<Int>("height") ?: 9
                    pictureInPictureWidth = width
                    pictureInPictureHeight = height
                    updatePictureInPictureParams(width, height)
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                }
                "setPictureInPicturePlaying" -> {
                    pictureInPicturePlaying = call.argument<Boolean>("playing") ?: true
                    updatePictureInPictureParams(
                        pictureInPictureWidth,
                        pictureInPictureHeight
                    )
                    result.success(null)
                }
                "enterPictureInPicture" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
                        !pictureInPictureEnabled ||
                        isInPictureInPictureMode
                    ) {
                        result.success(isInPictureInPictureMode)
                    } else {
                        val entered = runCatching {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                enterPictureInPictureMode(
                                    currentPictureInPictureParams(
                                        pictureInPictureWidth,
                                        pictureInPictureHeight
                                    )
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                enterPictureInPictureMode()
                            }
                        }.getOrDefault(false)
                        result.success(entered)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(info.versionName ?: "0.0.0")
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "O instalador não foi encontrado.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val apk = validatedApk(path)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            pendingApkPath = apk.path
                            val settingsIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(settingsIntent)
                            result.success("permissionRequested")
                        } else {
                            launchInstaller(apk)
                            result.success("started")
                        }
                    } catch (error: Exception) {
                        result.error("INSTALL_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val path = pendingApkPath ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = null
            runCatching { launchInstaller(validatedApk(path)) }
        }
    }

    override fun onDestroy() {
        if (pictureInPictureReceiverRegistered) {
            unregisterReceiver(pictureInPictureReceiver)
            pictureInPictureReceiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            !pictureInPictureEnabled ||
            isInPictureInPictureMode
        ) return
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.N until Build.VERSION_CODES.S) {
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    enterPictureInPictureMode(
                        currentPictureInPictureParams(
                            pictureInPictureWidth,
                            pictureInPictureHeight
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    enterPictureInPictureMode()
                }
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (::deviceChannel.isInitialized) {
            deviceChannel.invokeMethod(
                "pictureInPictureChanged",
                isInPictureInPictureMode
            )
        }
    }

    private fun updatePictureInPictureParams(width: Int, height: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(safeAspectRatio(width, height))
            .setActions(listOf(pictureInPictureAction()))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pictureInPictureEnabled)
            builder.setSeamlessResizeEnabled(true)
        }
        setPictureInPictureParams(builder.build())
    }

    private fun currentPictureInPictureParams(width: Int, height: Int): PictureInPictureParams =
        PictureInPictureParams.Builder()
            .setAspectRatio(safeAspectRatio(width, height))
            .setActions(listOf(pictureInPictureAction()))
            .build()

    private fun pictureInPictureAction(): RemoteAction {
        val action = if (pictureInPicturePlaying) "pause" else "play"
        val title = if (pictureInPicturePlaying) "Pausar" else "Reproduzir"
        val icon = if (pictureInPicturePlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val intent = Intent(PICTURE_IN_PICTURE_CONTROL)
            .setPackage(packageName)
            .putExtra(PICTURE_IN_PICTURE_ACTION, action)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            if (pictureInPicturePlaying) 1 else 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return RemoteAction(
            Icon.createWithResource(this, icon),
            title,
            title,
            pendingIntent
        )
    }

    private fun registerPictureInPictureReceiver() {
        if (pictureInPictureReceiverRegistered) return
        val filter = IntentFilter(PICTURE_IN_PICTURE_CONTROL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                pictureInPictureReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(pictureInPictureReceiver, filter)
        }
        pictureInPictureReceiverRegistered = true
    }

    private fun safeAspectRatio(width: Int, height: Int): Rational {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val ratio = safeWidth.toDouble() / safeHeight
        return when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < (1.0 / 2.39) -> Rational(100, 239)
            else -> Rational(safeWidth, safeHeight)
        }
    }

    private fun validatedApk(path: String): File {
        val apk = File(path).canonicalFile
        val filesRoot = filesDir.canonicalFile.path + File.separator
        require(apk.path.startsWith(filesRoot)) { "O arquivo está fora da pasta segura do aplicativo." }
        require(apk.isFile && apk.extension.equals("apk", ignoreCase = true)) {
            "O instalador baixado não é válido."
        }
        return apk
    }

    private fun launchInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    companion object {
        private const val CHANNEL = "netpobre/app_update"
        private const val DEVICE_CHANNEL = "netpobre/device"
        private const val PICTURE_IN_PICTURE_CONTROL =
            "com.casaflix.casaflix.PICTURE_IN_PICTURE_CONTROL"
        private const val PICTURE_IN_PICTURE_ACTION = "action"
    }
}
