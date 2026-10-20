import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reply_app/services/summary_service.dart';

void main() {
  group('SummaryService.parseSummary', () {
    test('解析纯 JSON', () {
      const raw =
          '{"title":"测试标题","summary":"这是摘要","keyPoints":["a","b"],"tags":["t"]}';
      final r = SummaryService.parseSummary(raw);
      expect(r.title, '测试标题');
      expect(r.summary, '这是摘要');
      expect(r.keyPoints, ['a', 'b']);
      expect(r.tags, ['t']);
    });

    test('解析被代码块包裹的 JSON', () {
      const raw =
          '```json\n{"title":"T","summary":"S","keyPoints":["k1"],"tags":[]}\n```';
      final r = SummaryService.parseSummary(raw);
      expect(r.title, 'T');
      expect(r.summary, 'S');
      expect(r.keyPoints, ['k1']);
    });

    test('解析夹杂在文字中的 JSON', () {
      const raw =
          '好的，以下是归档结果：\n{"title":"T","summary":"S","keyPoints":["k1"],"tags":["x"]}\n希望有帮助。';
      final r = SummaryService.parseSummary(raw);
      expect(r.title, 'T');
      expect(r.summary, 'S');
      expect(r.keyPoints, ['k1']);
    });

    test('keyPoints 缺失时返回空列表', () {
      const raw = '{"title":"T","summary":"S"}';
      final r = SummaryService.parseSummary(raw);
      expect(r.title, 'T');
      expect(r.summary, 'S');
      expect(r.keyPoints, isEmpty);
      expect(r.tags, isEmpty);
    });

    test('非法输入回退为原文摘要', () {
      const raw = '这不是 JSON';
      final r = SummaryService.parseSummary(raw);
      expect(r.title, '未命名');
      expect(r.summary, '这不是 JSON');
      expect(r.keyPoints, isEmpty);
    });
  });
}
