package br.com.prismrr.sinalacs.acs

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A lista da microárea mostra nome e condições crônicas. FLAG_SECURE
        // bloqueia captura de tela, gravação e a miniatura nos apps recentes,
        // na janela INTEIRA: Área, Visita e o seletor de paciente a exibem, e
        // proteger tela por tela deixaria uma de fora.
        //
        // A ÚNICA exceção é a constante de compilação abaixo, que o Gradle só liga no
        // buildType debug por `-Psinalacs.allowScreenCapture=true` e recusa em release:
        // nenhum menu, intent ou preferência a altera.
        if (!BuildConfig.ALLOW_SCREEN_CAPTURE) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cofre do refresh token: decifra só com BiometricPrompt/CryptoObject.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KeystoreVault.CHANNEL)
            .setMethodCallHandler(KeystoreVault(this))
    }
}
