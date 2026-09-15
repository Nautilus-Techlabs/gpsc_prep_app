import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:gpsc_prep_app/core/di/di.dart';
import 'package:gpsc_prep_app/core/helpers/snack_bar_helper.dart';
import 'package:gpsc_prep_app/core/router/args.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_language_model.dart';
import 'package:gpsc_prep_app/domain/entities/desc_question_model.dart';
import 'package:gpsc_prep_app/presentation/blocs/descriptive_test/daily_descriptive_test_bloc.dart';
import 'package:gpsc_prep_app/presentation/blocs/question/question_bloc.dart';
import 'package:gpsc_prep_app/presentation/screens/descriptive_test_module/native_pdf_bridge.dart';
import 'package:gpsc_prep_app/utils/app_constants.dart';
import 'package:gpsc_prep_app/utils/extensions/padding.dart';
import 'package:markdown_widget/markdown_widget.dart';

class DescFullQuestionsScreen extends StatefulWidget {
  final DescFullQuestionsScreenArgs args;

  const DescFullQuestionsScreen({super.key, required this.args});

  @override
  State<DescFullQuestionsScreen> createState() =>
      _DescFullQuestionsScreenState();
}

class _DescFullQuestionsScreenState extends State<DescFullQuestionsScreen> {
  // Helper to map language code string to enum
  late String _currentLangCode = '';
  List<String> _availableLangs = [];
  File? _selectedFile;
  final Set<int> _downloadingIndices = {};
  bool _isDownloadingFull = false;

