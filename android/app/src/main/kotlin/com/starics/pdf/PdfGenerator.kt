package com.starics.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.StyleSpan
import java.io.File
import java.io.FileOutputStream

/**
 * Ported from the csv-to-pdf reference app's PdfGenerator: renders descriptive-test PDFs
 * using Android's native Canvas/StaticLayout text engine (OS-level Indic shaping) instead
 * of dart_pdf's custom shaper, to sidestep the class of Gujarati conjunct-rendering bugs
 * dart_pdf needed several rounds of fixes for.
 */
object PdfGenerator {

    const val PAGE_WIDTH = 595
    const val PAGE_HEIGHT = 842

    private const val FRAME_LEFT = 32f
    private const val FRAME_TOP = 32f
    private const val FRAME_RIGHT = 563f
    private const val FRAME_BOTTOM = 810f

    private const val CONTENT_LEFT = 46f
    private const val CONTENT_RIGHT = 549f
    private const val CONTENT_WIDTH = (CONTENT_RIGHT - CONTENT_LEFT).toInt()
    private const val CONTENT_TOP = 46f
    private const val CONTENT_BOTTOM = 776f

    private var lohitTypefaceRegular: Typeface? = null
    private var lohitTypefaceBold: Typeface? = null

    /** Loads Lohit Gujarati from the Flutter asset bundle (already declared in pubspec.yaml,
     * so no separate copy is needed under android/app/src/main/assets). */
    fun initLohitTypeface(context: Context) {
        if (lohitTypefaceRegular == null) {
            try {
                val tf = Typeface.createFromAsset(
                    context.assets,
                    "flutter_assets/assets/fonts/lohit_gujarati.ttf"
                )
                lohitTypefaceRegular = tf
                lohitTypefaceBold = Typeface.create(tf, Typeface.BOLD)
            } catch (e: Exception) {
                lohitTypefaceRegular = Typeface.DEFAULT
                lohitTypefaceBold = Typeface.DEFAULT_BOLD
            }
        }
    }

    private fun containsGujarati(text: CharSequence): Boolean {
        for (i in 0 until text.length) {
            val c = text[i]
            if (c in '઀'..'૿') return true
        }
        return false
    }

