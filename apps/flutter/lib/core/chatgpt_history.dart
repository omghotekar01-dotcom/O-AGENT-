import 'dart:convert';

/// User-selected ChatGPT data export snapshot. Not an account API, live sync,
/// credential connection, or authorization to replay messages into ChatGPT.
class ChatGptMessage {
  const ChatGptMessage({required this.role, required this.text});
  final String role;
  final String text;
}

class ChatGptConversation {
  const ChatGptConversation({
    required this.id, required this.title, required this.messages,
    this.updatedAt,
  });
  final String id;
  final String title;
  final List<ChatGptMessage> messages;
  final DateTime? updatedAt;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
String _string(Object? value) => value is String ? value : '';
DateTime? _time(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(),
      isUtc: true).toLocal();
  }
  return null;
}

/// A ChatGPT export can contain multiple conversation branches. Follow
/// current_node -> parent to display the chosen branch, not unrelated edits.
List<ChatGptMessage> _messages(Map<String, dynamic> record) {
  final mapping = _map(record['mapping']);
  if (mapping.isEmpty) return const [];
  final chain = <Map<String, dynamic>>[];
  final seen = <String>{};
  var current = _string(record['current_node']);
  if (current.isNotEmpty && mapping.containsKey(current)) {
    while (current.isNotEmpty && seen.add(current) && chain.length < 30000) {
      final node = _map(mapping[current]);
      chain.add(node);
      current = _string(node['parent']);
    }
    chain.reversed.toList();
  }
  // Older exports do not always have a current_node field.
  final nodes = chain.isNotEmpty
      ? chain.reversed.toList()
      : mapping.values.map(_map).toList()
          ..sort((a, b) {
            final ma = _map(a['message']), mb = _map(b['message']);
            return ((_map(ma)['create_time'] as num?) ?? 0)
              .compareTo(((_map(mb)['create_time'] as num?) ?? 0));
          });
  final result = <ChatGptMessage>[];
  for (final node in nodes) {
    final message = _map(node['message']);
    if (message.isEmpty) continue;
    final role = _string(_map(message['author'])['role']);
    if (role != 'user' && role != 'assistant') continue;
    final content = _map(message['content']);
    final parts = content['parts'];
    String body = '';
    if (parts is List) {
      body = parts.whereType<String>().join('\n').trim();
    } else if (content['text'] is String) {
      body = (content['text'] as String).trim();
    }
    // Do not pretend unavailable image/tool/media payloads are readable.
    if (body.isEmpty) continue;
    if (body.length > 100000) body = body.substring(0, 100000);
    result.add(ChatGptMessage(role: role, text: body));
    if (result.length >= 12000) break;
  }
  return result;
}

/// Never modifies source content or sends an imported chat to a server.
/// It is a local, read-only snapshot, not a resumable ChatGPT conversation.
List<ChatGptConversation> parseChatGptExport(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) {
    throw const FormatException(
      'Expected conversations.json from an official ChatGPT data export.');
  }
  final result = <ChatGptConversation>[];
  for (final value in decoded) {
    if (value is! Map) continue;
    final record = _map(value);
    final id = _string(record['id']);
    if (id.isEmpty) continue;
    final title = _string(record['title']).trim();
    result.add(ChatGptConversation(
      id: id,
      title: title.isEmpty ? 'Untitled conversation' : title,
      updatedAt: _time(record['update_time'] ?? record['create_time']),
      messages: _messages(record),
    ));
    if (result.length >= 20000) break;
  }
  result.sort((a, b) =>
    (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
      .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
  return result;
}
