package com.starics.pdf

/** One language's question + answer text for a single question group. */
data class LangContent(
    val question: String,
    val answer: String
)

/** A single question, with content for each requested language code (e.g. "en", "gj", "hi"). */
data class QuestionGroup(
    val srNo: Int,
    val byLanguage: Map<String, LangContent>
)

data class PdfConfig(
    val watermarkText: String = "Star",
    val watermarkSubText: String = "Institute of Civil Services",
    val showWatermark: Boolean = true,
    val watermarkAlpha: Float = 0.09f,
    val telegramHandle: String = "@starics_prep",
    val emailContact: String = "star.ics89@gmail.com",
    val xHandle: String = "@star_ics89"
)
