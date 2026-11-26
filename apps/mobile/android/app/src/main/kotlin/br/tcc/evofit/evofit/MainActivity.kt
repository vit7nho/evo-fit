package br.tcc.evofit.evofit

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal "br.tcc.evofit/files" (5.6, ADR-063): salva um texto num arquivo escolhido pela
 * pessoa, pelo "Salvar como" do próprio Android (Storage Access Framework). Sem pacote
 * novo nem permissão de armazenamento: o sistema dá acesso só ao arquivo criado.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "Já há um arquivo sendo salvo.", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/json"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName"))
                }
                pendingResult = result
                pendingContent = call.argument<String>("content") ?: ""
                startActivityForResult(intent, SAVE_REQUEST)
            }
    }

    @Deprecated("O Flutter ainda entrega o resultado por aqui.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val result = pendingResult ?: return
        val content = pendingContent
        pendingResult = null
        pendingContent = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || content == null) {
            result.success(false) // a pessoa cancelou
            return
        }
        try {
            contentResolver.openOutputStream(uri, "wt")?.use { it.write(content.toByteArray()) }
                ?: throw IllegalStateException("Sem acesso ao arquivo.")
            result.success(true)
        } catch (error: Exception) {
            result.error("write_failed", "Não foi possível gravar o arquivo.", null)
        }
    }

    private companion object {
        const val CHANNEL = "br.tcc.evofit/files"
        const val SAVE_REQUEST = 4242
    }
}
