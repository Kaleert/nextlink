package pro.kaleert.nextlink

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import java.lang.ref.WeakReference

class NextLinkTileService : TileService() {
    companion object {
        // A non-active tile is bound while the panel is open. Update that tile
        // directly; requestListeningState() is ignored for this manifest mode.
        private var listeningService: WeakReference<NextLinkTileService>? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun refreshState() {
            mainHandler.post { listeningService?.get()?.renderState() }
        }
    }

    private fun renderState() {
        qsTile?.apply {
            val vpnIsOn = VpnTunnelService.isAlive &&
                VpnTunnelService.hasActiveTunnel &&
                !VpnTunnelService.isPaused
            state = if (vpnIsOn) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = getString(R.string.qs_vpn_tile_label)
            icon = Icon.createWithResource(this@NextLinkTileService, R.drawable.ic_qs_vpn)
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        listeningService = WeakReference(this)
        renderState()
    }

    override fun onStopListening() {
        if (listeningService?.get() === this) listeningService = null
        super.onStopListening()
    }

    override fun onDestroy() {
        if (listeningService?.get() === this) listeningService = null
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        if (!VpnTunnelService.hasActiveTunnel && !VpnTunnelService.isPaused) {
            val savedConfig = getSharedPreferences("quick_tile_vpn", MODE_PRIVATE)
                .getString("config", null)
            if (savedConfig.isNullOrBlank()) {
                Toast.makeText(
                    this,
                    NativeStrings.text(this, "Сначала выберите сервер и подключитесь в NextLink"),
                    Toast.LENGTH_SHORT,
                ).show()
                renderState()
                return
            }
        }
        val command = Intent(this, VpnTunnelService::class.java).apply {
            action = VpnTunnelService.ACTION_TILE_TOGGLE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(command)
        else startService(command)
    }
}
