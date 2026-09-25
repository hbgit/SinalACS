import java.util.Base64

fun dartDefineValue(name: String): String? {
    val encoded = project.findProperty("dart-defines")?.toString() ?: return null
    return encoded.split(",").firstNotNullOfOrNull { item ->
        runCatching {
            String(Base64.getDecoder().decode(item), Charsets.UTF_8)
        }.getOrNull()?.takeIf { it.startsWith("$name=") }?.substringAfter('=')
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.com.prismrr.sinalacs.acs"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.prismrr.sinalacs.acs"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = dartDefineValue("GOOGLE_MAPS_API_KEY") ?: ""
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Guarda contra o APK silenciosamente inútil: SINALACS_MQTT_PASSWORD é
// constante de compilação sem default (ver backend_config.dart) porque o
// broker usa um segredo por máquina — nenhum valor embutido no código
// poderia acertá-lo. Sem esta guarda, `flutter build apk` puro compila com
// sucesso um APK que nunca recebe alerta nenhum, e isso só se denuncia em
// tempo de execução, pelo banner "compilado sem a senha".
//
// Acoplada a dois detalhes internos do Flutter Gradle Plugin: a propriedade
// "dart-defines" (uma lista de pares CHAVE=VALOR em base64, separados por
// vírgula — FlutterPlugin.kt lê a mesma propriedade) e o prefixo de nome
// "compileFlutterBuild" das tarefas de compilação Dart. Se um upgrade do
// Flutter renomear qualquer um dos dois, esta guarda falha ABERTA — para de
// bloquear, sem avisar. `flutter build apk` sem senha voltando a passar é o
// sintoma; conferir isto faz parte de todo upgrade do Flutter.
fun hasMqttPassword(): Boolean {
    val encoded = project.findProperty("dart-defines")?.toString() ?: return false
    return encoded.split(",").any { item ->
        runCatching {
            String(Base64.getDecoder().decode(item), Charsets.UTF_8)
        }.getOrNull()?.let {
            it.startsWith("SINALACS_MQTT_PASSWORD=") && it.substringAfter('=').isNotEmpty()
        } ?: false
    }
}

// doFirst de TAREFA, nunca bloco de configuração: na configuração, isto
// dispararia em todo `gradlew`, inclusive o sync do Android Studio (que não
// passa define nenhum) — tornando o projeto impossível de abrir na IDE. No
// doFirst só roda quando o Dart vai de fato ser compilado.
tasks.configureEach {
    if (!name.startsWith("compileFlutterBuild")) return@configureEach
    doFirst {
        val allowMissing = project.hasProperty("sinalacs.allowMissingMqttPassword")
        if (hasMqttPassword()) return@doFirst
        if (allowMissing) {
            logger.warn("aviso: compilando sem SINALACS_MQTT_PASSWORD — este APK não vai receber alerta nenhum.")
            return@doFirst
        }
        // Nunca imprimir "dart-defines" aqui: a lista carrega a própria senha
        // quando ela FOI passada com outro nome de chave por engano.
        throw GradleException(
            """
            |Este APK não receberia alerta nenhum: falta --dart-define=SINALACS_MQTT_PASSWORD.
            |
            |O broker cria o usuário acs-area-12 com MQTT_ACS_PASSWORD, um segredo por
            |máquina gerado por scripts/dev/bootstrap_env.sh — nenhum valor embutido no
            |código poderia acertá-lo.
            |
            |  ./scripts/dev/run_acs.sh            # flutter run
            |  ./scripts/dev/run_acs.sh --build    # APK de depuração
            |  ./scripts/qa/e2e.sh --emulator      # integration_test
            |
            |Para compilar de propósito sem a senha — por exemplo, para reproduzir na tela
            |o aviso "compilado sem a senha" —, acrescente:
            |  -Psinalacs.allowMissingMqttPassword=true
            """.trimMargin()
        )
    }
}
