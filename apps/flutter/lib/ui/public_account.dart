import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/controller.dart';

/// Email/password accounts are private members, never operator/worker roles.
class PublicAccountScreen extends StatefulWidget {
  const PublicAccountScreen({super.key, required this.controller,
    required this.backend, required this.remember});
  final ControlController controller;
  final String backend;
  final bool remember;
  @override
  State<PublicAccountScreen> createState() => _PublicAccountScreenState();
}

class _PublicAccountScreenState extends State<PublicAccountScreen> {
  final email = TextEditingController();
  final name = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  String mode = 'Sign in';
  String? message;
  bool busy = false;
  @override
  void dispose() {
    email.dispose(); name.dispose(); password.dispose(); code.dispose();
    super.dispose();
  }
  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try {
      String path;
      Map<String, dynamic> body;
      switch (mode) {
        case 'Create account':
          path = '/api/auth/register';
          body = {'email': email.text.trim(), 'displayName': name.text.trim(),
            'password': password.text};
          break;
        case 'Verify email':
          path = '/api/auth/verify';
          body = {'email': email.text.trim(), 'code': code.text.trim()};
          break;
        case 'Forgot password':
          path = '/api/auth/forgot'; body = {'email': email.text.trim()}; break;
        case 'Reset password':
          path = '/api/auth/reset';
          body = {'email': email.text.trim(), 'code': code.text.trim(),
            'newPassword': password.text};
          break;
        default:
          path = '/api/auth/login';
          body = {'email': email.text.trim(), 'password': password.text};
      }
      final result = await AgentApi.publicAccountRequest(
        backend: widget.backend, path: path, body: body);
      if (!mounted) return;
      if (mode == 'Sign in') {
        final token = result['token'];
        if (token is! String || token.length < 40) {
          throw const ApiException('Invalid server session');
        }
        final ok = await widget.controller.connect(widget.backend, token,
          remember: widget.remember);
        if (!mounted) return;
        if (ok) Navigator.pop(context);
        else setState(() => message = widget.controller.error ?? 'Sign-in failed');
        return;
      }
      password.clear(); code.clear();
      setState(() {
        message = result['message']?.toString() ?? 'Account updated successfully.';
        if (mode == 'Create account') mode = 'Verify email';
        else if (mode == 'Forgot password') mode = 'Reset password';
        else mode = 'Sign in';
      });
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    const modes = ['Sign in','Create account','Verify email','Forgot password','Reset password'];
    final needsPassword = mode == 'Sign in' || mode == 'Create account' || mode == 'Reset password';
    return Scaffold(
      appBar: AppBar(title: const Text('Personal O-AGENT account')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Your own AI workspace', style: TextStyle(fontSize: 27,
            fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(widget.backend, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          const Text('Public accounts require an HTTPS cloud backend and email verification. '
            'Personal accounts cannot control the owner’s laptop.',
            style: TextStyle(fontSize: 12, height: 1.5)),
          const SizedBox(height: 17),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final item in modes) ChoiceChip(
              label: Text(item), selected: mode == item,
              onSelected: busy ? null : (_) => setState(() {
                mode = item; message = null; code.clear();
              })),
          ]),
          const SizedBox(height: 18),
          TextField(controller: email, keyboardType: TextInputType.emailAddress,
            autocorrect: false, decoration: const InputDecoration(
              labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined))),
          if (mode == 'Create account') ...[
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 80,
              decoration: const InputDecoration(labelText: 'Display name',
                prefixIcon: Icon(Icons.person_outline))),
          ],
          if (needsPassword) ...[
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, enableSuggestions: false,
              autocorrect: false, decoration: InputDecoration(
                labelText: mode == 'Reset password' ? 'New password (12+ characters)' :
                  'Password (12+ characters)', prefixIcon: const Icon(Icons.lock_outline))),
          ],
          if (mode == 'Verify email' || mode == 'Reset password') ...[
            const SizedBox(height: 12),
            TextField(controller: code, enableSuggestions: false, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Code received by email',
                prefixIcon: Icon(Icons.verified_outlined))),
          ],
          const SizedBox(height: 18),
          if (message != null) Padding(padding: const EdgeInsets.only(bottom: 14),
            child: Text(message!, style: const TextStyle(fontSize: 12))),
          FilledButton.icon(onPressed: busy ? null : submit,
            icon: busy ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)) :
              const Icon(Icons.arrow_forward),
            label: Text(busy ? 'Working…' : mode)),
          const SizedBox(height: 14),
          const Text('Never share your password or provider API keys. Connect your '
            'own AI provider only after signing in.',
            style: TextStyle(fontSize: 11, height: 1.5)),
        ]),
      ))),
    );
  }
}
