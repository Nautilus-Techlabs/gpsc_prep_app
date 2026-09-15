package com.starics.pdf

import java.io.File
import java.nio.charset.Charset
import java.util.Locale

/**
 * Makes regions of an android.graphics.pdf.PdfDocument-generated PDF clickable by appending
 * real `/Annot /Subtype /Link` objects, via a standard PDF "incremental update": new objects
 * plus a new xref section referencing them are appended after the file's existing content and
 * `%%EOF`, with `/Prev` pointing back at the original xref. PdfDocument's own Canvas API has no
 * way to add link annotations itself, so this is a necessary post-processing step.
 *
 * This targets the specific (well-formed, classic-xref-table) structure Android's Skia-based
 * PdfDocument is known to emit -- not a general-purpose PDF editor.
 */
object PdfLinkAnnotator {

    // PDF text is scanned/rewritten as ISO-8859-1 so every byte (including inside compressed
    // streams, which are never touched, only skipped over) round-trips 1:1 through the String.
    private val PDF_CHARSET: Charset = Charsets.ISO_8859_1

    fun addLinks(file: File, linkRectsByPage: Map<Int, List<LinkRect>>) {
        val relevantPages = linkRectsByPage.filterValues { it.isNotEmpty() }
        if (relevantPages.isEmpty()) return

        val original = file.readBytes()
        val text = String(original, PDF_CHARSET)

        val size = parseTrailerSize(text) ?: return
        val rootNum = parseTrailerRoot(text) ?: return
        val prevXrefOffset = parseStartXref(text) ?: return

        val pagesRootNum = parseRef(text, objectBody(text, rootNum) ?: return, "/Pages") ?: return
        val pageObjNums = mutableListOf<Int>()
        collectPageObjectNumbers(text, pagesRootNum, pageObjNums)
        if (pageObjNums.isEmpty()) return

        var nextObjNum = size
        val appended = StringBuilder()
        val newOffsets = sortedMapOf<Int, Long>() // objNum -> byte offset in the final file
        var writeOffset = original.size.toLong()

        fun appendObject(objNum: Int, body: String) {
            val objText = "$objNum 0 obj\n$body\nendobj\n"
            newOffsets[objNum] = writeOffset
            appended.append(objText)
            writeOffset += objText.toByteArray(PDF_CHARSET).size
        }

        for ((pageIndex, pageObjNum) in pageObjNums.withIndex()) {
            val pageNumber = pageIndex + 1
            val rects = relevantPages[pageNumber] ?: continue

            val annotRefs = mutableListOf<Int>()
            for (rect in rects) {
                val annotNum = nextObjNum++
                val body = buildLinkAnnotBody(rect)
                appendObject(annotNum, body)
                annotRefs.add(annotNum)
            }

            val originalPageBody = objectBody(text, pageObjNum) ?: continue
            val annotsArray = annotRefs.joinToString(" ") { "$it 0 R" }
            val updatedPageBody = insertAnnots(originalPageBody, annotsArray)
            appendObject(pageObjNum, updatedPageBody)
        }

        if (newOffsets.isEmpty()) return

        val newXrefOffset = writeOffset
        val xrefText = buildXref(newOffsets)
        val newSize = nextObjNum
        val trailerText = "trailer\n<</Size $newSize/Root $rootNum 0 R/Prev $prevXrefOffset>>\nstartxref\n$newXrefOffset\n%%EOF\n"

        val finalText = buildString {
            append(text)
            append(appended)
            append(xrefText)
            append(trailerText)
        }

        file.writeBytes(finalText.toByteArray(PDF_CHARSET))
    }

    private fun escapePdfString(s: String): String {
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    }

    private fun buildLinkAnnotBody(rect: LinkRect): String {
        val llx = fmt(rect.left)
        val lly = fmt(rect.bottom)
        val urx = fmt(rect.right)
        val ury = fmt(rect.top)
        val uri = escapePdfString(rect.uri)
        return "<</Type /Annot/Subtype /Link/Rect [$llx $lly $urx $ury]/Border [0 0 0]" +
            "/A <</Type /Action/S /URI/URI ($uri)>>>>"
    }

    private fun fmt(v: Float): String = String.format(Locale.US, "%.2f", v)