  @override
  void initState() {
    super.initState();
    _currentLangCode = widget.args.descTestModel?.allowedLanguages != null
        ? widget.args.descTestModel!.allowedLanguages!.first
        : widget.args.language ?? 'en';
    context.read<QuestionBloc>().add(
      LoadDescQuestion(widget.args.testId, _currentLangCode),
    );
    context.read<DailyDescTestBloc>().add(
      FetchAllTests(courseId: widget.args.courseId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<DailyDescTestBloc, DailyDescTestState>(
          listener: (context, state) {
            if (state is DescTestSubmitSuccess) {
              getIt<SnackBarHelper>().showSuccess(state.message);
              context.pop();
              context.read<DailyDescTestBloc>().add(ResetDescTestState());
            } else if (state is DescTestSubmitFailed) {
              getIt<SnackBarHelper>().showError(state.failure.message);
            }
          },
        ),
      ],
      child: BlocBuilder<QuestionBloc, QuestionState>(
        builder: (context, qState) {
          final questions = qState is DescQuestionLoaded
              ? qState.questionsModels
              : <DescQuestionModel>[];

          // Determine language options based on question data
          if (questions.isNotEmpty) {
            final List<String> present = [];
            final q = questions.first;
            if (q.questionEn.questionTxt.trim().isNotEmpty) {
              present.add('en');
            }
            if (q.questionHi != null &&
                q.questionHi!.questionTxt.trim().isNotEmpty) {
              present.add('hi');
            }
            if (q.questionGj != null &&
                q.questionGj!.questionTxt.trim().isNotEmpty) {
              present.add('gj');
            }

            final modelAllowed =
                widget.args.descTestModel?.allowedLanguages ?? [];

            // Prioritize model's allowed languages, but filter by what is actually present in question data.
            // If model doesn't specify allowed languages, fallback to all present languages.
            _availableLangs = modelAllowed.isNotEmpty
                ? modelAllowed.where((l) => present.contains(l)).toList()
                : present;

            if (_availableLangs.isNotEmpty &&
                !_availableLangs.contains(_currentLangCode)) {
              _currentLangCode = _availableLangs.first;
            }
          } else {
            _availableLangs = [];
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(widget.args.testName, style: AppTexts.titleTextStyle),
              actions: [
                // Language toggle button based on available languages
                if (_availableLangs.length > 1)
                  IconButton(
                    onPressed: () {
                      final currentIdx = _availableLangs.indexOf(
                        _currentLangCode,
                      );
                      final nextIdx = (currentIdx + 1) % _availableLangs.length;
                      setState(() {
                        _currentLangCode = _availableLangs[nextIdx];
                      });
                    },
                    icon: Text(
                      _getLanguageChar(_currentLangCode),
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    tooltip: 'Switch Language',
                  ),
                if (questions.isNotEmpty)
                  IconButton(
                    onPressed: _isDownloadingFull
                        ? null
                        : () => _downloadFullPdf(
                            questions,
                            isAnswer: widget.args.isSubmitted,
                          ),
                    icon: _isDownloadingFull
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            Icons.download_rounded,
                            color: AppColors.primary,
                          ),
                    tooltip: 'Download Full Test PDF',
                  ),
                SizedBox(width: 8.w),
              ],
            ),
            body: _buildBody(qState, questions),
            bottomNavigationBar: widget.args.isSubmitted
                ? null
                : _buildBottomBar(),
          );
        },
      ),
    );
  }

  String _getLanguageChar(String lang) {
    switch (lang) {
      case 'hi':
        return 'अ';
      case 'gj':
        return 'અ';
      default:
        return 'A';
    }
  }

  // ─── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(QuestionState qState, List<DescQuestionModel> questions) {
    if (qState is QuestionLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (qState is QuestionLoadFailed) {
      return Center(child: Text('Failed to load: ${qState.failure.message}'));
    }
    if (questions.isEmpty) {
      return const Center(child: Text('No questions available.'));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      itemCount: questions.length,
      itemBuilder: (context, i) => _buildCard(questions[i], i + 1),
    );
  }

  Widget _buildCard(DescQuestionModel q, int index) {
    final langData = _getLangData(q);
    final isDownloading = _downloadingIndices.contains(index);

    return Card(
      margin: EdgeInsets.only(bottom: 16.h),
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question $index',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                    color: AppColors.primary,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '${q.marks} Marks',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: 20.h),
            // Question text (markdown)
            MarkdownWidget(
              data: langData.questionTxt,
              shrinkWrap: true,
              config: MarkdownConfig(
                configs: [
                  PConfig(
                    textStyle: TextStyle(
                      fontSize: 15.sp,
                      height: 1.6,
                      color: AppColors.gray900,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.args.isSubmitted && langData.answerTxt.isNotEmpty) ...[
              Divider(height: 32.h),
              Text(
                'Model Answer',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 12.h),
              MarkdownWidget(
                data: langData.answerTxt,
                shrinkWrap: true,
                config: MarkdownConfig(
                  configs: [
                    PConfig(
                      textStyle: TextStyle(
                        fontSize: 15.sp,
                        height: 1.6,
                        color: AppColors.gray900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 12.h),
            if (!widget.args.isSubmitted)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isDownloading
                      ? null
                      : () => _downloadPdf(q, index),
                  icon: isDownloading
                      ? SizedBox(
                          width: 14.w,
                          height: 14.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 16.sp,
                          color: AppColors.primary,
                        ),
                  label: Text(
                    isDownloading
                        ? 'Generating...'
                        : 'Download (${q.pages ?? 1} pg${(q.pages ?? 1) > 1 ? "s" : ""})',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom PDF bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return BlocBuilder<DailyDescTestBloc, DailyDescTestState>(
      builder: (context, state) {
        final isSubmitting = state is DescTestSubmit;

        return Container(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(18),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Chosen file row
                if (_selectedFile != null) ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf,
                          color: Colors.red.shade700,
                          size: 20.sp,
                        ),
                        8.wGap,
                        Expanded(
                          child: Text(
                            _selectedFile!.path.split('/').last,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Remove PDF
                        GestureDetector(
                          onTap: () => setState(() => _selectedFile = null),
                          child: Icon(
                            Icons.close,
                            color: Colors.grey.shade600,
                            size: 18.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  8.hGap,
                ],
                // Primary action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : (_selectedFile == null ? _pickPDF : _submitTest),
                    icon: isSubmitting
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _selectedFile == null
                                ? Icons.upload_file
                                : Icons.check_circle_outline,
                            size: 20.sp,
                          ),
                    label: Text(
                      isSubmitting
                          ? 'Submitting...'
                          : (_selectedFile == null
                                ? 'Select PDF'
                                : 'Submit Test'),
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                  ),
                ),
                8.hGap,
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  DescQuestionLanguageData _getLangData(DescQuestionModel q) {
    switch (_currentLangCode) {
      case 'hi':
        return q.questionHi ?? q.questionEn;
      case 'gj':
        return q.questionGj ?? q.questionEn;
      default:
        return q.questionEn;
    }
  }

  Future<void> _pickPDF() async {
    final bool? shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'Instructions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          'Please select a single PDF containing answers for all the questions in this test.',
          style: TextStyle(fontSize: 14.sp, color: AppColors.gray700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.gray500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  void _submitTest() {
    if (_selectedFile == null) return;
    context.read<DailyDescTestBloc>().add(
      SubmitDescriptiveTestSinglePdf(
        testId: widget.args.testId,
        file: _selectedFile!,
      ),
    );
  }

  Future<void> _downloadPdf(DescQuestionModel question, int index) async {
    // Native (platform-channel) PDF generation is Android-only for now;
    // simply skip on other platforms rather than attempting it.
    if (!Platform.isAndroid) return;

    setState(() => _downloadingIndices.add(index));
    try {
      await generateSingleDescTestPdfNative(
        question,
        index,
        widget.args.testName,
        _availableLangs,
        showAnswers: false,
      );
      if (mounted) {
        getIt<SnackBarHelper>().showSuccess('PDF downloaded successfully');
      }
    } catch (e) {
      if (mounted) {
        getIt<SnackBarHelper>().showError('Failed to generate PDF');
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingIndices.remove(index));
      }
    }
  }

  Future<void> _downloadFullPdf(
    List<DescQuestionModel> questions, {
    required bool isAnswer,
  }) async {
    // Native (platform-channel) PDF generation is Android-only for now;
    // simply skip on other platforms rather than attempting it.
    if (!Platform.isAndroid) return;

    setState(() => _isDownloadingFull = true);
    try {
      await generateDescTestPdfNative(
        questions,
        widget.args.testName,
        _availableLangs,
        showAnswers: isAnswer,
      );
      if (mounted) {
        getIt<SnackBarHelper>().showSuccess(
          'Full Test PDF downloaded successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        getIt<SnackBarHelper>().showError('Failed to generate full PDF');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingFull = false);
      }
    }
  }
}
