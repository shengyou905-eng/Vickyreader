enum AiExplainMode { auto, plain, structure, concept, argument }

extension AiExplainModeInfo on AiExplainMode {
  String get apiValue => switch (this) {
    AiExplainMode.auto => 'auto',
    AiExplainMode.plain => 'plain',
    AiExplainMode.structure => 'structure',
    AiExplainMode.concept => 'concept',
    AiExplainMode.argument => 'argument',
  };

  String get label => switch (this) {
    AiExplainMode.auto => '自动',
    AiExplainMode.plain => '通俗',
    AiExplainMode.structure => '拆解',
    AiExplainMode.concept => '概念',
    AiExplainMode.argument => '论证',
  };

  String get fullLabel => switch (this) {
    AiExplainMode.auto => '小U解读',
    AiExplainMode.plain => '通俗解释',
    AiExplainMode.structure => '结构拆解',
    AiExplainMode.concept => '概念辨析',
    AiExplainMode.argument => '论证脉络',
  };

  String get loadingText => switch (this) {
    AiExplainMode.auto => '小U正在判断这段难在哪里…',
    AiExplainMode.plain => '小U正在换一种说法…',
    AiExplainMode.structure => '小U正在拆开句子结构…',
    AiExplainMode.concept => '小U正在辨清概念边界…',
    AiExplainMode.argument => '小U正在还原论证脉络…',
  };
}
