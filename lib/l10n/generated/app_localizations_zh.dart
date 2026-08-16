// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '知读';

  @override
  String get appTagline => '让阅读痕迹慢慢显影';

  @override
  String get tabBookshelf => '书架';

  @override
  String get tabXiaou => '小U';

  @override
  String get tabFreeNotes => '随心记';

  @override
  String get tabMingtai => '明台';

  @override
  String get settings => '设置';

  @override
  String get account => '账户';

  @override
  String get appearance => '界面氛围';

  @override
  String get language => '语言';

  @override
  String get languageSubtitle => '跟随系统或选择界面语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get featureGuide => '功能引导';

  @override
  String get viewGuideAgain => '重新查看功能引导';

  @override
  String get viewGuideAgainSubtitle => '下次进入对应场景时，再看一次简短提示';

  @override
  String get guideResetMessage => '功能引导已重置，将在下次进入对应场景时出现';

  @override
  String get about => '关于';

  @override
  String versionLabel(Object version) {
    return '版本 $version';
  }

  @override
  String get aboutTagline => 'AI 辅助阅读，让每本书都更易懂';

  @override
  String get loginRegister => '登录 / 注册';

  @override
  String get notSignedIn => '未登录';

  @override
  String get signInSyncSubtitle => '登录后同步阅读进度和小U条目';

  @override
  String get myReadingProfile => '我的阅读档案';

  @override
  String get myReadingProfileSubtitle => '头像、昵称、在读书籍与公开想法';

  @override
  String get cloudAccountConnected => '已连接云端账号';

  @override
  String get switchAccount => '切换账户';

  @override
  String get logout => '退出登录';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get deleteAccountTitle => '注销知读账号';

  @override
  String get deleteAccountBody =>
      '账号、云端阅读记录、随心记、小U对话和公开内容将被永久删除。设备中的本地电子书不会自动删除。此操作无法撤销。';

  @override
  String get currentPassword => '当前密码';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get deletePermanently => '永久注销';

  @override
  String get accountDeleted => '账号及云端关联数据已删除';

  @override
  String deleteAccountFailed(Object error) {
    return '注销失败：$error';
  }

  @override
  String get privacySecurity => '隐私与安全';

  @override
  String get aiDataAuthorization => 'AI 与数据授权';

  @override
  String get aiDataAuthorizationSubtitle => '管理小U、模型服务、数据使用与撤回授权';

  @override
  String get mingtaiPrivacyAndVisibility => '明台隐私与公开';

  @override
  String get mingtaiPrivacyAndVisibilitySubtitle => '管理阅读状态、进度、关注和动态的公开范围';

  @override
  String get communitySafety => '社区安全';

  @override
  String get communitySafetySubtitle => '社区规范、举报、屏蔽与联系邮箱';

  @override
  String get privacyDataInfo => '隐私与数据说明';

  @override
  String get privacyDataInfoSubtitle => '查看隐私政策、收集清单及第三方服务';

  @override
  String get signInToManagePrivacy => '登录后可管理与账号关联的隐私设置';

  @override
  String get deletingAccount => '正在注销…';

  @override
  String get xiaouThirdPartyAi => '小U与第三方 AI';

  @override
  String get xiaouThirdPartyAiSubtitle => '查看或撤回 DeepSeek 数据处理授权';

  @override
  String get mingtaiVisibility => '明台公开范围';

  @override
  String get mingtaiVisibilitySubtitle => '控制阅读状态、进度、关注和同书发现';

  @override
  String get communityRules => '社区规范与举报';

  @override
  String get communityRulesSubtitle => '查看公开内容规范和联系邮箱';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get privacyPolicySubtitle => '知读如何处理和保护你的数据';

  @override
  String get dataCollectionList => '个人信息收集清单';

  @override
  String get dataCollectionListSubtitle => '逐项查看信息、用途、上传与保存期限';

  @override
  String get thirdPartyList => '第三方服务清单';

  @override
  String get thirdPartyListSubtitle => '云服务、DeepSeek 与 Apple 系统能力';

  @override
  String get aiDataProcessing => 'AI 功能与数据处理';

  @override
  String get aiDataProcessingSubtitle => '小U会发送什么，以及如何撤回授权';

  @override
  String get accountDataDeletion => '账号与数据删除';

  @override
  String get accountDataDeletionSubtitle => '注销路径、删除范围和处理时间';

  @override
  String get pageUnavailable => '页面暂时无法打开，请检查网络后重试。';

  @override
  String get retry => '重试';

  @override
  String get authAccount => '账号';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get welcomeBack => '欢迎回来';

  @override
  String get createAccount => '创建账号';

  @override
  String get loginSubtitle => '登录以同步你的阅读数据';

  @override
  String get registerSubtitle => '注册后可在多设备同步阅读进度和笔记';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get enterEmail => '请输入邮箱';

  @override
  String get invalidEmail => '邮箱格式不正确';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get passwordMinLength => '密码至少 6 位';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get forgotPasswordTitle => '找回密码';

  @override
  String get forgotPasswordSubtitle => '输入注册邮箱，我们会发送一封 30 分钟内有效的重置邮件。';

  @override
  String get sendResetEmail => '发送重置邮件';

  @override
  String get passwordResetEmailSent => '如果该邮箱已注册，我们会发送一封密码重置邮件。';

  @override
  String get resetPasswordTitle => '设置新密码';

  @override
  String get resetPasswordSubtitle => '新密码设置成功后，其他设备上的旧登录会立即失效。';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmNewPassword => '再次输入新密码';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';

  @override
  String get resetPassword => '重置密码';

  @override
  String get passwordResetSuccess => '密码已重置，请重新登录。';

  @override
  String get backToLogin => '返回登录';

  @override
  String get orUseApple => '或';

  @override
  String get bindApple => '绑定 Apple';

  @override
  String get appleLinked => '已绑定 Apple';

  @override
  String get appleBindingSuccess => 'Apple 账号已绑定';

  @override
  String get appleAccountDeleteConfirm =>
      '此账号使用 Apple 登录。确认后将撤销 Apple 授权并永久注销账号。';

  @override
  String get localDataMergeNotice => '注册后，你之前在本机的所有数据会自动合并到新账号';

  @override
  String get importBook => '导入书籍';

  @override
  String get importEbook => '导入电子书';

  @override
  String get supportedBookFormats => '支持 EPUB · TXT · PDF';

  @override
  String get importLocalFile => '从本地文件导入';

  @override
  String get importLocalFileSubtitle => '选择 EPUB、TXT 或 PDF 文件';

  @override
  String get downloadFromLink => '从链接下载';

  @override
  String get downloadFromLinkSubtitle => '输入 EPUB、TXT 或 PDF 下载地址';

  @override
  String get downloadLinkHint => '请输入 EPUB / TXT / PDF 文件的下载链接';

  @override
  String get download => '下载';

  @override
  String get emptyBookshelf => '书架空空如也';

  @override
  String get emptyBookshelfSubtitle => '导入你的第一本电子书吧';

  @override
  String get shareReadingThought => '分享阅读想法';

  @override
  String get shareReadingThoughtSubtitle => '只关联书籍信息，不上传电子书文件';

  @override
  String get legacyPublicBookDisabled => '旧明台借阅入口已停用。请在私人书架重新导入你合法获得的电子书。';

  @override
  String get deleteBook => '删除书籍';

  @override
  String deleteBookConfirm(Object title) {
    return '确定要删除《$title》吗？\n相关的笔记和标注也会被删除。';
  }

  @override
  String get settingsTooltip => '设置';

  @override
  String get refreshFailedRetained => '刷新失败，现有内容已保留。';

  @override
  String get bookshelfUnavailable => '书架暂时没有打开';

  @override
  String get bookmarks => '书签';

  @override
  String get tableOfContents => '目录';

  @override
  String get reloadContent => '重新载入正文';

  @override
  String get readerOpenFailed => '书籍打开失败';

  @override
  String get readerAskXiaou => '问小U';

  @override
  String get readerAskCompact => '提问';

  @override
  String get readerExplain => '小U解读';

  @override
  String get readerExplainCompact => '解读';

  @override
  String get readerThought => '写想法';

  @override
  String get readerThoughtCompact => '想法';

  @override
  String get readerHighlight => '保存划线';

  @override
  String get readerTranslate => '翻译';

  @override
  String get readerClose => '关闭';

  @override
  String get privateOnly => '仅自己可见';

  @override
  String get shareToMingtai => '分享到明台';

  @override
  String get thoughtSavedPrivate => '想法已保存为私密';

  @override
  String get publishedToMingtai => '已发布到明台';

  @override
  String get aiGeneratedNotice => '由 AI 生成，可能存在错误，请结合原文判断。';

  @override
  String get freeNotesTitle => '随心记';

  @override
  String get freeNotesSubtitle => '留一处安静的地方，写下此刻经过心里的事';

  @override
  String get writeNote => '写一笔';

  @override
  String get searchFreeNotes => '找一找曾经写下的句子';

  @override
  String get writeWhatYouThink => '写下此刻想到的。';

  @override
  String get todayEcho => '今日回响';

  @override
  String get privateOnlyNote => '仅自己可见';

  @override
  String get save => '保存';

  @override
  String get saving => '保存中...';

  @override
  String get deleteRecord => '删除记录';

  @override
  String get deleteRecordConfirm => '这条随心记会从你的私密记录中删除，删除后不可恢复。';

  @override
  String get titleOptional => '标题（可选）';

  @override
  String get noteBodyHint => '不必整理，也不必解释。\n写下此刻经过心里的东西...';

  @override
  String get xiaouTitle => '小U';

  @override
  String get readingTraces => '阅读痕迹';

  @override
  String get searchTraces => '找一句话、一本书或一个想法';

  @override
  String get allBooks => '全部书籍';

  @override
  String get all => '全部';

  @override
  String get thoughts => '想法';

  @override
  String get highlights => '划线';

  @override
  String get xiaouExplanations => '小U解读';

  @override
  String get xiaouQuestions => '问小U';

  @override
  String get importantOnly => '仅看重要';

  @override
  String get expand => '展开';

  @override
  String get collapse => '收起';

  @override
  String get delete => '删除';

  @override
  String get undo => '撤销';

  @override
  String get markImportant => '标记重要';

  @override
  String get unmarkImportant => '取消重要';

  @override
  String get chatWithXiaou => '和小U说话';

  @override
  String get askXiaouDirectly => '直接问小U...';

  @override
  String get newConversation => '新对话';

  @override
  String get conversationHistory => '和小U说过的话';

  @override
  String get saveToFreeNotes => '保存到随心记';

  @override
  String get mingtaiTitle => '明台';

  @override
  String get mingtaiSearch => '找一本书、作者或一句话';

  @override
  String get recommended => '推荐';

  @override
  String get following => '关注';

  @override
  String get readingTogether => '同读';

  @override
  String get leaveReadingTrace => '留下一段阅读';

  @override
  String get loginToJoin => '登录后才能参与明台讨论';

  @override
  String get reply => '回应';

  @override
  String get quoteReply => '引用回应';

  @override
  String get favorite => '收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get viewSameBook => '查看同书';

  @override
  String get notifications => '明台消息';

  @override
  String get noNotifications => '这里还没有新的回声。';

  @override
  String get report => '举报';

  @override
  String get blockUser => '拉黑用户';

  @override
  String get loading => '正在加载…';

  @override
  String get empty => '这里暂时还没有内容。';

  @override
  String get networkSlow => '网络似乎有些慢，请稍后重试。';

  @override
  String get close => '关闭';

  @override
  String get clear => '清除';

  @override
  String get stop => '停止';

  @override
  String get send => '发送';

  @override
  String get tryIt => '试一下';

  @override
  String get gotIt => '我知道了';

  @override
  String get syncFailedLocalRetained => '同步暂时失败，已保留本机记录。';

  @override
  String get readerQuestionSelection => '所选文字';

  @override
  String get readerQuestionPage => '当前页';

  @override
  String get readerQuestionChapter => '本章';

  @override
  String get readerQuestionPrompt => '可以问一个具体的问题。\n小U会把回答放回你眼前的文字里。';

  @override
  String get readerQuestionHint => '就眼前的文字问小U…';

  @override
  String get readerQuestionEmpty => '小U暂时没有看清，可以换一种问法再试一次。';

  @override
  String get readerQuestionSaveFailed => '回答已经生成，但这次记录暂时没有同步成功。';

  @override
  String get readerQuestionThinking => '小U正在读这一段…';

  @override
  String get readingTypography => '阅读排版';

  @override
  String get resetDefaults => '恢复默认';

  @override
  String get readingPreview => '阅读效果';

  @override
  String get font => '字体';

  @override
  String get fontSystem => '默认';

  @override
  String get fontSerif => '宋体';

  @override
  String get fontWenkai => '文楷';

  @override
  String get typography => '排版';

  @override
  String get fontSize => '字号';

  @override
  String get lineHeight => '行距';

  @override
  String get pageMargin => '页边距';

  @override
  String get pagingMode => '翻页方式';

  @override
  String get verticalScroll => '上下滚动';

  @override
  String get horizontalPaging => '左右翻页';

  @override
  String get paperBackground => '纸张背景';

  @override
  String get paperWhite => '白色';

  @override
  String get paperSepia => '米纸';

  @override
  String get paperGreen => '护眼';

  @override
  String get paperDark => '夜间';

  @override
  String get readerGuideTitle => '长按任意文字';

  @override
  String get readerGuideBody => '可以提问、解读、划线，或记下想法。';

  @override
  String get readerGuideSelectionTip => '在这里向小U提问，或查看解读。';

  @override
  String get xiaouGuideTitle => '这是小U。';

  @override
  String get xiaouGuideBody => '有疑问、想继续追问，或回望阅读痕迹时，点亮它。';

  @override
  String get xiaouGuideAction => '点一下看看';

  @override
  String get mingtaiGuideTitle => '欢迎来到明台';

  @override
  String get mingtaiGuideBody =>
      '在这里，你可以阅读大家公开分享的阅读片段、想法和书评，也可以分享自己的阅读痕迹，与其他读者讨论。';

  @override
  String get mingtaiGuidePrivacy => '你的内容默认保持私人，只有主动确认后才会公开。';

  @override
  String get browseMingtai => '逛逛明台';

  @override
  String get learnSharing => '看看如何分享';

  @override
  String get sharingIsYourChoice => '分享由你决定';

  @override
  String get sharingGuideBody =>
      '在阅读页选中文字，写下想法后选择“分享到明台”；也可以从明台右下角留下一段阅读。每次发布前都会让你确认，私人记录不会自动公开。';

  @override
  String get newFreeNote => '新建记录';

  @override
  String get freeNotesSyncUnavailable => '暂时没能同步随心记';

  @override
  String get freeNotesSyncRetained => '本机记录没有被清空，网络恢复后可以重新加载。';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get backToThatDay => '回到那一天';

  @override
  String get thatDay => '那一天';

  @override
  String createdOnEditedOn(Object created, Object updated) {
    return '写于 $created · 最近编辑 $updated';
  }

  @override
  String createdOn(Object created) {
    return '写于 $created';
  }

  @override
  String get earlier => '更早以前';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get thisWeek => '本周';

  @override
  String get thisMonth => '本月';

  @override
  String get untitledMoment => '未命名的片刻';

  @override
  String get xiaouLoadRetained => '暂时无法刷新，已保留上次看到的内容。';

  @override
  String deletedEntry(Object type) {
    return '已删除$type';
  }

  @override
  String deleteFailed(Object error) {
    return '删除失败：$error';
  }

  @override
  String importanceSaveFailed(Object error) {
    return '重要标记保存失败：$error';
  }

  @override
  String get noMatchingTraces => '这里暂时没有找到对应的阅读痕迹。';

  @override
  String get noNewTraces => '还没有拿到新的阅读痕迹，可以稍后重试。';

  @override
  String get tracesEmptyBody => '划线、想法和小U解读会被安静地记在这里。';

  @override
  String get xiaouDiscovery => '小U发现了一件事';

  @override
  String get xiaouChatSubtitle => '直接问。小U会尽量把问题放回你的阅读里。';

  @override
  String get xiaouStartFromReading => '从正在读的地方开始';

  @override
  String get xiaouStartBody => '你可以直接输入，也可以先从下面的一件事开始。';

  @override
  String get xiaouThinking => '小U正在回看你的阅读痕迹…';

  @override
  String get conversationDeleteTitle => '删除这段对话？';

  @override
  String get conversationDeleteBody => '删除后无法恢复，但已经存入随心记的内容不会受到影响。';

  @override
  String get noConversationHistory => '还没有保存过的对话。';

  @override
  String get mingtaiUnavailable => '明台暂时没有打开';

  @override
  String get tryAgain => '再试一次';

  @override
  String get shareCurrentReading => '分享正在读';

  @override
  String get shareCurrentReadingSubtitle => '说说此刻读到哪里';

  @override
  String get publishHighlight => '公开划线';

  @override
  String get publishHighlightSubtitle => '分享一小段原文与停留的原因';

  @override
  String get writeThought => '写下想法';

  @override
  String get writeThoughtSubtitle => '留下你对这本书的理解';

  @override
  String get writeReview => '写书评';

  @override
  String get writeReviewSubtitle => '写一段完整而克制的读后回声';

  @override
  String get mingtaiComposeTitle => '留下一段阅读';

  @override
  String get mingtaiComposePrivacy => '每一条公开内容都需要关联一本书。';

  @override
  String get loginRequiredMingtai => '登录后才能参与明台讨论';

  @override
  String get noMeaningfulMingtaiContent => '明台还在等第一句话。';

  @override
  String get startWithBook => '从一本正在读的书开始，留下一个真实的问题或想法。';

  @override
  String get sameBookSpace => '同读空间';

  @override
  String get publicExpressions => '公开想法与问题';

  @override
  String get xiaouAsksMe => '小U问我';

  @override
  String get xiaouAsksSubtitle => '从你的阅读里开始一场开放对谈。';

  @override
  String get chatHistory => '历史记录';

  @override
  String get conversationActions => '对话操作';

  @override
  String get saveWholeConversation => '整段存入随心记';

  @override
  String get changeQuestion => '换个问题';

  @override
  String get endConversation => '结束对谈';

  @override
  String get xiaouAnswerHint => '回答、反问，或继续说…';

  @override
  String get xiaouAskMeSubtitle => '让小U从你的阅读里提出一个问题';

  @override
  String get quickExplainLabel => '解读刚才读到的内容';

  @override
  String get quickExplainPrompt => '请结合我最近读到的内容，帮我看清其中最需要理解的一处。';

  @override
  String get quickReviewLabel => '回顾我的划线与批注';

  @override
  String get quickReviewPrompt => '请回看我最近的划线与批注，告诉我其中有没有值得继续追问的联系。';

  @override
  String get quickBookChatLabel => '和小U聊聊这本书';

  @override
  String get quickBookChatPrompt => '请从我最近正在读的书开始，陪我聊聊我停留最多的那个问题。';

  @override
  String get sameBookReaders => '同书读者';

  @override
  String get latest => '最新';

  @override
  String get mostDiscussed => '热议';

  @override
  String get nearMyProgress => '与你读到相近位置';

  @override
  String get publicExcerpt => '公开摘录';

  @override
  String get fragmentThought => '片段想法';

  @override
  String get readingReflection => '阅读感受';

  @override
  String get bookReview => '书评';

  @override
  String get publicReadingExpressions => '这本书下的公开表达';

  @override
  String get noSameBookThoughts => '还没有人认真写下这本书带来的问题。';

  @override
  String get selectBook => '关联书籍';

  @override
  String get postType => '这是一段';

  @override
  String get shortExcerpt => '短摘录';

  @override
  String get shortExcerptOptional => '短摘录（可选）';

  @override
  String get shortExcerptHint => '只摘录讨论所需的一小段原文';

  @override
  String get readingPositionOptional => '阅读位置（可选）';

  @override
  String get readingPositionHint => '例如：第一卷 第三章';

  @override
  String get publishing => '正在发布…';

  @override
  String get publishToMingtai => '发布到明台';

  @override
  String get continueDiscussion => '围绕这段阅读继续讨论';

  @override
  String get noReplies => '还没有人回应。';

  @override
  String get writeReply => '写下回应…';

  @override
  String get selectQuote => '选择要回应的一句话';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(Object count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String get explainModeAuto => '自动';

  @override
  String get explainModePlain => '通俗';

  @override
  String get explainModeStructure => '拆解';

  @override
  String get explainModeConcept => '概念';

  @override
  String get explainModeArgument => '论证';

  @override
  String get explainModeAutoFull => '小U解读';

  @override
  String get explainModePlainFull => '通俗解释';

  @override
  String get explainModeStructureFull => '结构拆解';

  @override
  String get explainModeConceptFull => '概念辨析';

  @override
  String get explainModeArgumentFull => '论证脉络';

  @override
  String get xiaouOrganizing => '小U正在组织语言';

  @override
  String get followUpHint => '继续问一句…';

  @override
  String get passageUnavailable => '这一段暂时没能打开，请稍后重试。';

  @override
  String get aiLoginRequired => '登录后才能使用小U';

  @override
  String get aiConsentTitle => '使用小U前，请先了解';

  @override
  String get aiConsentBody =>
      '为生成小U解读，你选择的原文、相关上下文、提问和必要的阅读痕迹将发送至第三方人工智能服务 DeepSeek 处理。\n\n小U全局对话还可能使用你的划线、想法和小U解读。随心记和私人书籍文件不会发送。\n\n请不要提交身份证、医疗信息、密码等敏感个人信息。AI 生成内容可能存在错误，请结合原文判断。';

  @override
  String get decline => '暂不同意';

  @override
  String get agreeContinue => '同意并继续';

  @override
  String aiConsentLoadFailed(Object error) {
    return '暂时无法读取 AI 授权状态：$error';
  }

  @override
  String aiConsentSaveFailed(Object error) {
    return '保存授权失败：$error';
  }

  @override
  String get view => '查看';

  @override
  String get writeThoughtFirst => '先写下你的想法';

  @override
  String get publicThoughtMinLength => '公开想法至少需要 5 个字';

  @override
  String get thoughtPrompt => '这段文字让你想到什么？';

  @override
  String get privateThoughtExplanation => '保存在私人阅读记录中，不会自动公开。';

  @override
  String get publicThoughtExplanation => '这段话会出现在书页边缘。未发布的记录仍只属于你。';

  @override
  String get keepPrivate => '暂时留给自己';

  @override
  String get loginToPublish => '登录后才能公开到明台';

  @override
  String get writeThisMoment => '写下此刻';

  @override
  String get returnToThisPage => '回到这一页';

  @override
  String get privatePageSubtitle => '只属于你的私人书页';

  @override
  String get more => '更多';

  @override
  String get authorizeXiaou => '交给小U思考';

  @override
  String get revokeXiaou => '撤回小U授权';

  @override
  String get shareText => '分享文本';

  @override
  String get shareImage => '分享图片';

  @override
  String get authorizedToXiaou => '已授权给小U · 可随时撤回';

  @override
  String get noSearchResultTitle => '没有找到那句话';

  @override
  String get noSearchResultBody => '换个词，再慢慢找找';

  @override
  String get noBookmarks => '还没有书签';

  @override
  String get deleteBookmarkTitle => '删除书签';

  @override
  String get deleteBookmarkBody => '确定要删除这个书签吗？';

  @override
  String get expandFullExplanation => '展开完整解读';

  @override
  String followUpCount(Object count) {
    return '已继续追问 $count 次';
  }

  @override
  String followUpCountWithQuestion(Object count, Object question) {
    return '$count 次追问 · $question';
  }

  @override
  String chapterNumber(Object number) {
    return '第 $number 章';
  }

  @override
  String get chapterUnknown => '章节未记录';

  @override
  String get bookUnknown => '未记录书名';

  @override
  String get selectedPassage => '选中的原文';

  @override
  String get xiaouInterpretation => '小U的解读';

  @override
  String get followUpsUnavailable => '追问记录暂时没有同步，请稍后再试。';

  @override
  String get continueFollowUp => '继续追问';

  @override
  String get xiaouThinkingSentence => '小U正在想这一句…';

  @override
  String get traceType => '阅读痕迹';

  @override
  String get originalHighlight => '原始划线';

  @override
  String get bookTracesTitle => '这本书的阅读痕迹';

  @override
  String personalTraceCount(Object count) {
    return '$count 条属于你的阅读痕迹';
  }

  @override
  String get noBookTraces => '这里暂时没有对应的阅读痕迹。';

  @override
  String get topic => '主题';

  @override
  String get lookBack => '回望';

  @override
  String excerptCountRecent(Object count, Object date) {
    return '$count 条摘录 · 最近记录 $date';
  }

  @override
  String entryCount(Object count) {
    return '$count 条';
  }

  @override
  String get noTopicEntries => '这个主题下还没有条目';

  @override
  String get dateUnavailable => '暂无';

  @override
  String get unnamedBook => '未命名书籍';

  @override
  String topicRelatedSummary(Object topics) {
    return '小U轻轻看了一眼：你常在这个主题下关注：$topics。';
  }

  @override
  String topicBooksSummary(Object books) {
    return '小U轻轻看了一眼：你常在这个主题下回到：$books。';
  }

  @override
  String get topicQuietSummary => '小U轻轻看了一眼：这个主题还很安静，更多摘录会慢慢显出线索。';

  @override
  String get thatDayUnavailable => '那一天的记录暂时没有打开。';

  @override
  String get thatDayEmpty => '那一天没有留下更多记录。';

  @override
  String get readingRecords => '阅读记录';

  @override
  String get writeBeforeXiaou => '先写下一点内容，再交给小U观察';

  @override
  String get authorizingXiaou => '正在交给小U观察…';

  @override
  String get revokingXiaou => '正在撤回小U授权…';

  @override
  String get authorizedXiaouMessage => '已交给小U观察';

  @override
  String get revokedXiaouMessage => '已撤回小U授权';

  @override
  String operationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String shareFailed(Object error) {
    return '分享失败：$error';
  }

  @override
  String editedOn(Object date) {
    return '最近编辑 $date';
  }

  @override
  String readerContentLoadFailed(Object error) {
    return '正文载入失败：$error';
  }

  @override
  String get restoringTypography => '正在恢复阅读排版…';

  @override
  String get pageTextUnavailable => '当前格式暂时无法提取这一页的文字';

  @override
  String get organizedByXiaou => '已由小U整理';

  @override
  String get untitledBook => '未命名书籍';

  @override
  String get thoughtSavedPrivateNotShared => '想法已保存为私密，尚未公开到明台';

  @override
  String thoughtPrivatePublishFailed(Object error) {
    return '想法已保存为私密，公开失败：$error';
  }

  @override
  String get pleaseTryAgain => '请稍后重试';

  @override
  String todayQuestion(Object title) {
    return '今日问题 · 《$title》';
  }

  @override
  String get leaveResponse => '留下回应';

  @override
  String get enterBookPage => '进入书页';

  @override
  String get meetReaders => '也许可以先认识这些读者';

  @override
  String get loginFollowingHint => '登录后，这里会优先出现你关注的读者。';

  @override
  String get loginSameBookHint => '登录后，明台会寻找与你读过同一本书的人。';

  @override
  String get followingQuietFallback => '关注的读者暂时没有更新，先从这些公开阅读痕迹开始。';

  @override
  String get sameBookQuietFallback => '同读的新回应还很少，先看看明台里最近留下的话。';

  @override
  String get mingtaiFirstResponse => '明台还在等第一句话。';

  @override
  String sameBookReaderCount(Object count) {
    return '$count 位公开读者';
  }

  @override
  String get noPublicReadingStatus => '还没有人公开自己的阅读状态。';

  @override
  String get writeDownThought => '写下想法';

  @override
  String get noPublicBookThoughts => '还没有人认真写下这本书带来的问题。';

  @override
  String get reportUser => '举报用户';

  @override
  String blockUserTitle(Object name) {
    return '拉黑 $name？';
  }

  @override
  String get blockUserBody => '双方将不再看到彼此的动态，也会自动取消关注关系。';

  @override
  String get confirmBlock => '确认拉黑';

  @override
  String get readingProfile => '阅读档案';

  @override
  String get editProfile => '编辑资料';

  @override
  String get bioEmpty => '还没有写下一句话介绍。';

  @override
  String get follow => '关注';

  @override
  String get followed => '已关注';

  @override
  String profileFollowSummary(Object books, Object followers) {
    return '$followers 位读者关注 · 正在读 $books 本';
  }

  @override
  String get currentlyReading => '正在读';

  @override
  String get finishedReading => '读过';

  @override
  String get wantToRead => '想读';

  @override
  String get savedReadingTraces => '收藏的阅读痕迹';

  @override
  String get publicThoughtsDiscussions => '公开想法与讨论';

  @override
  String get noPublicThoughts => '还没有公开留下阅读想法。';

  @override
  String get deletePublicContentTitle => '删除这条公开内容？';

  @override
  String get deletePublicContentBody => '相关短摘录、评论和共鸣也会一起删除，且无法恢复。';

  @override
  String get publicContentDeleted => '公开内容已删除';

  @override
  String get originalTextPrefix => '原文 · ';

  @override
  String get expandOriginal => '展开原文';

  @override
  String get collapseOriginal => '收起原文';

  @override
  String get loginBeforePublishing => '请先登录后再发布';

  @override
  String get thoughtMinFive => '请至少写下 5 个字的完整想法';

  @override
  String get reviewMinTen => '公开书评至少需要 10 个字';

  @override
  String get highlightRequiresExcerpt => '公开划线需要包含一段短摘录';

  @override
  String get excerptTooLong => '公开摘录不能超过 240 个字符';

  @override
  String get selectBookFirst => '请先选择一本书';

  @override
  String get privateShelfNoBooks => '私人书架还没有可关联的书。';

  @override
  String get readingUpdate => '正在读';

  @override
  String get publicHighlight => '公开划线';

  @override
  String get readingThought => '阅读想法';

  @override
  String get sameBookDiscussion => '同书讨论';

  @override
  String get reportComment => '举报评论';

  @override
  String get cancelQuote => '取消引用';

  @override
  String get searchUnavailable => '搜索暂时没有回应';

  @override
  String get noSearchCommunityResults => '明台还没有找到相关书页或讨论。';

  @override
  String get books => '书籍';

  @override
  String get sharedQuestion => '提出了一个问题';

  @override
  String get sharedFragmentThought => '在一段原文旁留下想法';

  @override
  String get sharedReadingStatus => '分享了阅读阶段感受';

  @override
  String get sharedCurrentReading => '分享了正在读';

  @override
  String get sharedExcerpt => '分享了一段摘录';

  @override
  String get sharedReview => '留下了一段短评';

  @override
  String get sharedReadingThought => '写下了阅读想法';

  @override
  String get autosaving => '正在安静保存…';

  @override
  String get dailyQuestionOne => '这本书里，哪一句话改变了你理解它的方式？';

  @override
  String get dailyQuestionTwo => '你在这本书的哪一处停了下来？';

  @override
  String get dailyQuestionThree => '读到现在，你最想和同书读者确认什么？';

  @override
  String get dailyQuestionFour => '如果只留下一个问题，你会把什么带出这本书？';

  @override
  String translatorLabel(Object name) {
    return '$name 译';
  }

  @override
  String bookCommunitySummary(Object posts, Object readers) {
    return '$posts 条公开表达 · $readers 人正在读';
  }

  @override
  String get deleteThisContent => '删除这条内容';

  @override
  String get reportThisContent => '举报这条内容';

  @override
  String responseCount(Object count) {
    return '$count 条回应';
  }

  @override
  String quotedText(Object text) {
    return '引用：“$text”';
  }

  @override
  String get readingStatusHint => '此刻读到哪里，为什么停下来';

  @override
  String get excerptThoughtHint => '这段原文为什么值得留下';

  @override
  String get reviewHint => '这本书给你留下了什么';

  @override
  String get questionHint => '你想和同书读者讨论什么';

  @override
  String get yourThought => '你的想法';

  @override
  String notificationFollow(Object name) {
    return '$name 关注了你的阅读档案';
  }

  @override
  String notificationComment(Object name) {
    return '$name 回应了你的阅读想法';
  }

  @override
  String notificationQuote(Object name) {
    return '$name 引用了你的阅读想法';
  }

  @override
  String notificationResonance(Object name) {
    return '$name 与你的想法产生了共鸣';
  }

  @override
  String notificationDefault(Object name) {
    return '$name 在明台留下了回应';
  }

  @override
  String get bookDetails => '书籍详情';

  @override
  String get startReading => '开始阅读';

  @override
  String continueReadingPercent(int percent) {
    return '继续阅读 · $percent%';
  }

  @override
  String get readingProgressLabel => '阅读进度';

  @override
  String get bookDescription => '简介';

  @override
  String get bookDescriptionUnavailable => '这本书暂时没有简介。你仍可以从正文开始阅读。';

  @override
  String get freeNoteSaved => '已安静保存';

  @override
  String get originalTextLabel => '原文';

  @override
  String get userQuestionLabel => '我的问题';

  @override
  String get xiaouAnswerLabel => '小U回答';

  @override
  String get myThoughtLabel => '我的想法';
}
