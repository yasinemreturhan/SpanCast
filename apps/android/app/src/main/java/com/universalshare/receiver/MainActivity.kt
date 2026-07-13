package com.universalshare.receiver

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.net.http.SslError
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Bundle
import android.view.View
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * UniversalShare alıcısı: LAN'daki ushare sunucusunun receiver arayüzünü
 * WebView'da açar. Sunucu mDNS (_ushare._tcp) ile otomatik bulunur; bulunamazsa
 * adres elle girilir. TV kumandasıyla (D-pad) tam kullanılabilir.
 */
class MainActivity : Activity() {

    private lateinit var webView: WebView
    private lateinit var connectUi: LinearLayout
    private lateinit var statusText: TextView
    private var nsd: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webview)
        connectUi = findViewById(R.id.connectUi)
        statusText = findViewById(R.id.statusText)
        val addressInput = findViewById<EditText>(R.id.addressInput)
        val connectBtn = findViewById<Button>(R.id.connectBtn)

        setupWebView()

        // Son kullanılan sunucuyu hatırla.
        val prefs = getSharedPreferences("ushare", MODE_PRIVATE)
        prefs.getString("server", null)?.let { addressInput.setText(it) }

        connectBtn.setOnClickListener {
            val addr = addressInput.text.toString().trim()
            if (addr.isNotEmpty()) {
                prefs.edit().putString("server", addr).apply()
                openReceiver(addr)
            }
        }

        startDiscovery(addressInput)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
        }
        webView.webChromeClient = object : WebChromeClient() {
            // WebRTC medya izinleri (alıcı yalnız izler; yine de istenirse ver).
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread { request.grant(request.resources) }
            }
        }
        webView.webViewClient = object : WebViewClient() {
            // ushare self-signed sertifika kullanır; kullanıcı onayıyla ilerle.
            @SuppressLint("WebViewClientOnReceivedSslError")
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                AlertDialog.Builder(this@MainActivity)
                    .setTitle(getString(R.string.ssl_title))
                    .setMessage(getString(R.string.ssl_message))
                    .setPositiveButton(getString(R.string.ssl_accept)) { _, _ -> handler.proceed() }
                    .setNegativeButton(getString(R.string.ssl_reject)) { _, _ -> handler.cancel() }
                    .show()
            }
        }
    }

    private fun openReceiver(hostPort: String) {
        connectUi.visibility = View.GONE
        webView.visibility = View.VISIBLE
        webView.loadUrl("https://$hostPort/receiver.html")
        webView.requestFocus()
    }

    /** mDNS ile _ushare._tcp sunucularını arar; ilk bulunanı öner. */
    private fun startDiscovery(addressInput: EditText) {
        nsd = getSystemService(NSD_SERVICE) as NsdManager
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(service: NsdServiceInfo) {
                nsd?.resolveService(service, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        runOnUiThread {
                            if (addressInput.text.isEmpty()) {
                                addressInput.setText("${info.host.hostAddress}:${info.port}")
                            }
                            statusText.text = getString(R.string.found_server, info.serviceName)
                        }
                    }
                    override fun onResolveFailed(info: NsdServiceInfo, code: Int) {}
                })
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) {}
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        }
        discoveryListener = listener
        runCatching { nsd?.discoverServices("_ushare._tcp.", NsdManager.PROTOCOL_DNS_SD, listener) }
    }

    override fun onDestroy() {
        discoveryListener?.let { runCatching { nsd?.stopServiceDiscovery(it) } }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (webView.visibility == View.VISIBLE) {
            // TV'de geri: bağlantı ekranına dön.
            webView.loadUrl("about:blank")
            webView.visibility = View.GONE
            connectUi.visibility = View.VISIBLE
        } else {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }
}
