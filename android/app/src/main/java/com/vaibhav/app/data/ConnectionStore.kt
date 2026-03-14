package com.vaibhav.app.data

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.vaibhav.app.model.ConnectionConfig

class ConnectionStore(context: Context) {
    private val prefs = context.getSharedPreferences("vaibhav_connections", Context.MODE_PRIVATE)
    private val gson = Gson()

    fun save(connections: List<ConnectionConfig>) {
        prefs.edit().putString("connections", gson.toJson(connections)).apply()
    }

    fun load(): List<ConnectionConfig> {
        val json = prefs.getString("connections", null) ?: return emptyList()
        val type = object : TypeToken<List<ConnectionConfig>>() {}.type
        val list: List<ConnectionConfig> = gson.fromJson(json, type)
        return list.map { it.withDefaults() }
    }

    fun saveLast(config: ConnectionConfig) {
        prefs.edit().putString("last_connection", gson.toJson(config)).apply()
    }

    fun loadLast(): ConnectionConfig? {
        val json = prefs.getString("last_connection", null) ?: return null
        return gson.fromJson(json, ConnectionConfig::class.java).withDefaults()
    }
}
