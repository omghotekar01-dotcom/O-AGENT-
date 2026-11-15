import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/openai_responses.dart';

void main() {
  test('concatenates all genuine assistant output text blocks', () {
    final r = parseOpenAiResponse(jsonEncode({
      'id':'resp_valid','output':[
        {'type':'reasoning','summary':[]},
        {'type':'message','role':'assistant','content':[
          {'type':'output_text','text':'First result'},
          {'type':'refusal','text':'do not forward'}]},
        {'type':'message','role':'assistant','content':[
          {'type':'output_text','text':'Second result'}]},
      ],
    }));
    expect(r.id,'resp_valid');
    expect(r.text,'First result\n\nSecond result');
  });

  test('does not invent a response from non-text provider events', () {
    expect(() => parseOpenAiResponse(jsonEncode({
      'id':'resp_no_text','output':[{'type':'reasoning'}],
    })),throwsFormatException);
  });

  test('rejects missing IDs and unexpected JSON shapes', () {
    expect(() => parseOpenAiResponse('[]'),throwsFormatException);
    expect(() => parseOpenAiResponse(jsonEncode({
      'output':[{'type':'message','role':'assistant','content':[
        {'type':'output_text','text':'hello'}]}],
    })),throwsFormatException);
  });
}
