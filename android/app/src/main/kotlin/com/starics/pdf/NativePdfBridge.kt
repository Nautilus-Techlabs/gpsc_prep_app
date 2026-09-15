package com.starics.pdf

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel handler exposing the native (Canvas/StaticLayout-based) PDF generator to Dart.
 * Channel name: "com.starics/native_pdf".
 *
 * Method "generateDescTestPdf" expects arguments:
 *   testName: String
 *   langCodes: List<String>            e.g. ["en", "gj"]
 *   showAnswers: Boolean
 *   questions: List<Map<String, Any?>> each shaped as:
 *     { "srNo": Int, "byLanguage": { "en": {"question": String, "answer": String}, "gj": {...} } }
 *
 * Returns the absolute path of the generated PDF (written under the app's cache dir).
 */
class NativePdfBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.starics/native_pdf"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateDescTestPdf" -> {
                try {
                    val testName = call.argument<String>("testName") ?: "Test"
                    val langCodes = (call.argument<List<*>>("langCodes") ?: emptyList<Any>())
                        .map { it.toString() }
                    val showAnswers = call.argument<Boolean>("showAnswers") ?: true
                    val questionsArg = call.argument<List<*>>("questions") ?: emptyList<Any>()

                    val questionGroups = questionsArg.map { raw ->
                        @Suppress("UNCHECKED_CAST")
                        val q = raw as Map<String, Any?>
                        val srNo = (q["srNo"] as? Number)?.toInt() ?: 0
                        @Suppress("UNCHECKED_CAST")
                        val byLanguageRaw = q["byLanguage"] as? Map<String, Any?> ?: emptyMap()
                        val byLanguage = byLanguageRaw.mapValues { (_, v) ->
                            @Suppress("UNCHECKED_CAST")
                            val m = v as Map<String, Any?>
                            LangContent(
                                question = m["question"] as? String ?: "",
                                answer = m["answer"] as? String ?: ""
                            )
                        }
                        QuestionGroup(srNo = srNo, byLanguage = byLanguage)
                    }

                    val file = PdfGenerator.generateDescTestPdf(
                        context = context,
                        questionGroups = questionGroups,
                        langCodes = langCodes,
                        showAnswers = showAnswers,
                        testName = testName
                    )

                    result.success(file.absolutePath)
                } catch (e: Exception) {
                    result.error("NATIVE_PDF_ERROR", e.message, e.stackTraceToString())
                }
            }
            else -> result.notImplemented()
        }
    }
}
