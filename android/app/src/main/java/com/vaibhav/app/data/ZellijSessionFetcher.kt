package com.vaibhav.app.data

import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

data class VaibhavProject(
    val name: String,
    val path: String,
    val active: Boolean
)

data class VaibhavStatus(
    val projects: List<VaibhavProject>,
    val sessions: List<String>
)

object VaibhavApi {

    private const val TAG = "VaibhavApi"
    private val gson = Gson()

    suspend fun fetchStatus(filesBaseUrl: String): VaibhavStatus = withContext(Dispatchers.IO) {
        try {
            val apiUrl = "${filesBaseUrl.trimEnd('/')}/api/status"
            Log.d(TAG, "Fetching: $apiUrl")
            val url = URL(apiUrl)
            val conn = url.openConnection() as HttpURLConnection

            if (conn is HttpsURLConnection) {
                installTrustAll(conn)
            }

            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Accept", "application/json")

            val responseCode = conn.responseCode
            Log.d(TAG, "Response code: $responseCode")

            if (responseCode != 200) {
                Log.e(TAG, "HTTP $responseCode")
                conn.disconnect()
                return@withContext VaibhavStatus(emptyList(), emptyList())
            }

            val json = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            Log.d(TAG, "Got ${json.length} bytes")
            gson.fromJson(json, VaibhavStatus::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch status: ${e.javaClass.simpleName}: ${e.message}")
            VaibhavStatus(emptyList(), emptyList())
        }
    }

    data class ApiResponse(val ok: Boolean, val error: String? = null, val session: String? = null)

    suspend fun killSession(filesBaseUrl: String, sessionName: String): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val url = URL("${filesBaseUrl.trimEnd('/')}/api/kill")
            val conn = url.openConnection() as HttpURLConnection
            if (conn is HttpsURLConnection) installTrustAll(conn)
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Content-Type", "application/json")

            val body = """{"session":"$sessionName"}"""
            conn.outputStream.bufferedWriter().use { it.write(body) }

            val json = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            gson.fromJson(json, ApiResponse::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "Kill failed: ${e.message}")
            ApiResponse(ok = false, error = e.message)
        }
    }

    suspend fun openProject(filesBaseUrl: String, project: String, tool: String): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val url = URL("${filesBaseUrl.trimEnd('/')}/api/open")
            val conn = url.openConnection() as HttpURLConnection
            if (conn is HttpsURLConnection) installTrustAll(conn)
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.setRequestProperty("Content-Type", "application/json")

            val body = if (tool.isNotBlank()) {
                """{"project":"$project","tool":"$tool"}"""
            } else {
                """{"project":"$project"}"""
            }
            conn.outputStream.bufferedWriter().use { it.write(body) }

            val json = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            gson.fromJson(json, ApiResponse::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "Open failed: ${e.message}")
            ApiResponse(ok = false, error = e.message)
        }
    }

    private fun installTrustAll(conn: HttpsURLConnection) {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAll, SecureRandom())
        conn.sslSocketFactory = sslContext.socketFactory
        conn.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, _ -> true }
    }
}
