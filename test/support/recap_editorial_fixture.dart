import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'recap_display_fixture.dart';
import '../services/book_recap_client_test.dart' as base;

/// Original synthetic prose from the approved design, adapted to the real DTO.
/// No live account, server, model, or claim of independently verified book text.
class RecapEditorialFixture extends RecapDisplayFixture {
  static const book = '注意力与日常';
  static const localIds = [
    'local-a',
    'local-note',
    'local-correction',
    'local-addition',
  ];
  static const remoteIds = [
    base.remote,
    base.remote2,
    '88888888-8888-4888-8888-888888888888',
    '99999999-9999-4999-8999-999999999999',
  ];
  static const excerpt =
      '效率衡量事情完成得有多快，却不能替我们决定哪些事情值得完成。省下的时间可以留给停顿，也可能被更多任务填满。';
  static const pause = '停顿为看见细节留下空间。理解仍需要提问、比较和核对。';
  static const question = '如果工作仍然需要速度，怎样为重要的事保留注意力？';
  static const note = '我常把勾掉清单当成充实，却说不清今天真正理解了什么。';
  static const oldAnswer = '慢下来一定能让理解更深入，所以效率与理解不能兼得。';
  static const correction = '原文真的证明了慢下来一定能理解得更深吗？';
  static const correctedAnswer = '材料只谈到观察的空间，没有证明理解必然加深。';
  static const addition = '没有得到证明，不等于已经被排除。我还想看看具体的反例。';
  static String evidence(int n) => 'e-${n.toString() * 64}';
  List<Map<String, dynamic>> get evidenceRows => [
    for (final row in [
      (1, 0, 'book_excerpt', 'reader_context', excerpt),
      (2, 0, 'user_question', 'trace', question),
      (3, 0, 'historical_ai', 'trace', oldAnswer),
      (4, 1, 'user_note', 'trace', note),
      (5, 2, 'book_excerpt', 'reader_context', pause),
      (6, 2, 'user_question', 'trace', correction),
      (7, 2, 'historical_ai', 'trace', correctedAnswer),
      (8, 3, 'user_note', 'trace', addition),
    ])
      {
        'id': evidence(row.$1),
        'entry_id': remoteIds[row.$2],
        'follow_up_id': null,
        'kind': row.$3,
        'provenance': row.$4,
        'text': row.$5,
        'location': {
          'status': 'fragment_only',
          'exact': false,
          'chapter_index': '1',
          'chapter_title': '效率与停留',
        },
      },
  ];

  @override
  Future<void> init() async {
    debugPrint('editorial fixture: opening isolated database');
    await super.init();
    debugPrint('editorial fixture: base schema ready');
    windowMs =
        120000; // Explicit synthetic-test policy, never a production default.
    for (var i = 0; i < localIds.length; i++) {
      final reading = i == 0 || i == 2;
      final text = i == 0
          ? excerpt
          : i == 2
          ? pause
          : '';
      final row = {
        'id': localIds[i],
        'user_id': base.owner,
        'book_id': 'book-a',
        'book_title': book,
        'bmob_id': remoteIds[i],
        'source': reading ? 'ai_question' : 'thought',
        'original_text': text,
        'user_input': [question, note, correction, addition][i],
        'ai_explanation': i == 0
            ? oldAnswer
            : i == 2
            ? correctedAnswer
            : '',
        'metadata_json': jsonEncode({
          'origin': 'reader',
          if (reading)
            'reading_ai_context': {'scope': 'selection', 'selectedText': text},
        }),
        'created_at': '2026-01-01T00:00:00Z',
      };
      if (i == 0) {
        await db.update(
          'user_entries',
          row,
          where: 'id = ?',
          whereArgs: [localIds[i]],
        );
      } else {
        await db.insert('user_entries', row);
      }
    }
    debugPrint('editorial fixture: four synthetic records ready');
  }

  void decorateScope() {
    current['sources'] = [
      for (final id in remoteIds) {'entry_id': id, 'follow_up_ids': <String>[]},
    ];
    current['coverage'] = {
      ...base.coverage(),
      'availableEntries': 4,
      'includedEntries': 4,
    };
    current['evidence_summary'] = {'transmitted': 8, 'excluded_unverified': 0};
  }

