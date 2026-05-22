import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/services/ai_service.dart';
import 'package:ai_reader/models/ai_conversation.dart';

/// ⚠️ 这是一个模板，展示如何为调用外部 API 的 Service 写测试。
///
/// 当前 AiService 直连 DeepSeek API（产品文档要求走后端，待迁移）。
/// 迁移到后端 `/api/ai/explain` 后，可以用 MockClient 拦截 HTTP 请求。
///
/// 要启用以下测试，先在 pubspec.yaml 的 dev_dependencies 中加入：
///   mockito: ^5.4.0
///   build_runner: ^2.4.0
///
/// 然后运行：
///   dart run build_runner build
/// 生成 mock 文件后，取消注释下方的 import 和测试代码。

void main() {
  group('AiService (待迁移到后端后启用)', () {
    // ---- 测试 1：消息构造逻辑（纯函数，无需 mock） ----

    test('API Key 为空时抛出明确异常', () async {
      // AiService 从 SharedPreferences 读取 API Key。
      // 未配置 Key 时调用 explain() 应抛出可读异常。
      // 当前实现：throw Exception('请先在设置中配置 DeepSeek API Key')

      // 这个测试验证异常消息的格式，确保用户看到的提示是中文的。
      // 实际需要 mock SharedPreferences，此处保留为模板。
    });

    // ---- 测试 2：请求体结构（迁移到后端后启用） ----
    //
    // test('explain 请求体包含必要字段', () async {
    //   final mockClient = MockClient();
    //   final service = AiService(client: mockClient);
    //
    //   when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
    //       .thenAnswer((_) async => http.Response(
    //             '{"choices":[{"message":{"content":"解释内容"}}]}',
    //             200,
    //           ));
    //
    //   final result = await service.explain(
    //     selectedText: '测试文本',
    //     contextBefore: '上文',
    //     contextAfter: '下文',
    //     bookTitle: '测试书',
    //     bookAuthor: '作者',
    //   );
    //
    //   // 验证请求体结构
    //   final captured = verify(mockClient.post(
    //     captureAny,
    //     headers: captureAnyNamed('headers'),
    //     body: captureAnyNamed('body'),
    //   )).captured;
    //
    //   final body = jsonDecode(captured[2] as String);
    //   expect(body['model'], isNotEmpty);
    //   expect(body['messages'], isA<List>());
    //   expect(body['messages'].length, greaterThanOrEqualTo(2));
    //
    //   expect(result, '解释内容');
    // });

    // ---- 测试 3：HTTP 错误处理 ----
    //
    // test('API 返回非 200 时抛出异常', () async {
    //   final mockClient = MockClient();
    //   final service = AiService(client: mockClient);
    //
    //   when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
    //       .thenAnswer((_) async => http.Response(
    //             '{"error":{"message":"API Key 无效"}}',
    //             401,
    //           ));
    //
    //   expect(
    //     () => service.explain(
    //       selectedText: '测试',
    //       contextBefore: '',
    //       contextAfter: '',
    //       bookTitle: '',
    //       bookAuthor: '',
    //     ),
    //     throwsA(isA<Exception>()),
    //   );
    // });
  });
}
