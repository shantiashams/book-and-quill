package com.shantiashams.book_and_quill

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel

/** System media controls for the existing SoLoud player. No second audio player. */
class BookMusicService : Service() {
    companion object {
        private const val CHANNEL = "book_music"
        private const val NOTIFICATION = 350
        private const val UPDATE = "book.media.UPDATE"
        private const val STOP = "book.media.STOP"
        var commandChannel: MethodChannel? = null
        private var instance: BookMusicService? = null
        private var requestId = 0
        private val pending = mutableMapOf<Int, MethodChannel.Result>()

        fun publish(context: Context, data: Map<*, *>, result: MethodChannel.Result) {
            if (commandChannel == null) { result.success(false); return }
            val intent = Intent(context, BookMusicService::class.java).setAction(UPDATE)
            for (key in listOf("trackId", "title", "artist", "album", "artwork")) {
                intent.putExtra(key, data[key] as? String ?: "")
            }
            intent.putExtra("positionMs", (data["positionMs"] as? Number)?.toLong() ?: 0L)
            intent.putExtra("durationMs", (data["durationMs"] as? Number)?.toLong() ?: 0L)
            intent.putExtra("paused", data["paused"] as? Boolean ?: true)
            val id = ++requestId
            pending[id] = result
            intent.putExtra("requestId", id)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                pending.remove(id)
                throw error
            }
        }

        fun requestFocus(): Boolean = instance?.acquireFocus() ?: false

        fun clear(context: Context) {
            context.stopService(Intent(context, BookMusicService::class.java))
        }
    }

    private lateinit var session: MediaSession
    private lateinit var audio: AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var paused = true
    private var position = 0L
    private var duration = 0L
    private var title = "Book and Quill"
    private var artist = ""
    private var album = ""
    private var trackId = ""
    private var artworkPath = ""
    private var artwork: Bitmap? = null
    private var lastNotification = ""
    private val handler = Handler(Looper.getMainLooper())
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
            hasFocus = false
            command("pause")
        }
    }
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) command("pause")
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL, "Music playback", NotificationManager.IMPORTANCE_LOW
            ).apply { setSound(null, null) })
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(focusListener, handler)
                .build()
        }
        session = MediaSession(this, "Book and Quill")
        session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = command("play")
            override fun onPause() = command("pause")
            override fun onSkipToNext() = command("next")
            override fun onSkipToPrevious() = command("previous")
            override fun onSeekTo(pos: Long) = command("seek", pos)
            override fun onStop() = command("stop")
        }, handler)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) session.setSessionActivity(PendingIntent.getActivity(
            this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        session.isActive = true
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(noisyReceiver, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (commandChannel == null || intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent.action) {
            UPDATE -> {
                val result = pending.remove(intent.getIntExtra("requestId", -1))
                try { update(intent); result?.success(true) }
                catch (error: Exception) {
                    result?.error("MEDIA_SESSION", error.message, null)
                    command("pause")
                    stopSelf()
                }
            }
            STOP -> { command("stop"); stopSelf() }
            else -> command(intent.action ?: "pause")
        }
        return START_NOT_STICKY
    }

    private fun command(name: String, positionMs: Long? = null) {
        commandChannel?.invokeMethod("command", mapOf("name" to name, "positionMs" to positionMs))
    }

    private fun update(intent: Intent) {
        val changed = trackId != intent.getStringExtra("trackId")
        trackId = intent.getStringExtra("trackId") ?: ""
        title = intent.getStringExtra("title") ?: "Book and Quill"
        artist = intent.getStringExtra("artist") ?: ""
        album = intent.getStringExtra("album") ?: ""
        duration = intent.getLongExtra("durationMs", 0).coerceAtLeast(0)
        position = intent.getLongExtra("positionMs", 0).coerceIn(0, duration)
        paused = intent.getBooleanExtra("paused", true)
        val path = intent.getStringExtra("artwork") ?: ""
        if (path != artworkPath) {
            artworkPath = path
            artwork = try {
                val asset = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
                assets.open(asset).use { stream ->
                    BitmapFactory.decodeStream(stream, null, BitmapFactory.Options().apply { inSampleSize = 4 })
                }
            } catch (_: Exception) { null }
        }
        if (changed || session.controller.metadata == null) {
            session.setMetadata(MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, trackId)
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
                .putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, artwork)
                .putBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON, artwork).build())
        }
        updateState()
        // Become a mediaPlayback foreground service before asking for focus:
        // Android 15+ requires the app to be topmost or to have an active FGS.
        showNotification()
        if (!paused && !acquireFocus()) command("pause")
        else if (paused) releaseFocus()
    }

    private fun acquireFocus(): Boolean {
        if (hasFocus) return true
        val result = if (Build.VERSION.SDK_INT >= 26) audio.requestAudioFocus(focusRequest!!)
            else audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        hasFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasFocus
    }

    private fun updateState() {
        val actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_STOP
        session.setPlaybackState(PlaybackState.Builder().setActions(actions)
            .setState(if (paused) PlaybackState.STATE_PAUSED else PlaybackState.STATE_PLAYING,
                position, if (paused) 0f else 1f, SystemClock.elapsedRealtime()).build())
    }

    private fun action(name: String, icon: Int, label: String): Notification.Action {
        val intent = Intent(this, BookMusicService::class.java).setAction(name)
        val pending = PendingIntent.getService(this, name.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Action.Builder(icon, label, pending).build()
    }

    private fun showNotification() {
        val signature = "$trackId|$paused"
        if (signature == lastNotification) return
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_music_notification)
            .setContentTitle(title).setContentText(artist).setSubText(album)
            .setLargeIcon(artwork)
            .setContentIntent(session.controller.sessionActivity)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true).setShowWhen(false).setOngoing(!paused)
            .addAction(action("previous", android.R.drawable.ic_media_previous, "Previous"))
            .addAction(action(if (paused) "play" else "pause",
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (paused) "Play" else "Pause"))
            .addAction(action("next", android.R.drawable.ic_media_next, "Next"))
            .setDeleteIntent(PendingIntent.getService(this, 350,
                Intent(this, BookMusicService::class.java).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)).build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else startForeground(NOTIFICATION, notification)
        lastNotification = signature
    }

    private fun releaseFocus() {
        if (Build.VERSION.SDK_INT >= 26) audio.abandonAudioFocusRequest(focusRequest!!)
        else audio.abandonAudioFocus(focusListener)
        hasFocus = false
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        command("stop")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        instance = null
        for (result in pending.values) result.success(false)
        pending.clear()
        releaseFocus()
        unregisterReceiver(noisyReceiver)
        session.isActive = false
        session.release()
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
