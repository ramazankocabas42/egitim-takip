package PAKET

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SMS kutusundan kurum deneme sonuçlarını okumak için kanal.
 * Yalnızca okuma yapar; SMS göndermez, silmez.
 */
class MainActivity : FlutterActivity() {
    private var bekleyen: MethodChannel.Result? = null
    private val izinKodu = 4242

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "egitim_takip/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "izinVar" -> result.success(izinVar())
                    "izinIste" -> {
                        if (izinVar()) {
                            result.success(true)
                        } else {
                            bekleyen?.success(false)
                            bekleyen = result
                            requestPermissions(arrayOf(Manifest.permission.READ_SMS), izinKodu)
                        }
                    }
                    "oku" -> {
                        if (!izinVar()) {
                            result.success(emptyList<Map<String, Any>>())
                        } else {
                            try {
                                val gonderen = call.argument<String>("gonderen") ?: ""
                                val ifade = call.argument<String>("ifade") ?: ""
                                val sonra = (call.argument<Number>("sonra") ?: 0).toLong()
                                result.success(oku(gonderen, ifade, sonra))
                            } catch (e: Exception) {
                                result.error("SMS", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun izinVar(): Boolean =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun oku(gonderen: String, ifade: String, sonra: Long): List<Map<String, Any>> {
        val liste = mutableListOf<Map<String, Any>>()
        val secim = "date > ? AND (UPPER(address) LIKE ? OR body LIKE ?)"
        val argumanlar = arrayOf(
            sonra.toString(),
            "%" + gonderen.uppercase() + "%",
            "%" + ifade + "%"
        )
        contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("_id", "address", "body", "date"),
            secim, argumanlar, "date DESC"
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow("_id")
            val iAdres = c.getColumnIndexOrThrow("address")
            val iMetin = c.getColumnIndexOrThrow("body")
            val iTarih = c.getColumnIndexOrThrow("date")
            while (c.moveToNext() && liste.size < 300) {
                liste.add(
                    mapOf(
                        "id" to c.getLong(iId).toString(),
                        "adres" to (c.getString(iAdres) ?: ""),
                        "metin" to (c.getString(iMetin) ?: ""),
                        "tarih" to c.getLong(iTarih)
                    )
                )
            }
        }
        return liste
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == izinKodu) {
            bekleyen?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            bekleyen = null
        }
    }
}