    /** Inserts `/Annots [...]` just before the dict's final closing `>>` (the outermost one,
     * which -- for a well-formed single-dict page object -- is always the last `>>` in the
     * body, even though /Resources etc. contain their own nested `<<...>>` pairs earlier). */
    private fun insertAnnots(originalBody: String, annotsArray: String): String {
        val lastClose = originalBody.lastIndexOf(">>")
        require(lastClose >= 0) { "Page object has no closing >>" }
        return originalBody.substring(0, lastClose) + "/Annots [$annotsArray]" +
            originalBody.substring(lastClose)
    }

    /** Returns the `<<...>>` dictionary body (without the leading "N 0 obj" / trailing
     * "endobj") for the given object number, or null if not found. */
    private fun objectBody(text: String, objNum: Int): String? {
        val objRegex = Regex("(?m)(?<![0-9])$objNum\\s+0\\s+obj\\b")
        val match = objRegex.find(text) ?: return null
        val start = text.indexOf("<<", match.range.last)
        if (start < 0) return null
        val end = findMatchingDictEnd(text, start)
        if (end < 0) return null
        return text.substring(start, end)
    }

    /** Finds the index right after the `>>` that closes the `<<` at [start], accounting for
     * nested dictionaries. */
    private fun findMatchingDictEnd(text: String, start: Int): Int {
        var depth = 0
        var i = start
        while (i < text.length - 1) {
            if (text[i] == '<' && text[i + 1] == '<') {
                depth++
                i += 2
                continue
            }
            if (text[i] == '>' && text[i + 1] == '>') {
                depth--
                i += 2
                if (depth == 0) return i
                continue
            }
            i++
        }
        return -1
    }

    private fun parseRef(text: String, dictBody: String, key: String): Int? {
        val m = Regex(Regex.escape(key) + "\\s+(\\d+)\\s+0\\s+R").find(dictBody) ?: return null
        return m.groupValues[1].toIntOrNull()
    }

    /** Recursively walks a /Pages (or /Page) node's /Kids to collect leaf page object numbers
     * in document order. */
    private fun collectPageObjectNumbers(text: String, objNum: Int, out: MutableList<Int>) {
        val body = objectBody(text, objNum) ?: return
        val kidsMatch = Regex("/Kids\\s*\\[([^\\]]*)\\]").find(body)
        if (kidsMatch == null) {
            out.add(objNum)
            return
        }
        val refs = Regex("(\\d+)\\s+0\\s+R").findAll(kidsMatch.groupValues[1])
        for (ref in refs) {
            collectPageObjectNumbers(text, ref.groupValues[1].toInt(), out)
        }
    }

    private fun parseTrailerSize(text: String): Int? {
        val trailerIdx = text.lastIndexOf("trailer")
        if (trailerIdx < 0) return null
        val m = Regex("/Size\\s+(\\d+)").find(text, trailerIdx) ?: return null
        return m.groupValues[1].toIntOrNull()
    }

    private fun parseTrailerRoot(text: String): Int? {
        val trailerIdx = text.lastIndexOf("trailer")
        if (trailerIdx < 0) return null
        val m = Regex("/Root\\s+(\\d+)\\s+0\\s+R").find(text, trailerIdx) ?: return null
        return m.groupValues[1].toIntOrNull()
    }

    private fun parseStartXref(text: String): Long? {
        val idx = text.lastIndexOf("startxref")
        if (idx < 0) return null
        val m = Regex("(\\d+)").find(text, idx + "startxref".length) ?: return null
        return m.groupValues[1].toLongOrNull()
    }

    /** Builds one or more xref subsections (grouping contiguous object numbers together, as
     * classic xref tables require) covering exactly the given new/updated objects. */
    private fun buildXref(offsets: Map<Int, Long>): String {
        val nums = offsets.keys.sorted()
        val sb = StringBuilder("xref\n")
        var i = 0
        while (i < nums.size) {
            var j = i
            while (j + 1 < nums.size && nums[j + 1] == nums[j] + 1) j++
            val first = nums[i]
            val count = j - i + 1
            sb.append("$first $count\n")
            for (k in i..j) {
                val offset = offsets.getValue(nums[k])
                sb.append(String.format(Locale.US, "%010d 00000 n \n", offset))
            }
            i = j + 1
        }
        return sb.toString()
    }
}
