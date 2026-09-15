package com.starics.pdf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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

    private val logoBitmaps = mutableMapOf<String, Bitmap?>()

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

    /** Loads (and caches) the real logo/social-icon PNGs from the Flutter asset bundle -- the
     * same files desc_pdf_download.dart's dart_pdf footer uses -- instead of hand-drawn
     * approximations, so both generators produce visually consistent output. */
    private fun getLogoBitmap(context: Context, assetName: String): Bitmap? {
        return logoBitmaps.getOrPut(assetName) {
            try {
                context.assets.open("flutter_assets/assets/images/$assetName").use { input ->
                    BitmapFactory.decodeStream(input)
                }
            } catch (e: Exception) {
                null
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
        // 1-based page number -> its footer link rects, in PDF (Y-up) space, for the
        // incremental-update annotator to turn into real clickable links after writeTo().
        val linkRectsByPage = mutableMapOf<Int, List<LinkRect>>()

        fun startNewPage() {
            currentPage?.let { document.finishPage(it) }
            currentPageNumber++
            val pageInfo = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, currentPageNumber).create()
            val newPage = document.startPage(pageInfo)
            currentPage = newPage
            currentCanvas = newPage.canvas
            val footerLinks = drawPageChrome(context, newPage.canvas, config)
            linkRectsByPage[currentPageNumber] = footerLinks.map {
                // Canvas space is Y-down from the top; PDF page space is Y-up from the
                // bottom, so flip both edges and keep them ordered bottom < top.
                LinkRect(
                    left = it.left,
                    top = PAGE_HEIGHT - it.top,
                    right = it.right,
                    bottom = PAGE_HEIGHT - it.bottom,
                    uri = it.uri
                )
            }
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

        // android.graphics.pdf.PdfDocument has no API for link annotations, so make the
        // footer's social links actually clickable via a manual incremental PDF update.
        try {
            PdfLinkAnnotator.addLinks(outputFile, linkRectsByPage)
        } catch (e: Exception) {
            // Non-fatal: worst case the footer text/icons are visible but not clickable.
        }

        return outputFile
    }

    private fun drawPageChrome(context: Context, canvas: Canvas, config: PdfConfig): List<LinkRect> {
        if (config.showWatermark) {
            drawWatermark(context, canvas, config)
        }
        val borderPaint = Paint().apply {
            color = Color.BLACK
            style = Paint.Style.STROKE
            strokeWidth = 1.15f
            isAntiAlias = true
        }
        canvas.drawRect(FRAME_LEFT, FRAME_TOP, FRAME_RIGHT, FRAME_BOTTOM, borderPaint)
        return drawPageFooter(context, canvas, config)
    }

    /** Draws the actual Star logo (assets/images/logo_without_bg.png) at low opacity,
     * contained within the bordered frame -- matching dart_pdf's
     * `pw.Opacity(opacity: 0.1, child: pw.Image(logoImage, fit: BoxFit.contain))` -- instead
     * of a hand-drawn approximation. */
    private fun drawWatermark(context: Context, canvas: Canvas, config: PdfConfig) {
        val bitmap = getLogoBitmap(context, "logo_without_bg.png") ?: return
        val alphaInt = (config.watermarkAlpha * 255).toInt().coerceIn(10, 80)

        val boxLeft = FRAME_LEFT + 16f
        val boxTop = FRAME_TOP + 16f
        val boxRight = FRAME_RIGHT - 16f
        val boxBottom = FRAME_BOTTOM - 16f
        val boxWidth = boxRight - boxLeft
        val boxHeight = boxBottom - boxTop

        val scale = minOf(boxWidth / bitmap.width, boxHeight / bitmap.height)
        val drawWidth = bitmap.width * scale
        val drawHeight = bitmap.height * scale
        val left = boxLeft + (boxWidth - drawWidth) / 2f
        val top = boxTop + (boxHeight - drawHeight) / 2f

        val paint = Paint().apply {
            isAntiAlias = true
            isFilterBitmap = true
            alpha = alphaInt
        }
        val destRect = RectF(left, top, left + drawWidth, top + drawHeight)
        canvas.drawBitmap(bitmap, null, destRect, paint)
    }

    /** Draws the footer using the real social-icon PNGs (assets/images/telegram_logo.png,
     * gmail_logo.png, x_logo.png) at the same 10x10pt size dart_pdf uses, and returns the
     * clickable regions (icon + handle) for the caller to turn into real link annotations --
     * android.graphics.pdf.PdfDocument has no built-in way to add those itself. */
    private fun drawPageFooter(context: Context, canvas: Canvas, config: PdfConfig): List<LinkRect> {
        val footerY = 799f
        var curX = CONTENT_LEFT
        val links = mutableListOf<LinkRect>()

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
        val iconPaint = Paint().apply {
            isAntiAlias = true
            isFilterBitmap = true
        }

        // Telegram
        val telegramLogo = getLogoBitmap(context, "telegram_logo.png")
        val tgIconTop = footerY - 7.5f
        val tgLinkStart = curX
        if (telegramLogo != null) {
            val dest = RectF(curX, tgIconTop, curX + 10f, tgIconTop + 10f)
            canvas.drawBitmap(telegramLogo, null, dest, iconPaint)
        }
        curX += 14f
        canvas.drawText(config.telegramHandle, curX, footerY, linkPaint)
        curX += linkPaint.measureText(config.telegramHandle)
        links.add(LinkRect(tgLinkStart, tgIconTop, curX, footerY + 2f, "https://t.me/starics_prep"))
        curX += 14f

        canvas.drawText("|", curX, footerY, sepPaint)
        curX += 14f

        // Gmail
        val gmailLogo = getLogoBitmap(context, "gmail_logo.png")
        val gmailIconTop = footerY - 7.5f
        val gmailLinkStart = curX
        if (gmailLogo != null) {
            val dest = RectF(curX, gmailIconTop, curX + 10f, gmailIconTop + 10f)
            canvas.drawBitmap(gmailLogo, null, dest, iconPaint)
        }
        curX += 14f
        canvas.drawText(config.emailContact, curX, footerY, linkPaint)
        curX += linkPaint.measureText(config.emailContact)
        links.add(
            LinkRect(
                gmailLinkStart,
                gmailIconTop,
                curX,
                footerY + 2f,
                "mailto:${config.emailContact}"
            )
        )
        curX += 14f

        canvas.drawText("|", curX, footerY, sepPaint)
        curX += 14f

        // X / Twitter
        val xLogo = getLogoBitmap(context, "x_logo.png")
        val xIconTop = footerY - 7.5f
        val xLinkStart = curX
        if (xLogo != null) {
            val dest = RectF(curX, xIconTop, curX + 10f, xIconTop + 10f)
            canvas.drawBitmap(xLogo, null, dest, iconPaint)
        }
        curX += 14f
        canvas.drawText(config.xHandle, curX, footerY, linkPaint)
        curX += linkPaint.measureText(config.xHandle)
        links.add(LinkRect(xLinkStart, xIconTop, curX, footerY + 2f, "https://x.com/star_ics89"))

        return links
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
