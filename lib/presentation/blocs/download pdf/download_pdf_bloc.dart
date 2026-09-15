import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gpsc_prep_app/core/di/di.dart';
import 'package:gpsc_prep_app/core/error/failure.dart';
import 'package:gpsc_prep_app/core/helpers/log_helper.dart';
import 'package:gpsc_prep_app/core/helpers/snack_bar_helper.dart';
import 'package:gpsc_prep_app/domain/entities/question_model.dart';
import 'package:gpsc_prep_app/domain/entities/result_with_top_score_model.dart';
import 'package:gpsc_prep_app/presentation/screens/descriptive_test_module/native_pdf_bridge.dart';
import 'package:gpsc_prep_app/presentation/screens/preview_screen/pdf_export_service.dart';
import 'package:gpsc_prep_app/utils/helper_methods/pdf_download_from_link.dart';
import 'package:gpsc_prep_app/utils/services/test_link_generator.dart';
import 'package:meta/meta.dart';
import 'package:open_file_manager/open_file_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../../domain/entities/desc_question_model.dart';
import '../../../domain/entities/detailed_test_result_model.dart';

part 'download_pdf_event.dart';
part 'download_pdf_state.dart';

class DownLoadPdfBloc extends Bloc<DownLoadPdfEvent, DownLoadPdfState> {
  final _log = getIt<LogHelper>();
  final _snackBar = getIt<SnackBarHelper>();

  DownLoadPdfBloc() : super(DownLoadPdfInitial()) {
    on<ExportQuestionsToPdfEvent>(_onExportQuestionsToPdf);
    on<DownloadStudyMaterial>(_downloadStudyMaterial);
    on<DownloadDescTestPdf>(_downloadDescTestPdf);
    on<DownloadFullDescTestPdf>(_onDownloadFullDescTestPdf);
    on<DownloadPrelimsOmr>(_downloadPrelimsOmr);
  }

  Future<void> _onExportQuestionsToPdf(
    ExportQuestionsToPdfEvent event,
    Emitter<DownLoadPdfState> emit,
  ) async {
    try {
      emit(DownLoadPdfStarted());
      if (Platform.isAndroid &&
          (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 30) {
        await getExternalStorageDirectory();
      } else {
        await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      final result = await PdfExportService().exportQuestionsToPdf(
        event.questions,
        event.testName,
        performanceSummary: event.performanceSummary,
        testType: event.testType,
        detailedResults: event.detailedResults,
        languages: event.languages,
        showAnswers: event.showAnswers,
      );
      if (result.isEmpty) {
        _log.e("Failed to generate PDF");
        emit(PdfDownloadFailure(Failure("Failed to generate PDF")));
        return;
      }
      _log.i("PDF generated successfully: $result");
      await openFileManager(
        androidConfig: AndroidConfig(
          folderPath: result,
          folderType: AndroidFolderType.download,
        ),
      );
      emit(PdfDownloadSuccess(result));
    } catch (e) {
      _log.e('Error exporting questions to PDF: $e');
      emit(PdfDownloadFailure(Failure('Failed to export PDF')));
    }
  }

  Future<void> _downloadDescTestPdf(
    DownloadDescTestPdf event,
    Emitter<DownLoadPdfState> emit,
  ) async {
    // Native (platform-channel) PDF generation is Android-only for now;
    // simply skip on other platforms rather than attempting it.
    if (!Platform.isAndroid) return;

    emit(DownLoadPdfStarted());

    try {
      if ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 30) {
        await getExternalStorageDirectory();
      } else {
        await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      final result = await generateSingleDescTestPdfNative(
        event.question,
        event.index,
        event.testName,
        event.langCodes,
        showAnswers: event.showAnswers,
      );

      if (result.isEmpty) {
        _log.e("Failed to generate PDF for question ${event.question.id}");
        emit(PdfDownloadFailure(Failure("Failed to generate PDF")));
        return;
      }
      _log.i("PDF generated successfully: $result");
      emit(PdfDownloadSuccess(result));
      _snackBar.showSuccess(
        "PDF downloaded successfully into Downloads under StarICS folder",
      );
    } catch (e) {
      _log.e("Error downloading PDF: $e");
      emit(PdfDownloadFailure(Failure(e.toString())));
    }
  }

  Future<void> _onDownloadFullDescTestPdf(
    DownloadFullDescTestPdf event,
    Emitter<DownLoadPdfState> emit,
  ) async {
    // Native (platform-channel) PDF generation is Android-only for now;
    // simply skip on other platforms rather than attempting it.
    if (!Platform.isAndroid) return;

    try {
      emit(DownLoadPdfStarted());
      final result = await generateDescTestPdfNative(
        event.questions,
        event.testName,
        event.langCodes,
        showAnswers: event.showAnswers,
      );

      if (result.isEmpty) {
        _log.e("Failed to generate PDF for test ${event.testName}");
        emit(PdfDownloadFailure(Failure("Failed to generate PDF")));
        return;
      }
      _log.i("Full test PDF generated successfully: $result");
      emit(PdfDownloadSuccess(result));
    } catch (e) {
      _log.e("Error downloading full test PDF: $e");
      emit(PdfDownloadFailure(Failure(e.toString())));
    }
  }

  Future<void> _downloadStudyMaterial(
    DownloadStudyMaterial event,
    Emitter<DownLoadPdfState> emit,
  ) async {
    emit(DownLoadPdfStarted());
    final result = await downloadAndOpenPdf(
      normalUrl: event.url,
      filename: event.filename,
    );
    result.fold(
      (failure) {
        emit(PdfDownloadFailure(failure));
      },
      (_) {
        _snackBar.showSuccess(
          "PDF downloaded successfully into Downloads under StarICS folder",
        );
        emit(PdfDownloadSuccess(result.right));
      },
    );
  }

  Future<void> _downloadPrelimsOmr(
    DownloadPrelimsOmr event,
    Emitter<DownLoadPdfState> emit,
  ) async {
    emit(DownLoadPdfStarted());
    final result = await downloadAndOpenPdf(
      normalUrl: event.url,
      filename: event.filename,
    );
    result.fold(
      (failure) {
        emit(PdfDownloadFailure(failure));
      },
      (_) {
        _snackBar.showSuccess(
          "PDF downloaded successfully into Downloads under StarICS folder",
        );
        emit(PdfDownloadSuccess(result.right));
      },
    );
  }
}
