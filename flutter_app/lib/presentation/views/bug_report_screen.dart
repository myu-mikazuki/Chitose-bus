import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

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

  @override
  void dispose() {
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final client = http.Client();
    try {
      // GAS web app redirects POST (302) to a GET URL.
      // Disable auto-redirect to capture the Location header, then follow manually.
      final request = http.Request(
        'POST',
        Uri.parse(AppConstants.gasEndpointUrl),
      )
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'description': _descriptionController.text.trim(),
          'steps': _stepsController.text.trim(),
        })
        ..followRedirects = false;

      final streamed = await client.send(request).timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamed);

      if (response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null) {
          response = await client
              .get(Uri.parse(location))
              .timeout(const Duration(seconds: 30));
        }
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) {
        throw Exception(body['error'] ?? '送信に失敗しました');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('報告を送信しました。ありがとうございます！')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送信に失敗しました: $e')),
      );
    } finally {
      client.close();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
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
                hintStyle: const TextStyle(color: AppColors.textDisabled),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.border),
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
              style: const TextStyle(color: AppColors.textPrimary),
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
                hintStyle: const TextStyle(color: AppColors.textDisabled),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(color: AppColors.textPrimary),
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
