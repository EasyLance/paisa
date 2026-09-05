package com.paisa.paisa_mobile

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

object FinancialEventQueue {
    private const val prefsName = "paisa_financial_events"
    private const val queueKey = "normalized_events_v1"

    @Synchronized
    fun enqueue(context: Context, event: Map<String, Any>) {
        val prefs = preferences(context)
        val queue = JSONArray(prefs.getString(queueKey, "[]"))
        val hash = event["sourceHash"]
        for (index in 0 until queue.length()) {
            if (queue.getJSONObject(index).optString("sourceHash") == hash) return
        }
        queue.put(JSONObject(event))
        prefs.edit().putString(queueKey, queue.toString()).apply()
    }

    @Synchronized
    fun drain(context: Context): List<Map<String, Any?>> {
        val prefs = preferences(context)
        val queue = JSONArray(prefs.getString(queueKey, "[]"))
        val events = mutableListOf<Map<String, Any?>>()
        for (index in 0 until queue.length()) {
            val json = queue.getJSONObject(index)
            events += json.keys().asSequence().associateWith { key -> json.opt(key) }
        }
        prefs.edit().putString(queueKey, "[]").commit()
        return events
    }

    private fun preferences(context: Context) = EncryptedSharedPreferences.create(
        context,
        prefsName,
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
}
