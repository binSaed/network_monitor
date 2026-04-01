package com.example.network_monitor

import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.net.CacheRequest
import java.net.CacheResponse
import java.net.ResponseCache
import java.net.URI
import java.net.URLConnection
import java.util.concurrent.CopyOnWriteArrayList

data class NativeNetworkRecord(
    val url: String,
    val method: String,
    val statusCode: Int,
    val requestSizeBytes: Int,
    val responseSizeBytes: Int,
    val timestamp: Long,
    val durationMs: Long,
    val source: String
) {
    fun toMap(): Map<String, Any> = mapOf(
        "url" to url,
        "method" to method,
        "statusCode" to statusCode,
        "requestSizeBytes" to requestSizeBytes,
        "responseSizeBytes" to responseSizeBytes,
        "timestamp" to timestamp,
        "durationMs" to durationMs,
        "source" to source
    )
}

class NetworkMonitorCache : ResponseCache() {
    companion object {
        var maxRecords = 500
        val records = CopyOnWriteArrayList<NativeNetworkRecord>()

        fun drainRecords(): List<NativeNetworkRecord> {
            val drained = ArrayList(records)
            records.clear()
            return drained
        }

        fun addRecord(record: NativeNetworkRecord) {
            records.add(record)
            while (records.size > maxRecords) {
                records.removeAt(0)
            }
        }
    }

    override fun get(
        uri: URI?,
        requestMethod: String?,
        rqstHeaders: MutableMap<String, MutableList<String>>?
    ): CacheResponse? {
        return null
    }

    override fun put(uri: URI?, conn: URLConnection?): CacheRequest? {
        if (uri != null && conn != null) {
            try {
                val contentLength = conn.contentLength
                val responseCode =
                    if (conn is java.net.HttpURLConnection) conn.responseCode else 0
                addRecord(
                    NativeNetworkRecord(
                        url = uri.toString(),
                        method = conn.getRequestProperty("X-HTTP-Method-Override") ?: "GET",
                        statusCode = responseCode,
                        requestSizeBytes = 0,
                        responseSizeBytes = if (contentLength > 0) contentLength else 0,
                        timestamp = System.currentTimeMillis(),
                        durationMs = 0,
                        source = "native_android"
                    )
                )
            } catch (_: Exception) {
            }
        }
        return null
    }
}

class NetworkMonitorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        try {
            if (ResponseCache.getDefault() == null) {
                ResponseCache.setDefault(NetworkMonitorCache())
            }
        } catch (_: Exception) {
        }

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "network_monitor")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getRecords" -> {
                val records = NetworkMonitorCache.drainRecords()
                result.success(records.map { it.toMap() })
            }

            "setMaxRecords" -> {
                val max = call.argument<Int>("maxRecords") ?: 500
                NetworkMonitorCache.maxRecords = max
                result.success(null)
            }

            "getTrafficStats" -> {
                val uid = Process.myUid()
                val txBytes = TrafficStats.getUidTxBytes(uid)
                val rxBytes = TrafficStats.getUidRxBytes(uid)
                result.success(mapOf("txBytes" to txBytes, "rxBytes" to rxBytes))
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