    private fun getTypefaceFor(text: CharSequence, isBold: Boolean = false): Typeface {
        return if (containsGujarati(text) && lohitTypefaceRegular != null) {
            if (isBold) (lohitTypefaceBold ?: Typeface.DEFAULT_BOLD) else (lohitTypefaceRegular ?: Typeface.DEFAULT)
        } else {
            if (isBold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
    }

    /**
     * Generates the descriptive-test PDF (Model Answer when [showAnswers], Question Paper text
     * otherwise) for the given questions, one language block per entry in [langCodes] that the
     * question actually has content for.
     */
    fun generateDescTestPdf(
        context: Context,
        questionGroups: List<QuestionGroup>,
        langCodes: List<String>,
        showAnswers: Boolean,
        testName: String,
        config: PdfConfig = PdfConfig()
    ): File {
        initLohitTypeface(context)
        val document = PdfDocument()
        val suffix = if (showAnswers) "ModelAnswer" else "QuestionPaper"
        val outputFile = File(context.cacheDir, "${sanitizeFileName(testName)}_Native_$suffix.pdf")

        var currentPageNumber = 0
        var currentY = CONTENT_TOP
        var currentPage: PdfDocument.Page? = null
        var currentCanvas: Canvas? = null

        fun startNewPage() {
            currentPage?.let { document.finishPage(it) }
            currentPageNumber++
            val pageInfo = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, currentPageNumber).create()
            val newPage = document.startPage(pageInfo)
            currentPage = newPage
            currentCanvas = newPage.canvas
            drawPageChrome(newPage.canvas, config)
            currentY = CONTENT_TOP
        }

        for (group in questionGroups) {
            startNewPage()
            val canvas = currentCanvas!!

            drawQuestionTopHeader(canvas, group.srNo, if (showAnswers) "Model Answer" else "Question Paper")
            currentY += 28f

            for ((index, langCode) in langCodes.withIndex()) {
                val content = group.byLanguage[langCode] ?: continue
                val langLabel = langCode.uppercase()

                drawTextElement(
                    getCurrentCanvas = { currentCanvas!! },
                    startNewPage = { startNewPage() },
                    getCurrentY = { currentY },
                    setCurrentY = { currentY = it },
                    spanned = makeBold("Question ($langLabel):"),
                    isHeading = true,
                    topSpacing = if (index == 0) 4f else 10f,
                    bottomSpacing = 4f
                )

                drawTextElement(
                    getCurrentCanvas = { currentCanvas!! },
                    startNewPage = { startNewPage() },
                    getCurrentY = { currentY },
                    setCurrentY = { currentY = it },
                    spanned = parseMarkdownToSpannable(content.question),
                    isHeading = false,
                    topSpacing = 2f,
                    bottomSpacing = 10f
                )

                if (showAnswers && content.answer.isNotEmpty()) {
                    drawTextElement(
                        getCurrentCanvas = { currentCanvas!! },
                        startNewPage = { startNewPage() },
                        getCurrentY = { currentY },
                        setCurrentY = { currentY = it },
                        spanned = makeBold("Model Answer ($langLabel):"),
                        isHeading = true,
                        topSpacing = 4f,
                        bottomSpacing = 6f
                    )

                    renderMarkdownBlocks(
                        getCurrentCanvas = { currentCanvas!! },
                        startNewPage = { startNewPage() },
                        getCurrentY = { currentY },
                        setCurrentY = { currentY = it },
                        markdownText = content.answer
                    )
                }
            }
        }

        currentPage?.let { document.finishPage(it) }

        FileOutputStream(outputFile).use { out -> document.writeTo(out) }
        document.close()

        return outputFile
    }

    private fun drawPageChrome(canvas: Canvas, config: PdfConfig) {
        if (config.showWatermark) {
            drawWatermark(canvas, config)
        }
        val borderPaint = Paint().apply {
            color = Color.BLACK
            style = Paint.Style.STROKE
            strokeWidth = 1.15f
            isAntiAlias = true
        }
        canvas.drawRect(FRAME_LEFT, FRAME_TOP, FRAME_RIGHT, FRAME_BOTTOM, borderPaint)
        drawPageFooter(canvas, config)
    }

    private fun drawWatermark(canvas: Canvas, config: PdfConfig) {
        val centerX = PAGE_WIDTH / 2f
        val centerY = PAGE_HEIGHT / 2f + 50f
        val alphaInt = (config.watermarkAlpha * 255).toInt().coerceIn(10, 80)

        val starTextPaint = Paint().apply {
            color = Color.argb(alphaInt, 120, 120, 120)
            textSize = 105f
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD_ITALIC)
            isAntiAlias = true
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(config.watermarkText, centerX - 18f, centerY, starTextPaint)

        val starIconPaint = Paint().apply {
            color = Color.argb(alphaInt, 130, 130, 130)
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        drawFivePointStar(canvas, centerX + 120f, centerY - 80f, 26f, starIconPaint)

        val subTextPaint = Paint().apply {
            color = Color.argb(alphaInt, 120, 120, 120)
            textSize = 34f
            typeface = Typeface.create(Typeface.SERIF, Typeface.ITALIC)
            isAntiAlias = true
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(config.watermarkSubText, centerX, centerY + 58f, subTextPaint)
    }

    private fun drawFivePointStar(canvas: Canvas, cx: Float, cy: Float, radius: Float, paint: Paint) {
        val path = Path()
        val innerRadius = radius * 0.42f
        for (i in 0 until 10) {
            val r = if (i % 2 == 0) radius else innerRadius
            val angle = Math.toRadians((i * 36 - 90).toDouble())
            val x = (cx + r * Math.cos(angle)).toFloat()
            val y = (cy + r * Math.sin(angle)).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        canvas.drawPath(path, paint)
    }

    private fun drawPageFooter(canvas: Canvas, config: PdfConfig) {
        val footerY = 799f
        var curX = CONTENT_LEFT

        val labelPaint = TextPaint().apply {
            color = Color.BLACK
            textSize = 8.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isAntiAlias = true
        }
        val labelText = "Click here to Join us:  "
        canvas.drawText(labelText, curX, footerY, labelPaint)
        curX += labelPaint.measureText(labelText) + 4f

        val linkPaint = TextPaint().apply {
            color = Color.parseColor("#2AABEE")
            textSize = 8.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            isAntiAlias = true
        }
        val sepPaint = TextPaint().apply {
            color = Color.parseColor("#777777")
            textSize = 8.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            isAntiAlias = true
        }

        val tgCirclePaint = Paint().apply {
            color = Color.parseColor("#2AABEE")
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        val tgY = footerY - 3f
        canvas.drawCircle(curX + 4.5f, tgY, 4.5f, tgCirclePaint)

        val planePaint = Paint().apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 1f
            isAntiAlias = true
        }
        val tgPath = Path().apply {
            moveTo(curX + 2.5f, tgY + 0.5f)
            lineTo(curX + 6.5f, tgY - 1.5f)
            lineTo(curX + 4.5f, tgY + 2.5f)
            close()
        }
        canvas.drawPath(tgPath, planePaint)
        curX += 13f

        canvas.drawText(config.telegramHandle, curX, footerY, linkPaint)
        curX += linkPaint.measureText(config.telegramHandle) + 14f

        canvas.drawText("|", curX, footerY, sepPaint)
        curX += 14f

        val gmailRect = RectF(curX, footerY - 7.5f, curX + 9f, footerY + 0.5f)
        val gmailBgPaint = Paint().apply {
            color = Color.parseColor("#EA4335")
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        canvas.drawRoundRect(gmailRect, 1.5f, 1.5f, gmailBgPaint)
        val mLetterPaint = Paint().apply {
            color = Color.WHITE
            textSize = 6.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            isAntiAlias = true
        }
        canvas.drawText("M", curX + 4.5f, footerY - 1f, mLetterPaint)
        curX += 13f

        canvas.drawText(config.emailContact, curX, footerY, linkPaint)
        curX += linkPaint.measureText(config.emailContact) + 14f

        canvas.drawText("|", curX, footerY, sepPaint)
        curX += 14f

        val xRect = RectF(curX, footerY - 7.5f, curX + 9f, footerY + 0.5f)
        val xBgPaint = Paint().apply {
            color = Color.BLACK
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        canvas.drawRoundRect(xRect, 1.5f, 1.5f, xBgPaint)
        val xLetterPaint = Paint().apply {
            color = Color.WHITE
            textSize = 6.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            isAntiAlias = true
        }
        canvas.drawText("X", curX + 4.5f, footerY - 1f, xLetterPaint)
        curX += 13f

        canvas.drawText(config.xHandle, curX, footerY, linkPaint)
    }

    private fun drawQuestionTopHeader(canvas: Canvas, srNo: Int, rightTitle: String) {
        val headerY = CONTENT_TOP + 12f

        val qTitlePaint = TextPaint().apply {
            color = Color.BLACK
            textSize = 13.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isAntiAlias = true
        }
        canvas.drawText("Question $srNo", CONTENT_LEFT, headerY, qTitlePaint)

        val rightPaint = TextPaint().apply {
            color = Color.parseColor("#444444")
            textSize = 11.5f
            typeface = Typeface.create(Typeface.SERIF, Typeface.ITALIC)
            isAntiAlias = true
            textAlign = Paint.Align.RIGHT
        }
        canvas.drawText(rightTitle, CONTENT_RIGHT, headerY, rightPaint)
    }

    private fun renderMarkdownBlocks(
        getCurrentCanvas: () -> Canvas,
        startNewPage: () -> Unit,
        getCurrentY: () -> Float,
        setCurrentY: (Float) -> Unit,
        markdownText: String
    ) {
        val lines = markdownText.split("\n")
        var i = 0

        while (i < lines.size) {
            val rawLine = lines[i].trim()
            if (rawLine.isEmpty()) {
                i++
                continue
            }

            if (isHeadingLine(rawLine)) {
                val cleanHeading = cleanMarkdownHeading(rawLine)
                drawTextElement(
                    getCurrentCanvas = getCurrentCanvas,
                    startNewPage = startNewPage,
                    getCurrentY = getCurrentY,
                    setCurrentY = setCurrentY,
                    spanned = makeBold(cleanHeading),
                    isHeading = true,
                    topSpacing = 8f,
                    bottomSpacing = 4f
                )
                i++
                continue
            }

            if (rawLine.startsWith("- ") || rawLine.startsWith("* ")) {
                val bulletContent = rawLine.substring(2).trim()
                val spanned = parseMarkdownToSpannable(bulletContent)

                drawBulletElement(
                    getCurrentCanvas = getCurrentCanvas,
                    startNewPage = startNewPage,
                    getCurrentY = getCurrentY,
                    setCurrentY = setCurrentY,
                    bulletSpanned = spanned
                )
                i++
                continue
            }

            val paragraphBuilder = StringBuilder(rawLine)
            while (i + 1 < lines.size) {
                val nextLine = lines[i + 1].trim()
                if (nextLine.isEmpty() || isHeadingLine(nextLine) || nextLine.startsWith("- ") || nextLine.startsWith("* ")) {
                    break
                }
                paragraphBuilder.append(" ").append(nextLine)
                i++
            }

            val paragraphText = paragraphBuilder.toString()
            val spanned = parseMarkdownToSpannable(paragraphText)

            drawTextElement(
                getCurrentCanvas = getCurrentCanvas,
                startNewPage = startNewPage,
                getCurrentY = getCurrentY,
                setCurrentY = setCurrentY,
                spanned = spanned,
                isHeading = false,
                topSpacing = 2f,
                bottomSpacing = 6f
            )

            i++
        }
    }

    private fun drawBulletElement(
        getCurrentCanvas: () -> Canvas,
        startNewPage: () -> Unit,
        getCurrentY: () -> Float,
        setCurrentY: (Float) -> Unit,
        bulletSpanned: CharSequence
    ) {
        val indent = 16f
        val textWidth = (CONTENT_WIDTH - indent).toInt()

        val textPaint = TextPaint().apply {
            color = Color.BLACK
            textSize = 10f
            typeface = getTypefaceFor(bulletSpanned, isBold = false)
            isAntiAlias = true
        }

        val layout = StaticLayout.Builder.obtain(bulletSpanned, 0, bulletSpanned.length, textPaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(2f, 1.15f)
            .setIncludePad(false)
            .build()

        val layoutHeight = layout.height.toFloat()
        var currentY = getCurrentY()

        if (currentY + layoutHeight > CONTENT_BOTTOM) {
            startNewPage()
            currentY = CONTENT_TOP
        }

        val canvas = getCurrentCanvas()

        val bulletPaint = Paint().apply {
            color = Color.BLACK
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            isAntiAlias = true
        }
        canvas.drawText("•", CONTENT_LEFT + 2f, currentY + 9f, bulletPaint)

        canvas.save()
        canvas.translate(CONTENT_LEFT + indent, currentY)
        layout.draw(canvas)
        canvas.restore()

        setCurrentY(currentY + layoutHeight + 4f)
    }

    private fun drawTextElement(
        getCurrentCanvas: () -> Canvas,
        startNewPage: () -> Unit,
        getCurrentY: () -> Float,
        setCurrentY: (Float) -> Unit,
        spanned: CharSequence,
        isHeading: Boolean,
        topSpacing: Float,
        bottomSpacing: Float
    ) {
        val textPaint = TextPaint().apply {
            color = Color.BLACK
            textSize = if (isHeading) 11.5f else 10f
            typeface = getTypefaceFor(spanned, isBold = isHeading)
            isAntiAlias = true
        }

        var currentY = getCurrentY() + topSpacing

        val layout = StaticLayout.Builder.obtain(spanned, 0, spanned.length, textPaint, CONTENT_WIDTH)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(2f, if (isHeading) 1.1f else 1.18f)
            .setIncludePad(false)
            .build()

        val totalHeight = layout.height.toFloat()

        if (currentY + totalHeight <= CONTENT_BOTTOM) {
            val canvas = getCurrentCanvas()
            canvas.save()
            canvas.translate(CONTENT_LEFT, currentY)
            layout.draw(canvas)
            canvas.restore()
            setCurrentY(currentY + totalHeight + bottomSpacing)
            return
        }

        if (isHeading) {
            startNewPage()
            currentY = CONTENT_TOP + topSpacing
            val canvas = getCurrentCanvas()
            canvas.save()
            canvas.translate(CONTENT_LEFT, currentY)
            layout.draw(canvas)
            canvas.restore()
            setCurrentY(currentY + totalHeight + bottomSpacing)
            return
        }

        var lineStart = 0
        var availableHeight = CONTENT_BOTTOM - currentY

        while (lineStart < layout.lineCount) {
            var lineEnd = lineStart
            while (lineEnd < layout.lineCount && (layout.getLineBottom(lineEnd) - layout.getLineTop(lineStart)) <= availableHeight) {
                lineEnd++
            }

            if (lineEnd == lineStart) {
                startNewPage()
                currentY = CONTENT_TOP
                availableHeight = CONTENT_BOTTOM - currentY
                continue
            }

            val startChar = layout.getLineStart(lineStart)
            val endChar = layout.getLineEnd(lineEnd - 1)
            val chunk = spanned.subSequence(startChar, endChar)

            val chunkLayout = StaticLayout.Builder.obtain(chunk, 0, chunk.length, textPaint, CONTENT_WIDTH)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setLineSpacing(2f, 1.18f)
                .setIncludePad(false)
                .build()

            val canvas = getCurrentCanvas()
            canvas.save()
            canvas.translate(CONTENT_LEFT, currentY)
            chunkLayout.draw(canvas)
            canvas.restore()

            currentY += chunkLayout.height.toFloat()

            lineStart = lineEnd
            if (lineStart < layout.lineCount) {
                startNewPage()
                currentY = CONTENT_TOP
                availableHeight = CONTENT_BOTTOM - currentY
            }
        }

        setCurrentY(currentY + bottomSpacing)
    }

    fun parseMarkdownToSpannable(raw: CharSequence): SpannableStringBuilder {
        val s = raw.toString()
        val builder = SpannableStringBuilder()

        var i = 0
        val len = s.length

        while (i < len) {
            if (i + 1 < len && s[i] == '*' && s[i + 1] == '*') {
                val end = s.indexOf("**", i + 2)
                if (end != -1) {
                    val boldText = s.substring(i + 2, end)
                    val startIdx = builder.length
                    builder.append(boldText)
                    builder.setSpan(
                        StyleSpan(Typeface.BOLD),
                        startIdx,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    i = end + 2
                    continue
                }
            } else if (s[i] == '*' && (i + 1 >= len || s[i + 1] != '*')) {
                val end = s.indexOf('*', i + 1)
                if (end != -1 && (end + 1 >= len || s[end + 1] != '*')) {
                    val italicText = s.substring(i + 1, end)
                    val startIdx = builder.length
                    builder.append(italicText)
                    builder.setSpan(
                        StyleSpan(Typeface.ITALIC),
                        startIdx,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    i = end + 1
                    continue
                }
            }

            builder.append(s[i])
            i++
        }

        return builder
    }

    private fun makeBold(text: String): SpannableStringBuilder {
        val s = SpannableStringBuilder(text)
        s.setSpan(StyleSpan(Typeface.BOLD), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return s
    }

    private fun isHeadingLine(line: String): Boolean {
        val trimmed = line.trim()
        if (trimmed.startsWith("###") || trimmed.startsWith("##") || trimmed.startsWith("#")) return true
        if (trimmed.startsWith("**") && trimmed.endsWith("**") && trimmed.length > 4 && !trimmed.contains("\n")) {
            val inner = trimmed.substring(2, trimmed.length - 2)
            return !inner.contains("**")
        }
        return false
    }

    private fun cleanMarkdownHeading(line: String): String {
        var t = line.trim()
        if (t.startsWith("###")) t = t.substring(3).trim()
        else if (t.startsWith("##")) t = t.substring(2).trim()
        else if (t.startsWith("#")) t = t.substring(1).trim()

        if (t.startsWith("**") && t.endsWith("**") && t.length >= 4) {
            t = t.substring(2, t.length - 2).trim()
        }
        return t
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[^a-zA-Z0-9_-]"), "_").take(30)
    }
}
