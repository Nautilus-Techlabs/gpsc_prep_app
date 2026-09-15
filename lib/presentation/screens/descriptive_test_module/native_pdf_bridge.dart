// Standalone bridge to the native (Kotlin Canvas/StaticLayout) PDF generator,
// ported from the csv-to-pdf reference app, exposed via a platform channel
// (see android/app/src/main/kotlin/com/starics/pdf/). Kept separate from
// desc_pdf_download.dart on purpose: it's a distinct rendering path
// (Android-only -- callers are expected to check Platform.isAndroid and
// skip calling this on other platforms) and isn't meant to touch the
// existing dart_pdf-based screen/flow's own code.
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_file_manager/open_file_manager.dart';

const _channel = MethodChannel('com.starics/native_pdf');

Map<String, Map<String, String>> _byLanguageFor(
  DescQuestionModel q,
  bool showAnswers,
) {
  final byLanguage = <String, Map<String, String>>{};

  void addLang(String code, String question, String? answer) {
    if (question.isEmpty) return;
    byLanguage[code] = {
      'question': question,
      'answer': showAnswers ? (answer ?? '') : '',
    };
  }

  addLang('en', q.questionEn.questionTxt, q.questionEn.answerTxt);
  if (q.questionHi != null) {
    addLang('hi', q.questionHi!.questionTxt, q.questionHi!.answerTxt);
  }
  if (q.questionGj != null) {
    addLang('gj', q.questionGj!.questionTxt, q.questionGj!.answerTxt);
  }

  return byLanguage;
}

Future<String> _invokeAndSave(
  List<Map<String, Object?>> questionArgs,
  String testName,
  List<String> langCodes,
  bool showAnswers,
) async {
  final nativePath = await _channel.invokeMethod<String>(
    'generateDescTestPdf',
    {
      'testName': testName,
      'langCodes': langCodes,
      'showAnswers': showAnswers,
      'questions': questionArgs,
    },
  );

  if (nativePath == null) {
    throw Exception('Native PDF generation returned no file path.');
  }

  return _saveToDownloads(nativePath, testName, showAnswers);
}

/// Generates a descriptive-test PDF for a full set of questions using the
/// native Android text engine (Canvas/StaticLayout) instead of dart_pdf,
/// saves it to /Download/StarICS the same way the existing dart_pdf flow
/// does, and returns the resulting file path. Android-only -- callers must
/// check Platform.isAndroid themselves before calling this.
Future<String> generateDescTestPdfNative(
  List<DescQuestionModel> questions,
  String testName,
  List<String> langCodes, {
  bool showAnswers = true,
}) {
  final questionArgs = questions.asMap().entries.map((entry) {
    return {
      'srNo': entry.key + 1,
      'byLanguage': _byLanguageFor(entry.value, showAnswers),
    };
  }).toList();

  return _invokeAndSave(questionArgs, testName, langCodes, showAnswers);
}

/// Same as [generateDescTestPdfNative], but for a single question (mirrors
/// desc_pdf_download.dart's per-question generateDescTestPdf). [index] is
/// used as the "Question N" number shown on the page, matching the
/// dart_pdf version's behavior. Android-only.
Future<String> generateSingleDescTestPdfNative(
  DescQuestionModel question,
  int index,
  String testName,
  List<String> langCodes, {
  bool showAnswers = true,
}) {
  final questionArgs = [
    {
      'srNo': index,
      'byLanguage': _byLanguageFor(question, showAnswers),
    },
  ];

  return _invokeAndSave(questionArgs, testName, langCodes, showAnswers);
}

Future<String> _saveToDownloads(
  String nativeFilePath,
  String testName,
  bool showAnswers,
) async {
  final suffix = showAnswers ? 'ModelAnswer' : 'QuestionPaper';
  final safeTestName = testName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
  final safeFileName = '${safeTestName}_Native_$suffix.pdf';

  final deviceInfo = DeviceInfoPlugin();
  final androidInfo = await deviceInfo.androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  if (sdkInt >= 29) {
    final mediaStore = MediaStore();
    MediaStore.appFolder = 'StarICS';

    final saveInfo = await mediaStore.saveFile(
      tempFilePath: nativeFilePath,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: 'StarICS/',
    );

    if (saveInfo == null) {
      throw Exception('Failed to save native PDF to MediaStore');
    }

    String? realPath;
    try {
      realPath = await mediaStore.getFilePathFromUri(
        uriString: saveInfo.uri.toString(),
      );
    } catch (_) {
      // fall through to the URI-based path below
    }

    final filePath = (realPath != null && await File(realPath).exists())
        ? realPath
        : saveInfo.uri.toString();

    await openFileManager(
      androidConfig: AndroidConfig(
        folderPath: filePath,
        folderType: AndroidFolderType.download,
      ),
    );
    return filePath;
  }

  final downloadsDir = Directory('/storage/emulated/0/Download/StarICS');
  if (!await downloadsDir.exists()) {
    await downloadsDir.create(recursive: true);
  }
  final filePath = '${downloadsDir.path}/$safeFileName';
  await File(nativeFilePath).copy(filePath);
  await openFileManager(
    androidConfig: AndroidConfig(
      folderPath: filePath,
      folderType: AndroidFolderType.download,
    ),
  );
  return filePath;
}
