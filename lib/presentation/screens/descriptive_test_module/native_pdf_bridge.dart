// Standalone bridge to the native (Kotlin Canvas/StaticLayout) PDF generator,
// ported from the csv-to-pdf reference app, exposed via a platform channel
// (see android/app/src/main/kotlin/com/starics/pdf/). Kept separate from
// desc_pdf_download.dart on purpose: this is an experimental alternative
// rendering path (Android-only for now) and isn't meant to touch the
// existing dart_pdf-based screen/flow while it's being evaluated.
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_file_manager/open_file_manager.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.starics/native_pdf');

/// Generates a descriptive-test PDF using the native Android text engine
/// (Canvas/StaticLayout) instead of dart_pdf, saves it to
/// /Download/StarICS the same way the existing dart_pdf flow does, and
/// returns the resulting file path. Android-only.
Future<String> generateDescTestPdfNative(
  List<DescQuestionModel> questions,
  String testName,
  List<String> langCodes, {
  bool showAnswers = true,
}) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('Native PDF generation is Android-only for now.');
  }

  final questionArgs = questions.asMap().entries.map((entry) {
    final index = entry.key + 1;
    final q = entry.value;
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

    return {'srNo': index, 'byLanguage': byLanguage};
  }).toList();

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
