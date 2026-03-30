import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../data/sources/bug_report_remote_source.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();
  bool _isSubmitting = false;
  final _source = BugReportRemoteSource(
    endpointUrl: AppConstants.gasEndpointUrl,
  );

  @override
  void dispose() {
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (AppConstants.gasEndpointUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信先が設定されていません。')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _source.sendReport(
        description: _descriptionController.text.trim(),
        steps: _stepsController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('報告を送信しました。ありがとうございます！')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('BugReportScreen: send failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信に失敗しました。しばらく後で再試行してください。')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          'バグを報告',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'バグの内容',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'どのような問題が起きましたか？',
                hintStyle: TextStyle(color: context.appColors.textDisabled),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                errorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: TextStyle(color: context.appColors.textPrimary),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'バグの内容を入力してください' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              '発生手順（任意）',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _stepsController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '再現する手順があれば教えてください',
                hintStyle: TextStyle(color: context.appColors.textDisabled),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: TextStyle(color: context.appColors.textPrimary),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('送信'),
            ),
          ],
        ),
      ),
    );
  }
}
