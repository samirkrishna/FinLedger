package com.finledger.finledger

import android.Manifest
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.content.ContentValues
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.finledger.app/sms"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "importInbox" -> {
                    if (checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_SMS), 402)
                        result.error("PERMISSION_REQUIRED", "SMS inbox permission not granted", null)
                    } else {
                        val items = mutableListOf<Map<String, Any?>>()
                        val cursor = contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE), null, null, "date DESC")
                        cursor?.use { while (it.moveToNext() && items.size < 5000) {
                            items.add(mapOf("sender" to it.getString(0), "body" to it.getString(1), "date" to it.getLong(2)))
                        } }
                        result.success(items)
                    }
                }
                "getPendingSms" -> {
                    val file = getDatabasePath("finledger.db")
                    if (!file.exists()) { result.success(emptyList<Map<String, Any?>>()) }
                    else {
                        val db = SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
                        val items = mutableListOf<Map<String, Any?>>()
                        try {
                            val cursor = db.rawQuery("SELECT id, sender, body, received_at FROM sms_queue ORDER BY id", null)
                            cursor.use { while (it.moveToNext()) items.add(mapOf("id" to it.getLong(0), "sender" to it.getString(1), "body" to it.getString(2), "date" to it.getLong(3))) }
                            db.delete("sms_queue", null, null)
                        } catch (_: Exception) { }
                        db.close()
                        result.success(items)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
