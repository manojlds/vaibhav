package com.vaibhav.app.model

data class ConnectionConfig(
    val name: String,
    val host: String,
    val port: Int = 8443,
    val filesPort: Int = 9443,
    val zellijSessionName: String = ""
) {
    val zellijWebUrl: String
        get() {
            val sessionPath = if (zellijSessionName.isNotBlank()) "/$zellijSessionName" else ""
            return "https://$host:$port$sessionPath"
        }

    val filesBaseUrl: String
        get() = "https://$host:$filesPort"

    fun withDefaults() = copy(
        port = if (port == 0) 8443 else port,
        filesPort = if (filesPort == 0) 9443 else filesPort
    )
}
