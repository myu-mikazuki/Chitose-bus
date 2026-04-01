import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../data/sources/contact_remote_source.dart';

const _categories = ['バグ報告', '機能要望', 'その他'];

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _detailController = TextEditingController();
  String _category = _categories.first;
  bool _isSubmitting = false;
  final _source = ContactRemoteSource(
    endpointUrl: AppConstants.gasEndpointUrl,
  );

  @override
  void dispose() {
    _descriptionController.dispose();
    _detailController.dispose();
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
        category: _category,
        description: _descriptionController.text.trim(),
        steps: _detailController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信しました。ありがとうございます！')),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('ContactScreen: send failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信に失敗しました。しばらく後で再試行してください。')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderSide: BorderSide(color: color),
        borderRadius: BorderRadius.circular(8),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          'お問い合わせ',
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
              'お問い合わせの種類',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _category,
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
              style: TextStyle(color: context.appColors.textPrimary),
              dropdownColor: context.appColors.background,
              decoration: InputDecoration(
                enabledBorder: _border(context.appColors.border),
                focusedBorder: _border(AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'お問い合わせ内容',
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
                hintText: 'お問い合わせの内容を入力してください',
                hintStyle: TextStyle(color: context.appColors.textDisabled),
                enabledBorder: _border(context.appColors.border),
                focusedBorder: _border(AppColors.primary),
                errorBorder: _border(Colors.red.shade300),
                focusedErrorBorder: _border(Colors.red.shade300),
              ),
              style: TextStyle(color: context.appColors.textPrimary),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'お問い合わせ内容を入力してください' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              '詳細（任意）',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _detailController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '詳細があれば教えてください',
                hintStyle: TextStyle(color: context.appColors.textDisabled),
                enabledBorder: _border(context.appColors.border),
                focusedBorder: _border(AppColors.primary),
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
