package com.finledger.finledger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.provider.Telephony

class BankSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return
        val dbFile = context.getDatabasePath("finledger.db")
        dbFile.parentFile?.mkdirs()
        val db = SQLiteDatabase.openOrCreateDatabase(dbFile, null)
        try {
            db.execSQL("CREATE TABLE IF NOT EXISTS sms_queue(id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT, body TEXT, received_at INTEGER)")
            db.beginTransaction()
            for (sms in messages) {
                val body = sms.messageBody ?: continue
                // Queue only likely financial notifications; never persist OTP or unrelated SMS.
                val lower = body.lowercase()
                val hasMoney = Regex("(inr|rs\\.?|₹)\\s*[0-9,]+", RegexOption.IGNORE_CASE).containsMatchIn(body)
                val hasTxn = listOf("debited", "credited", "withdrawn", "deposited", "spent", "received", "transferred", "purchase", "paid").any { lower.contains(it) }
                val otp = lower.contains("otp") || lower.contains("one time password")
                if (hasMoney && hasTxn && !otp) {
                    val values = android.content.ContentValues().apply {
                        put("sender", sms.originatingAddress ?: "")
                        put("body", body)
                        put("received_at", sms.timestampMillis)
                    }
                    db.insert("sms_queue", null, values)
                }
            }
            db.setTransactionSuccessful()
            db.endTransaction()
        } finally { db.close() }
    }
}
