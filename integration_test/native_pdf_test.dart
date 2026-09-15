// On-device test for the native (Kotlin Canvas/StaticLayout) PDF generation
// platform channel. Runs as a real app on a real device (not flutter_test's
// fake-async host environment), so the MethodChannel call actually reaches
// the native Android code.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_language_model.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:gpsc_prep_app/presentation/screens/descriptive_test_module/native_pdf_bridge.dart';
import 'package:gpsc_prep_app/utils/enums/difficulty_level.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native PDF generation produces a real PDF for Gujarati content', (
    tester,
  ) async {
    // The real app calls this once at startup (see lib/app_services.dart);
    // this test runs standalone, so it needs to do the same before saving.
    await MediaStore.ensureInitialized();
    const questionGjText =
        'ભારતીય સ્વાતંત્ર્યસંગ્રામ ક્રમિક તબક્કાઓમાંથી વિકસ્યો; '
        'પરંતુ દરેક તબક્કાએ અગાઉના તબક્કામાંથી વિચારો.';

    final question = DescQuestionModel(
      id: 1,
      questionType: 'desc',
      difficultyLevel: DifficultyLevel.mod,
      questionEn: DescQuestionLanguageData(
        questionTxt:
            'The Indian freedom struggle evolved through successive stages.',
        answerTxt:
            'Introduction\nThe Indian freedom struggle was neither isolated nor linear.',
      ),
      questionHi: null,
      questionGj: DescQuestionLanguageData(
        questionTxt: questionGjText,
        answerTxt: '**પ્રસ્તાવના**\n$questionGjText',
      ),
      createdAt: DateTime.now().toIso8601String(),
      marks: 15,
      questionHash: 'native-test-hash',
      subjectName: 'History',
      topicName: 'Test Topic',
      pages: 3,
      questionOrder: 1,
    );

    final filePath = await generateDescTestPdfNative(
      [question],
      'Native Bridge Test',
      ['gj'],
      showAnswers: true,
    );

    // ignore: avoid_print
    print('NATIVE_PDF_PATH: $filePath');

    final file = File(filePath);
    expect(
      file.existsSync(),
      true,
      reason: 'Native PDF file should have been written to $filePath',
    );
    expect(file.readAsBytesSync().length, greaterThan(500));
  });
}
