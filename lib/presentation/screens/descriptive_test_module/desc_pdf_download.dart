import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gpsc_prep_app/core/di/di.dart';
import 'package:gpsc_prep_app/core/helpers/log_helper.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:gpsc_prep_app/presentation/screens/preview_screen/pdf_export_service.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_file_manager/open_file_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<String> generateDescTestPdf(
  DescQuestionModel question,
  int index,
  String testName,
  List<String> langCodes, {
  bool showAnswers = true,
}) async {
  final base = await rootBundle.load("assets/fonts/ArialUnicodeMs.otf");
  final baseFont = pw.Font.ttf(base);
  final gujaratiFontData = await rootBundle.load(
    "assets/fonts/lohit_gujarati.ttf",
  );
  final gujaratiFont = pw.Font.ttf(gujaratiFontData);

  final pdf = pw.Document(
    pageMode: PdfPageMode.fullscreen,
    theme: pw.ThemeData.withFont(
      base: baseFont,
      fontFallback: [baseFont, pw.Font.symbol()],
    ),
  );

  // Load logo
  final logoData = await rootBundle.load('assets/images/logo_without_bg.png');
  final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

  final telegramLogo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/images/telegram_logo.png',
    )).buffer.asUint8List(),
  );
  final gmailLogo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/images/gmail_logo.png',
    )).buffer.asUint8List(),
  );
  final xLogo = pw.MemoryImage(
    (await rootBundle.load('assets/images/x_logo.png')).buffer.asUint8List(),
  );

  pw.Widget borderedPage(pw.Widget child) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      padding: const pw.EdgeInsets.all(16),
      child: child,
    );
  }

  // --- Page 1 ---
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return borderedPage(
          pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.1,
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Question $index",
                        style: pw.TextStyle(
                          fontSize: 12.sp,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        showAnswers ? "Model Answer" : "Question Paper",
                        style: pw.TextStyle(
                          fontSize: 10.sp,
                          color: PdfColors.grey700,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  for (int i = 0; i < langCodes.length; i++) ...[
                    if (i > 0) pw.SizedBox(height: 10),
                    if (langCodes[i] == 'en') ...[
                      pw.Text(
                        "Question (EN):",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      ..._parseMarkdownToPdfWidgets(
                        question.questionEn.questionTxt,
                        baseFont,
                        gujaratiFont,
                      ),
                      if (showAnswers &&
                          question.questionEn.answerTxt.isNotEmpty) ...[
                        pw.SizedBox(height: 10),
                        pw.Text(
                          "Model Answer (EN):",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        ..._parseMarkdownToPdfWidgets(
                          question.questionEn.answerTxt,
                          baseFont,
                          gujaratiFont,
                        ),
                      ],
                    ],
                    if (langCodes[i] == 'hi' &&
                        question.questionHi?.questionTxt != null &&
                        question.questionHi!.questionTxt.isNotEmpty) ...[
                      pw.Text(
                        "Question (HI):",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      ..._parseMarkdownToPdfWidgets(
                        question.questionHi!.questionTxt,
                        baseFont,
                        gujaratiFont,
                      ),
                      if (showAnswers &&
                          question.questionHi!.answerTxt.isNotEmpty) ...[
                        pw.SizedBox(height: 10),
                        pw.Text(
                          "Model Answer (HI):",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        ..._parseMarkdownToPdfWidgets(
                          question.questionHi!.answerTxt,
                          baseFont,
                          gujaratiFont,
                        ),
                      ],
                    ],
                    if (langCodes[i] == 'gj' &&
                        question.questionGj?.questionTxt != null &&
                        question.questionGj!.questionTxt.isNotEmpty) ...[
                      pw.Text(
                        "Question (GJ):",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      ..._parseMarkdownToPdfWidgets(
                        question.questionGj!.questionTxt,
                        baseFont,
                        gujaratiFont,
                      ),
                      if (showAnswers &&
                          question.questionGj!.answerTxt.isNotEmpty) ...[
                        pw.SizedBox(height: 10),
                        pw.Text(
                          "Model Answer (GJ):",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        ..._parseMarkdownToPdfWidgets(
                          question.questionGj!.answerTxt,
                          baseFont,
                          gujaratiFont,
                        ),
                      ],
                    ],
                  ],
                ],
              ),
              // --- Footer ---
              pw.Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: pw.Container(
                  alignment: pw.Alignment.center,
                  margin: const pw.EdgeInsets.only(top: 10),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      pw.Text(
                        'Click here to Join us:',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Row(
                        children: [
                          pw.Image(telegramLogo, width: 10, height: 10),
                          pw.SizedBox(width: 4),
                          pw.UrlLink(
                            destination: 'https://t.me/starics_prep',
                            child: pw.Text(
                              '@starics_prep',
                              style: pw.TextStyle(
                                color: PdfColors.blue,
                                decoration: pw.TextDecoration.underline,
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
                      pw.Row(
                        children: [
                          pw.Image(gmailLogo, width: 10, height: 10),
                          pw.SizedBox(width: 4),
                          pw.UrlLink(
                            destination: 'mailto:star.ics89@gmail.com',
                            child: pw.Text(
                              'star.ics89@gmail.com',
                              style: pw.TextStyle(
                                color: PdfColors.blue,
                                decoration: pw.TextDecoration.underline,
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
                      pw.Row(
                        children: [
                          pw.Image(xLogo, width: 10, height: 10),
                          pw.SizedBox(width: 4),
                          pw.UrlLink(
                            destination: 'https://x.com/star_ics89',
                            child: pw.Text(
                              '@star_ics89',
                              style: pw.TextStyle(
                                color: PdfColors.blue,
                                decoration: pw.TextDecoration.underline,
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  // --- Extra pages ---
  if (!showAnswers) {
    for (int i = 1; i < (question.pages ?? 1); i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return borderedPage(
              pw.Stack(
                children: [
                  pw.Center(
                    child: pw.Opacity(
                      opacity: 0.1,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                  // Footer reused
                  pw.Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: pw.Container(
                      alignment: pw.Alignment.center,
                      margin: const pw.EdgeInsets.only(top: 10),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                        children: [
                          pw.Text(
                            'Click here to Join us:',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Row(
                            children: [
                              pw.Image(telegramLogo, width: 10, height: 10),
                              pw.SizedBox(width: 4),
                              pw.UrlLink(
                                destination: 'https://t.me/starics_prep',
                                child: pw.Text(
                                  '@starics_prep',
                                  style: pw.TextStyle(
                                    color: PdfColors.blue,
                                    decoration: pw.TextDecoration.underline,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
                          pw.Row(
                            children: [
                              pw.Image(gmailLogo, width: 10, height: 10),
                              pw.SizedBox(width: 4),
                              pw.UrlLink(
                                destination: 'mailto:star.ics89@gmail.com',
                                child: pw.Text(
                                  'star.ics89@gmail.com',
                                  style: pw.TextStyle(
                                    color: PdfColors.blue,
                                    decoration: pw.TextDecoration.underline,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
                          pw.Row(
                            children: [
                              pw.Image(xLogo, width: 10, height: 10),
                              pw.SizedBox(width: 4),
                              pw.UrlLink(
                                destination: 'https://x.com/star_ics89',
                                child: pw.Text(
                                  '@star_ics89',
                                  style: pw.TextStyle(
                                    color: PdfColors.blue,
                                    decoration: pw.TextDecoration.underline,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
  }

  // --- Save PDF ---
  final bytes = await pdf.save();
  final suffix = showAnswers ? "ModelAnswer" : "QuestionPaper";
  final safeFileName =
      "${testName.toSafeFileName()}_Question${index}_$suffix.pdf";
  String filePath;

  try {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // ✅ Android 10+ (Scoped Storage)
      if (sdkInt >= 29) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = "${tempDir.path}/$safeFileName";
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes);

        final mediaStore = MediaStore();
        MediaStore.appFolder = "StarICS";

        final saveInfo = await mediaStore.saveFile(
          tempFilePath: tempPath,
          dirType: DirType.download,
          dirName: DirName.download,
          relativePath: "StarICS/",
        );

        if (saveInfo == null) {
          throw Exception("Failed to save PDF to MediaStore");
        }

        String? realPath;
        try {
          realPath = await mediaStore.getFilePathFromUri(
            uriString: saveInfo.uri.toString(),
          );
        } catch (e) {
          getIt<LogHelper>().e("Could not resolve file path: $e");
        }

        if (realPath != null && await File(realPath).exists()) {
          filePath = realPath;
          await openFileManager(
            androidConfig: AndroidConfig(
              folderPath: realPath,
              folderType: AndroidFolderType.download,
            ),
          );
        } else {
          filePath = saveInfo.uri.toString();
          await openFileManager(
            androidConfig: AndroidConfig(
              folderPath: filePath,
              folderType: AndroidFolderType.download,
            ),
          );
        }
        return filePath;
      } else {
        // ✅ Android 9 and below – direct /Download/StarICS
        final downloadsDir = Directory("/storage/emulated/0/Download/StarICS");
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        filePath = "${downloadsDir.path}/$safeFileName";
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await openFileManager(
          androidConfig: AndroidConfig(
            folderPath: filePath,
            folderType: AndroidFolderType.download,
          ),
        );
        return filePath;
      }
    } else {
      // ✅ iOS or other platforms
      final dir = await getApplicationDocumentsDirectory();
      filePath = "${dir.path}/$safeFileName";
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await openFileManager(
        androidConfig: AndroidConfig(
          folderPath: filePath,
          folderType: AndroidFolderType.download,
        ),
      );
      return filePath;
    }
  } catch (e) {
    getIt<LogHelper>().e("Error generating Desc PDF: $e");
    final fallbackDir = await getTemporaryDirectory();
    filePath = "${fallbackDir.path}/$safeFileName";
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }
}

Future<String> generateFullDescTestPdf(
  List<DescQuestionModel> questions,
  String testName,
  List<String> langCodes, {
  bool showAnswers = true,
}) async {
  final base = await rootBundle.load("assets/fonts/ArialUnicodeMs.otf");
  final baseFont = pw.Font.ttf(base);
  final gujaratiFontData = await rootBundle.load(
    "assets/fonts/lohit_gujarati.ttf",
  );
  final gujaratiFont = pw.Font.ttf(gujaratiFontData);

  final pdf = pw.Document(
    pageMode: PdfPageMode.fullscreen,
    theme: pw.ThemeData.withFont(
      base: baseFont,
      fontFallback: [baseFont, pw.Font.symbol()],
    ),
  );

  // Load logo
  final logoData = await rootBundle.load('assets/images/logo_without_bg.png');
  final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

  final telegramLogo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/images/telegram_logo.png',
    )).buffer.asUint8List(),
  );
  final gmailLogo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/images/gmail_logo.png',
    )).buffer.asUint8List(),
  );
  final xLogo = pw.MemoryImage(
    (await rootBundle.load('assets/images/x_logo.png')).buffer.asUint8List(),
  );

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(left: 32, top: 32, right: 32, bottom: 40),
    buildBackground: (context) {
      return pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          margin: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
          child: pw.Center(
            child: pw.Opacity(
              opacity: 0.1,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ),
        ),
      );
    },
  );

  pw.Widget buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 10, bottom: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          pw.Text(
            'Click here to Join us:',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.Row(
            children: [
              pw.Image(telegramLogo, width: 10, height: 10),
              pw.SizedBox(width: 4),
              pw.UrlLink(
                destination: 'https://t.me/starics_prep',
                child: pw.Text(
                  '@starics_prep',
                  style: pw.TextStyle(
                    color: PdfColors.blue,
                    decoration: pw.TextDecoration.underline,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
          pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
          pw.Row(
            children: [
              pw.Image(gmailLogo, width: 10, height: 10),
              pw.SizedBox(width: 4),
              pw.UrlLink(
                destination: 'mailto:star.ics89@gmail.com',
                child: pw.Text(
                  'star.ics89@gmail.com',
                  style: pw.TextStyle(
                    color: PdfColors.blue,
                    decoration: pw.TextDecoration.underline,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
          pw.Text('|', style: pw.TextStyle(fontSize: 9.5)),
          pw.Row(
            children: [
              pw.Image(xLogo, width: 10, height: 10),
              pw.SizedBox(width: 4),
              pw.UrlLink(
                destination: 'https://x.com/star_ics89',
                child: pw.Text(
                  '@star_ics89',
                  style: pw.TextStyle(
                    color: PdfColors.blue,
                    decoration: pw.TextDecoration.underline,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<pw.Widget> currentWidgets = [];

  for (int i = 0; i < questions.length; i++) {
    final question = questions[i];
    final index = i + 1;

    currentWidgets.addAll([
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "Question $index",
            style: pw.TextStyle(
              fontSize: 12.sp,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            showAnswers ? "Model Answer" : "Question Paper",
            style: pw.TextStyle(
              fontSize: 10.sp,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      // Add question text based on selected languages
      for (int k = 0; k < langCodes.length; k++) ...[
        if (k > 0) pw.SizedBox(height: 10),
        if (langCodes[k] == 'en') ...[
          pw.Text(
            "Question (EN):",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          ..._parseMarkdownToPdfWidgets(
            question.questionEn.questionTxt,
            baseFont,
            gujaratiFont,
          ),
          if (showAnswers &&
              question.questionEn.answerTxt.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              "Model Answer (EN):",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ..._parseMarkdownToPdfWidgets(
              question.questionEn.answerTxt,
              baseFont,
              gujaratiFont,
            ),
          ],
        ],
        if (langCodes[k] == 'hi' &&
            question.questionHi?.questionTxt != null &&
            question.questionHi!.questionTxt.isNotEmpty) ...[
          pw.Text(
            "Question (HI):",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          ..._parseMarkdownToPdfWidgets(
            question.questionHi!.questionTxt,
            baseFont,
            gujaratiFont,
          ),
          if (showAnswers &&
              question.questionHi!.answerTxt.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              "Model Answer (HI):",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ..._parseMarkdownToPdfWidgets(
              question.questionHi!.answerTxt,
              baseFont,
              gujaratiFont,
            ),
          ],
        ],
        if (langCodes[k] == 'gj' &&
            question.questionGj?.questionTxt != null &&
            question.questionGj!.questionTxt.isNotEmpty) ...[
          pw.Text(
            "Question (GJ):",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          ..._parseMarkdownToPdfWidgets(
            question.questionGj!.questionTxt,
            baseFont,
            gujaratiFont,
          ),
          if (showAnswers &&
              question.questionGj!.answerTxt.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              "Model Answer (GJ):",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ..._parseMarkdownToPdfWidgets(
              question.questionGj!.answerTxt,
              baseFont,
              gujaratiFont,
            ),
          ],
        ],
      ],
      pw.SizedBox(height: 30), // Spacing after question/answer
    ]);

    // --- Extra pages (Question Paper mode only) ---
    if (!showAnswers && (question.pages ?? 1) > 1) {
      // Dump the accumulated widgets so far into a MultiPage
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          footer: buildFooter,
          build: (context) => currentWidgets,
        ),
      );
      // Reset the list for the next set of questions
      currentWidgets = [];

      // Add the requested blank pages for the user to write their answer
      for (int j = 1; j < (question.pages ?? 1); j++) {
        pdf.addPage(
          pw.Page(
            pageTheme: pageTheme,
            build: (context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Expanded(child: pw.SizedBox()),
                  buildFooter(context),
                ],
              );
            },
          ),
        );
      }
    }
  }

  // If there are any remaining widgets, output them as the final MultiPage
  if (currentWidgets.isNotEmpty) {
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        footer: buildFooter,
        build: (context) => currentWidgets,
      ),
    );
  }

  // --- Save PDF ---
  final bytes = await pdf.save();
  final suffix = showAnswers ? "ModelAnswer" : "QuestionPaper";
  final safeFileName = "${testName.toSafeFileName()}_FullTest_$suffix.pdf";
  String filePath;

  try {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // ✅ Android 10+ (Scoped Storage)
      if (sdkInt >= 29) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = "${tempDir.path}/$safeFileName";
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes);

        final mediaStore = MediaStore();
        MediaStore.appFolder = "StarICS";

        final saveInfo = await mediaStore.saveFile(
          tempFilePath: tempPath,
          dirType: DirType.download,
          dirName: DirName.download,
          relativePath: "StarICS/",
        );

        if (saveInfo == null) {
          throw Exception("Failed to save PDF to MediaStore");
        }

        String? realPath;
        try {
          realPath = await mediaStore.getFilePathFromUri(
            uriString: saveInfo.uri.toString(),
          );
        } catch (e) {
          getIt<LogHelper>().e("Could not resolve file path: $e");
        }

        if (realPath != null && await File(realPath).exists()) {
          filePath = realPath;
          await openFileManager(
            androidConfig: AndroidConfig(
              folderPath: realPath,
              folderType: AndroidFolderType.download,
            ),
          );
        } else {
          filePath = saveInfo.uri.toString();
          await openFileManager(
            androidConfig: AndroidConfig(
              folderPath: filePath,
              folderType: AndroidFolderType.download,
            ),
          );
        }
        return filePath;
      } else {
        // ✅ Android 9 and below – direct /Download/StarICS
        final downloadsDir = Directory("/storage/emulated/0/Download/StarICS");
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
        filePath = "${downloadsDir.path}/$safeFileName";
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await openFileManager(
          androidConfig: AndroidConfig(
            folderPath: filePath,
            folderType: AndroidFolderType.download,
          ),
        );
        return filePath;
      }
    } else {
      // ✅ iOS or other platforms
      final dir = await getApplicationDocumentsDirectory();
      filePath = "${dir.path}/$safeFileName";
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await openFileManager(
        androidConfig: AndroidConfig(
          folderPath: filePath,
          folderType: AndroidFolderType.download,
        ),
      );
      return filePath;
    }
  } catch (e) {
    getIt<LogHelper>().e("Error generating full Desc PDF: $e");
    final fallbackDir = await getTemporaryDirectory();
    filePath = "${fallbackDir.path}/$safeFileName";
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }
}

/// --- Script-aware font selection ---
/// ArialUnicodeMs.otf has real OpenType conjunct/half-form rules for some
/// Gujarati consonants but not others (e.g. ત but not ક), producing
/// visually-unfused conjuncts for the ones it lacks. lohit_gujarati.ttf is
/// a font purpose-built for Gujarati with complete conjunct coverage, so
/// any text containing Gujarati codepoints is rendered with it instead.
bool _containsGujarati(String text) {
  for (final rune in text.runes) {
    if (rune >= 0x0A80 && rune <= 0x0AFF) return true;
  }
  return false;
}

pw.Font _fontFor(String text, pw.Font baseFont, pw.Font gujaratiFont) =>
    _containsGujarati(text) ? gujaratiFont : baseFont;

/// lohit_gujarati.ttf only covers Gujarati script + basic ASCII, so
/// content mixing Gujarati with symbols it lacks (e.g. "→" used as a
/// flowchart separator in some answers) would otherwise render as a
/// missing-glyph box. Keep the other font available as a fallback so
/// those individual characters still draw, without affecting Gujarati
/// conjunct shaping (which only ever runs against the primary font).
List<pw.Font> _fallbackFor(String text, pw.Font baseFont, pw.Font gujaratiFont) =>
    _containsGujarati(text) ? [baseFont] : [gujaratiFont];

/// --- Markdown Parsing Helpers ---
List<pw.Widget> _parseMarkdownToPdfWidgets(
  String markdownText,
  pw.Font baseFont,
  pw.Font gujaratiFont,
) {
  final lines = markdownText.split('\n');
  List<pw.Widget> widgets = [];
  int i = 0;

  while (i < lines.length) {
    if (lines[i].trim().startsWith('|') &&
        i + 2 < lines.length &&
        lines[i + 1].contains('---')) {
      List<String> tableLines = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        tableLines.add(lines[i]);
        i++;
      }
      widgets.add(_buildPdfTableFromMarkdown(tableLines, baseFont, gujaratiFont));
      widgets.add(pw.SizedBox(height: 8));
    } else {
      final buffer = StringBuffer();
      while (i < lines.length && !lines[i].trim().startsWith('|')) {
        buffer.writeln(lines[i]);
        i++;
      }
      final normalMd = buffer.toString().trim();
      if (normalMd.isNotEmpty) {
        final document = md.Document(encodeHtml: false);
        final nodes = document.parseLines(normalMd.split('\n'));
        for (var node in nodes) {
          widgets.addAll(_markdownNodeToPdfWidget(node, baseFont, gujaratiFont));
        }
      }
    }
  }

  return widgets;
}

pw.Widget _buildPdfTableFromMarkdown(
  List<String> tableLines,
  pw.Font baseFont,
  pw.Font gujaratiFont,
) {
  List<List<String>> rows = tableLines
      .map(
        (line) => line
            .trim()
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .toList(),
      )
      .toList();

  if (rows.length < 2) return pw.SizedBox();
  final header = rows[0];
  final dataRows = rows.sublist(2);
  final tableText = [...header, ...dataRows.expand((r) => r)].join();
  final tableFont = _fontFor(tableText, baseFont, gujaratiFont);
  final tableFallback = _fallbackFor(tableText, baseFont, gujaratiFont);

  return pw.TableHelper.fromTextArray(
    headers: header,
    data: dataRows,
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey),
    headerStyle: pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      font: tableFont,
      fontFallback: tableFallback,
    ),
    cellStyle: pw.TextStyle(font: tableFont, fontFallback: tableFallback),
    headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
    cellAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.all(4),
  );
}

List<pw.Widget> _markdownNodeToPdfWidget(
  md.Node node,
  pw.Font baseFont,
  pw.Font gujaratiFont,
) {
  if (node is md.Element) {
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        return [
          pw.Text(
            node.textContent,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 18 - (level * 2),
              font: _fontFor(node.textContent, baseFont, gujaratiFont),
              fontFallback: _fallbackFor(node.textContent, baseFont, gujaratiFont),
            ),
          ),
          pw.SizedBox(height: 4),
        ];
      case 'ul':
        return [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: node.children!
                .expand((li) => _markdownNodeToPdfWidget(li, baseFont, gujaratiFont))
                .toList(),
          ),
        ];
      case 'ol':
        int i = 1;
        return [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: node.children!
                .map(
                  (li) => pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('$i. '),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: _markdownNodeToPdfWidget(li, baseFont, gujaratiFont),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ];
      case 'li':
        return [
          pw.Bullet(
            text: node.textContent,
            style: pw.TextStyle(
              font: _fontFor(node.textContent, baseFont, gujaratiFont),
              fontFallback: _fallbackFor(node.textContent, baseFont, gujaratiFont),
            ),
          ),
        ];
      case 'p':
        return [
          _spanFromMarkdownInline(node.children ?? [], baseFont, gujaratiFont),
          pw.SizedBox(height: 4),
        ];
      case 'strong':
      case 'em':
        return [
          _spanFromMarkdownInline([node], baseFont, gujaratiFont),
        ];
      case 'br':
        return [pw.SizedBox(height: 4)];
      default:
        return [
          pw.Text(
            node.textContent,
            style: pw.TextStyle(
              font: _fontFor(node.textContent, baseFont, gujaratiFont),
              fontFallback: _fallbackFor(node.textContent, baseFont, gujaratiFont),
            ),
          ),
        ];
    }
  } else if (node is md.Text) {
    return [
      pw.Text(
        node.text,
        style: pw.TextStyle(
          font: _fontFor(node.text, baseFont, gujaratiFont),
          fontFallback: _fallbackFor(node.text, baseFont, gujaratiFont),
        ),
      ),
    ];
  }
  return [];
}

pw.Widget _spanFromMarkdownInline(
  List<md.Node> nodes,
  pw.Font baseFont,
  pw.Font gujaratiFont,
) {
  return pw.RichText(
    text: pw.TextSpan(
      children: nodes.map((node) {
        if (node is md.Text) {
          return pw.TextSpan(
            text: node.text,
            style: pw.TextStyle(
              font: _fontFor(node.text, baseFont, gujaratiFont),
              fontFallback: _fallbackFor(node.text, baseFont, gujaratiFont),
            ),
          );
        } else if (node is md.Element) {
          final baseStyle = pw.TextStyle(
            font: _fontFor(node.textContent, baseFont, gujaratiFont),
            fontFallback: _fallbackFor(node.textContent, baseFont, gujaratiFont),
          );
          if (node.tag == 'strong' || node.tag == 'b') {
            return pw.TextSpan(
              text: node.textContent,
              style: baseStyle.copyWith(fontWeight: pw.FontWeight.bold),
            );
          }
          if (node.tag == 'em' || node.tag == 'i') {
            return pw.TextSpan(
              text: node.textContent,
              style: baseStyle.copyWith(fontStyle: pw.FontStyle.italic),
            );
          }
          return pw.TextSpan(
            children: node.children?.map((e) {
              if (e is md.Text) {
                return pw.TextSpan(
                  text: e.text,
                  style: pw.TextStyle(
                    font: _fontFor(e.text, baseFont, gujaratiFont),
                    fontFallback: _fallbackFor(e.text, baseFont, gujaratiFont),
                  ),
                );
              } else if (e is md.Element) {
                return pw.TextSpan(
                  text: e.textContent,
                  style: pw.TextStyle(
                    font: _fontFor(e.textContent, baseFont, gujaratiFont),
                    fontFallback: _fallbackFor(e.textContent, baseFont, gujaratiFont),
                  ),
                );
              }
              return pw.TextSpan();
            }).toList(),
          );
        }
        return pw.TextSpan();
      }).toList(),
    ),
  );
}
