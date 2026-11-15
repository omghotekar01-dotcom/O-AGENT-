import 'dart:convert';
import 'dart:io';

/// New API-owned conversation, not a ChatGPT website conversation.
class OpenAiResponseTurn {
  const OpenAiResponseTurn({required this.id, required this.text});
  final String id;
  final String text;
}

/// Read all actual assistant output_text blocks, not just output[0].
OpenAiResponseTurn parseOpenAiResponse(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Provider returned an invalid response.');
  }
  final id = decoded['id'];
  final output = decoded['output'];
  if (id is! String || id.isEmpty || output is! List) {
    throw const FormatException('Provider returned no completed text response.');
  }
  final parts = <String>[];
  for (final item in output) {
    if (item is! Map || item['type'] != 'message' ||
        item['role'] != 'assistant') continue;
    final content = item['content'];
    if (content is! List) continue;
    for (final part in content) {
      if (part is Map && part['type'] == 'output_text' &&
          part['text'] is String) {
        final text = (part['text'] as String).trim();
        if (text.isNotEmpty) parts.add(text);
      }
    }
  }
  if (parts.isEmpty) {
    throw const FormatException('Provider returned no readable answer.');
  }
  return OpenAiResponseTurn(id: id, text: parts.join('\n\n'));
}

/// HTTPS-only BYOK request. The key stays in phone secure storage; only
/// the OpenAI API receives it as the bearer credential.
Future<OpenAiResponseTurn> sendOpenAiResponse({
  required String key,
  required String model,
  required String prompt,
  String? previousResponseId,
  HttpClient? httpClient,
}) async {
  if (key.trim().length < 24) throw const FormatException('Invalid API key.');
  if (model.trim().isEmpty || model.length > 90 ||
      !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(model)) {
    throw const FormatException('Use a valid model ID.');
  }
  final input = prompt.trim();
  if (input.isEmpty || input.length > 16000) {
    throw const FormatException('Prompt must contain 1–16000 characters.');
  }
  final ownedClient = httpClient == null;
  final client = httpClient ?? HttpClient();
  try {
    client.connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(
      Uri.parse('https://api.openai.com/v1/responses'))
      .timeout(const Duration(seconds: 18));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + key.trim());
    req.headers.contentType = ContentType.json;
    final payload = <String, dynamic>{
      'model': model.trim(),
      'input': input,
      'store': true,
      if (previousResponseId != null && previousResponseId.isNotEmpty)
        'previous_response_id': previousResponseId,
    };
    req.add(utf8.encode(jsonEncode(payload)));
    final res = await req.close().timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      // Don't expose raw provider errors containing sensitive details.
      throw HttpException('OpenAI API returned HTTP ' +
        res.statusCode.toString() +
        '. Check your key, model access, credits and connection.');
    }
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 90))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Provider response is too large.');
      }
    }
    return parseOpenAiResponse(utf8.decode(bytes));
  } finally {
    if (ownedClient) client.close(force: true);
  }
}
