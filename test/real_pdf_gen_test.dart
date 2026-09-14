// Smoke test: calls the REAL generateFullDescTestPdf function (not a
// reimplementation) through flutter_test's real asset-bundle resolution,
// so font loading (ArialUnicodeMs + lohit_gujarati) goes through the
// actual Flutter asset pipeline rather than a script reading files off
// disk directly. Catches asset-registration issues a pure-Dart harness
// can't see.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpsc_prep_app/core/di/di.dart';
import 'package:gpsc_prep_app/core/helpers/log_helper.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_language_model.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:gpsc_prep_app/presentation/screens/descriptive_test_module/desc_pdf_download.dart';
import 'package:gpsc_prep_app/utils/enums/difficulty_level.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'generateFullDescTestPdf produces a real PDF for Gujarati content',
    (tester) async {
      // ScreenUtil (.sp sizing) needs a real widget tree pumped first,
      // same as the app does at startup, before any code using .sp runs.
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(360, 690),
          builder: (context, child) => const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pump();

      if (!getIt.isRegistered<LogHelper>()) {
        getIt.registerSingleton<LogHelper>(LogHelper());
      }

      // testWidgets runs in a fake-async zone; real dart:io operations
      // (file creation, rootBundle.load, pdf.save) hang forever unless
      // run via tester.runAsync() to escape onto the real event loop.
      await tester.runAsync(() async {
        final tempDir = await Directory.systemTemp.createTemp('pdf_gen_test');
        PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

        const questionGjText =
            'ભારતીય સ્વાતંત્ર્યસંગ્રામ ક્રમિક તબક્કાઓમાંથી વિકસ્યો; '
            'પરંતુ દરેક તબક્કાએ અગાઉના તબક્કામાંથી વિચારો.';

        final question = DescQuestionModel(
          id: 1,
          questionType: 'desc',
          difficultyLevel: DifficultyLevel.mod,
          questionEn: DescQuestionLanguageData(
            questionTxt: 'The Indian freedom struggle evolved through successive stages.',
            answerTxt: 'Introduction\nThe Indian freedom struggle was neither isolated nor linear.',
          ),
          questionHi: null,
          questionGj: DescQuestionLanguageData(
            questionTxt: questionGjText,
            answerTxt: '**પ્રસ્તાવના**\n$questionGjText',
          ),
          createdAt: DateTime.now().toIso8601String(),
          marks: 15,
          questionHash: 'test-hash',
          subjectName: 'History',
          topicName: 'Test Topic',
          pages: 3,
          questionOrder: 1,
        );

        final filePath = await generateFullDescTestPdf(
          [question],
          'Day - 34 Test',
          ['gj'],
          showAnswers: true,
        );

        final file = File(filePath);
        expect(
          file.existsSync(),
          true,
          reason: 'PDF file should have been written to $filePath',
        );
        expect(file.readAsBytesSync().length, greaterThan(1000));
      });
    },
  );
}