  @override
  void resetResult() {
    super.resetResult();
    decorateScope();
    if (current['result'] == null || emptyResult) return;
    Map<String, dynamic> item(
      String id,
      String title,
      String summary,
      String basis,
      List<int> refs, {
      List<Map<String, dynamic>> quotes = const [],
    }) => {
      'id': id,
      'title': title,
      'summary': summary,
      'basis': basis,
      'evidenceRefs': refs.map(evidence).toList(),
      'quotes': quotes,
    };
    Map<String, dynamic> quote(int id, String text, String voice) => {
      'evidenceId': evidence(id),
      'text': text,
      'voice': voice,
    };
    current['result'] = {
      ...base.result(),
      'knowledge': [
        {
          ...item(
            'k1',
            '效率与注意力，回答不同的问题',
            '这几段阅读材料没有把效率放在生活的对立面。效率解决的是：一件事能否更省时地完成。注意力追问的则是：完成之后，什么仍然值得我们停留。如果省下的时间只是被更多任务填满，日程或许变得紧凑，我们却不一定更清楚自己真正关心什么。',
            'source_supported',
            [1],
            quotes: [quote(1, '效率衡量事情完成得有多快，却不能替我们决定哪些事情值得完成。', 'author')],
          ),
          'kind': 'concept',
        },
        {
          ...item(
            'k2',
            '慢不是答案，而是一种条件',
            '另一段材料把停顿与看见细节联系起来，但没有证明只要放慢节奏，就一定能理解得更深。更稳妥的读法是：停顿可能为观察留下空间，真正的理解还需要提问、比较和核对。这里应保留创造条件和保证结果的区别，也不必因此否定所有快速阅读。',
            'source_supported',
            [5],
          ),
          'kind': 'argument',
        },
      ],
      'relations': [
        {
          'id': 'r1',
          'from': 'k1',
          'to': 'k2',
          'type': 'complements',
          'basis': 'ai_inference',
          'explanation':
              '把这两条线索放在一起，可以尝试一个较温和的判断：我们未必需要把每件事都做得更慢，而是需要辨认哪些环节适合提速、哪些环节值得停下来核实。这是基于所选材料提出的思考方向，不是作者给出的行动清单。若要进一步判断它是否适用于自己的工作，还需要具体情境。',
          'evidenceRefs': [evidence(1), evidence(5)],
        },
      ],
      'myThinking': [
        item(
          'm1',
          '你问的，不只是怎样更有效率',
          '你的批注提到，自己有时会把完成清单当作一天充实的证明，却不一定记得当天真正理解了什么。随后，你提出了一个更具体的问题：如果工作仍然需要速度，怎样为重要的事保留注意力？这可以整理成一条待探索的线索，而不是你已经认同慢生活的结论。',
          'user_explicit',
          [4, 2],
          quotes: [quote(4, note, 'user'), quote(2, question, 'user')],
        ),
        item(
          'm2',
          '讨论中的一次修正，仍值得保留',
          '历史回答曾把慢下来说成理解的保证。你追问原文是否真的证明了这一点，并指出没有得到证明不等于已经被排除。这次回望保留这段纠错：当前片段不足以证明慢与理解之间必然存在因果关系，也不足以断言两者毫无联系。历史 AI 回答只用于恢复讨论，不作为书籍事实。',
          'user_explicit',
          [6, 3, 7, 8],
          quotes: [
            quote(3, oldAnswer, 'historical_ai'),
            quote(8, addition, 'user'),
          ],
        ),
      ],
      'openQuestions': [
        item(
          'o1',
          '什么样的观察才足以支持判断？',
          '当前讨论还没有具体比较工作中不同节奏的效果。可以保留这个问题，不把一次自我观察扩大成固定的人格或长期立场。',
          'ai_inference',
          [6, 8],
        ),
      ],
      'nextQuestions': [
        item(
          'n1',
          '最近一次省下时间后，我把注意力交给了什么？',
          '从一次具体经历出发，而不是先评价生活方式。可以回想当时看见了什么、忽略了什么，再判断更快或更慢是否真的改变了理解。不需要一次回答所有问题。',
          'ai_inference',
          [1, 4],
        ),
        item(
          'n2',
          '怎样区分停留得更久和理解得更深？',
          '需要什么观察或反例，才能支持这种判断？这些是沿着已有材料提出的思考建议，不是原文结论，也不是对个人能力的评价。',
          'ai_inference',
          [5, 8],
        ),
      ],
    };
  }

  @override
  Future<http.Response> respond(http.Request req) async {
    final response = await super.respond(req);
    if (response.statusCode != 200) return response;
    final action = req.url.path.split('/').last;
    if (action == 'prepare') {
      decorateScope();
      return ok(current);
    }
    if (action == 'scope') {
      return ok({
        ...scope,
        'evidence_catalog': [
          for (final row in evidenceRows)
            {...row}
              ..remove('text')
              ..remove('location'),
        ],
        'requires_local_confirmation': true,
      });
    }
    if (action == 'evidence') {
      final ids = jsonDecode(req.body)['evidence_ids'] as List;
      return ok({
        'evidence': evidenceRows
            .where((row) => ids.contains(row['id']))
            .toList(),
        'display': grant(),
      });
    }
    if (action == 'follow-ups' && req.method == 'GET') {
      for (final turn in turns) {
        turn['answer']['parts'][0]['text'] =
            '当前材料只谈到观察的空间。可以保留这个问题，而不把停顿当成理解的保证。';
        turn['answer']['parts'][0]['evidenceRefs'] = [evidence(5)];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      data['turns'] = turns;
      data['coverage'] = current['coverage'];
      return ok(data);
    }
    return response;
  }
}
