package br.com.prismrr.sinalacs.patient

import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Lado nativo do canal `sinalacs/push_token` (RF14): devolve o token FCM do
/// aparelho. O contrato Dart está em `native_push_token_source.dart`: qualquer erro
/// aqui vira `null` lá, e o app segue sem push.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sinalacs/push_token")
            .setMethodCallHandler { call, result ->
                if (call.method != "getToken") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Sem google-services.json (CI, outro dev) o FirebaseApp não existe.
                if (FirebaseApp.getApps(this).isEmpty()) {
                    result.error("firebase_unavailable", "FirebaseApp não inicializado", null)
                    return@setMethodCallHandler
                }
                FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                    val token = if (task.isSuccessful) task.result else null
                    if (!token.isNullOrBlank()) {
                        result.success(mapOf("token" to token, "platform" to "android"))
                    } else {
                        result.error("token_unavailable", task.exception?.message, null)
                    }
                }
            }
    }
}
