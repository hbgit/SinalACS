import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

fun dartDefineValue(name: String): String? {
    val encoded = project.findProperty("dart-defines")?.toString() ?: return null
    return encoded.split(",").firstNotNullOfOrNull { item ->
        runCatching {
            String(Base64.getDecoder().decode(item), Charsets.UTF_8)
        }.getOrNull()?.takeIf { it.startsWith("$name=") }?.substringAfter('=')
    }
}

// Chave de release: de `apps/acs/android/key.properties` (gitignorado) ou, para
// CI e shell, das variáveis SINALACS_KEYSTORE_*. Nenhum valor mora no repositório.
//   storeFile=/caminho/para/release.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
val keyProperties = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) FileInputStream(arquivo).use { load(it) }
}

fun assinatura(propriedade: String, ambiente: String): String? =
    keyProperties.getProperty(propriedade)?.takeIf { it.isNotBlank() }
        ?: System.getenv(ambiente)?.takeIf { it.isNotBlank() }

// `-Pfoo=false` não pode liberar nada: só o texto "true" vale (`hasProperty`
// aceitava qualquer valor, inclusive `false`).
fun licenca(nome: String): Boolean = project.findProperty(nome)?.toString() == "true"

val releaseStoreFile = assinatura("storeFile", "SINALACS_KEYSTORE_PATH")
val releaseStorePassword = assinatura("storePassword", "SINALACS_KEYSTORE_PASSWORD")
val releaseKeyAlias = assinatura("keyAlias", "SINALACS_KEY_ALIAS")
val releaseKeyPassword = assinatura("keyPassword", "SINALACS_KEY_PASSWORD")
val temChaveDeRelease = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }

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

    buildFeatures {
        // AGP 9 desliga a geração de BuildConfig por padrão; a captura de tela do
        // debug depende dela.
        buildConfig = true
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
        // Captura de tela: FECHADA em todo build. Só o buildType debug pode abri-la.
        buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", "false")
    }

    signingConfigs {
        if (temChaveDeRelease) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            // Opt-out para QA, vídeo de demonstração e Firebase Test Lab: só aqui e só
            // com `-Psinalacs.allowScreenCapture=true` (o texto exato `true`). Release
            // herda o `false` do defaultConfig e não lê a propriedade.
            buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", licenca("sinalacs.allowScreenCapture").toString())
        }
        release {
            // Sem chave, a configuração continua carregável (sync da IDE, debug):
            // quem barra a build de RELEASE é o guard `taskGraph.whenReady` abaixo.
            signingConfig = signingConfigs.getByName(if (temChaveDeRelease) "release" else "debug")
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

dependencies {
    // BiometricPrompt com CryptoObject para o cofre do refresh token
    // (KeystoreVault.kt). Fixada na 1.1.0 estável: a 1.2.0 é alpha.
    implementation("androidx.biometric:biometric:1.1.0")
}

// Guard de release: só quando uma tarefa de release está no grafo (o sync da IDE
// e `flutter run` em debug não passam por aqui). Sem chave de release, assinar
// com a de debug exige pedir (-Psinalacs.allowDebugSigning=true).
gradle.taskGraph.whenReady {
    val buildaRelease = allTasks.any {
        it.path.endsWith(":assembleRelease") ||
            it.path.endsWith(":bundleRelease") ||
            it.path.endsWith(":packageRelease")
    }
    if (buildaRelease && !temChaveDeRelease && !licenca("sinalacs.allowDebugSigning")) {
        val faltam = listOf(
            "storeFile (SINALACS_KEYSTORE_PATH)" to releaseStoreFile,
            "storePassword (SINALACS_KEYSTORE_PASSWORD)" to releaseStorePassword,
            "keyAlias (SINALACS_KEY_ALIAS)" to releaseKeyAlias,
            "keyPassword (SINALACS_KEY_PASSWORD)" to releaseKeyPassword,
        ).filter { it.second == null }.joinToString(", ") { it.first }
        throw GradleException(
            """
            |Sem chave de assinatura de release: esta build sairia assinada com a chave de debug.
            |Faltando: $faltam
            |
            |Informe a chave por apps/acs/android/key.properties (storeFile, storePassword,
            |keyAlias, keyPassword) ou pelas variáveis SINALACS_KEYSTORE_PATH,
            |SINALACS_KEYSTORE_PASSWORD, SINALACS_KEY_ALIAS e SINALACS_KEY_PASSWORD.
            |
            |Para assinar com a chave de debug DE PROPÓSITO (teste local, nunca distribuição):
            |  flutter build apk --release -Psinalacs.allowDebugSigning=true
            """.trimMargin()
        )
    }

    // A chave privada de CLIENTE do broker de desenvolvimento (assets/certs/acs_client.key)
    // não pode ir dentro de um APK de release: qualquer pessoa com o APK a extrairia.
    if (buildaRelease && licenca("sinalacs.allowScreenCapture")) {
        throw GradleException(
            """
            |-Psinalacs.allowScreenCapture=true não vale em build de release: a janela do ACS
            |(que mostra nome e condições crônicas de pacientes) fica sem captura de tela
            |liberada SOMENTE em debug. Para gravar a demonstração, gere a build de debug:
            |  ./scripts/dev/run_acs.sh --build --captura
            """.trimMargin()
        )
    }
    val chaveDeDev = rootProject.file("../assets/certs/acs_client.key")
    if (buildaRelease && chaveDeDev.exists() && !licenca("sinalacs.allowDevClientKey")) {
        throw GradleException(
            """
            |O release levaria a chave privada de desenvolvimento do broker (assets/certs/acs_client.key).
            |
            |Desde a #94 o app não usa chave de cliente embarcada: cada aparelho gera o próprio par
            |e recebe do backend um certificado por aparelho (devices.issueCertificate). Esta é uma
            |chave legada que sobrou no checkout; remova o arquivo antes de gerar o release. Para
            |um release de TESTE LOCAL, acrescente -Psinalacs.allowDevClientKey=true.
            """.trimMargin()
        )
    }
}
