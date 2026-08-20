import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'知读'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'让阅读痕迹慢慢显影'**
  String get appTagline;

  /// No description provided for @tabBookshelf.
  ///
  /// In zh, this message translates to:
  /// **'书架'**
  String get tabBookshelf;

  /// No description provided for @tabXiaou.
  ///
  /// In zh, this message translates to:
  /// **'小U'**
  String get tabXiaou;

  /// No description provided for @tabFreeNotes.
  ///
  /// In zh, this message translates to:
  /// **'随心记'**
  String get tabFreeNotes;

  /// No description provided for @tabMingtai.
  ///
  /// In zh, this message translates to:
  /// **'明台'**
  String get tabMingtai;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get account;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'界面氛围'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统或选择界面语言'**
  String get languageSubtitle;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @chinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @english.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @featureGuide.
  ///
  /// In zh, this message translates to:
  /// **'功能引导'**
  String get featureGuide;

  /// No description provided for @viewGuideAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新查看功能引导'**
  String get viewGuideAgain;

  /// No description provided for @viewGuideAgainSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'下次进入对应场景时，再看一次简短提示'**
  String get viewGuideAgainSubtitle;

  /// No description provided for @guideResetMessage.
  ///
  /// In zh, this message translates to:
  /// **'功能引导已重置，将在下次进入对应场景时出现'**
  String get guideResetMessage;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @versionLabel.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}'**
  String versionLabel(Object version);

  /// No description provided for @aboutTagline.
  ///
  /// In zh, this message translates to:
  /// **'AI 辅助阅读，让每本书都更易懂'**
  String get aboutTagline;

  /// No description provided for @loginRegister.
  ///
  /// In zh, this message translates to:
  /// **'登录 / 注册'**
  String get loginRegister;

  /// No description provided for @notSignedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get notSignedIn;

  /// No description provided for @signInSyncSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录后同步阅读进度和小U条目'**
  String get signInSyncSubtitle;

  /// No description provided for @myReadingProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的阅读档案'**
  String get myReadingProfile;

  /// No description provided for @myReadingProfileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'头像、昵称、在读书籍与公开想法'**
  String get myReadingProfileSubtitle;

  /// No description provided for @cloudAccountConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接云端账号'**
  String get cloudAccountConnected;

  /// No description provided for @switchAccount.
  ///
  /// In zh, this message translates to:
  /// **'切换账户'**
  String get switchAccount;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In zh, this message translates to:
  /// **'注销账号'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'注销知读账号'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In zh, this message translates to:
  /// **'账号、云端阅读记录、随心记、小U对话和公开内容将被永久删除。设备中的本地电子书不会自动删除。此操作无法撤销。'**
  String get deleteAccountBody;

  /// No description provided for @currentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get currentPassword;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @deletePermanently.
  ///
  /// In zh, this message translates to:
  /// **'永久注销'**
  String get deletePermanently;

  /// No description provided for @accountDeleted.
  ///
  /// In zh, this message translates to:
  /// **'账号及云端关联数据已删除'**
  String get accountDeleted;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In zh, this message translates to:
  /// **'注销失败：{error}'**
  String deleteAccountFailed(Object error);

  /// No description provided for @privacySecurity.
  ///
  /// In zh, this message translates to:
  /// **'隐私与安全'**
  String get privacySecurity;

  /// No description provided for @xiaouThirdPartyAi.
  ///
  /// In zh, this message translates to:
  /// **'小U与第三方 AI'**
  String get xiaouThirdPartyAi;

  /// No description provided for @xiaouThirdPartyAiSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看或撤回 DeepSeek 数据处理授权'**
  String get xiaouThirdPartyAiSubtitle;

  /// No description provided for @mingtaiVisibility.
  ///
  /// In zh, this message translates to:
  /// **'明台公开范围'**
  String get mingtaiVisibility;

  /// No description provided for @mingtaiVisibilitySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'控制阅读状态、进度、关注和同书发现'**
  String get mingtaiVisibilitySubtitle;

  /// No description provided for @communityRules.
  ///
  /// In zh, this message translates to:
  /// **'社区规范与举报'**
  String get communityRules;

  /// No description provided for @communityRulesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看公开内容规范和联系邮箱'**
  String get communityRulesSubtitle;

  /// No description provided for @privacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'知读如何处理和保护你的数据'**
  String get privacyPolicySubtitle;

  /// No description provided for @dataCollectionList.
  ///
  /// In zh, this message translates to:
  /// **'个人信息收集清单'**
  String get dataCollectionList;

  /// No description provided for @dataCollectionListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'逐项查看信息、用途、上传与保存期限'**
  String get dataCollectionListSubtitle;

  /// No description provided for @thirdPartyList.
  ///
  /// In zh, this message translates to:
  /// **'第三方服务清单'**
  String get thirdPartyList;

  /// No description provided for @thirdPartyListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'云服务、DeepSeek 与 Apple 系统能力'**
  String get thirdPartyListSubtitle;

  /// No description provided for @aiDataProcessing.
  ///
  /// In zh, this message translates to:
  /// **'AI 功能与数据处理'**
  String get aiDataProcessing;

  /// No description provided for @aiDataProcessingSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'小U会发送什么，以及如何撤回授权'**
  String get aiDataProcessingSubtitle;

  /// No description provided for @accountDataDeletion.
  ///
  /// In zh, this message translates to:
  /// **'账号与数据删除'**
  String get accountDataDeletion;

  /// No description provided for @accountDataDeletionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'注销路径、删除范围和处理时间'**
  String get accountDataDeletionSubtitle;

  /// No description provided for @pageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'页面暂时无法打开，请检查网络后重试。'**
  String get pageUnavailable;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @authAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get authAccount;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @register.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get register;

  /// No description provided for @welcomeBack.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来'**
  String get welcomeBack;

  /// No description provided for @createAccount.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get createAccount;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录以同步你的阅读数据'**
  String get loginSubtitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'注册后可在多设备同步阅读进度和笔记'**
  String get registerSubtitle;

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get email;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @enterEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱'**
  String get enterEmail;

  /// No description provided for @invalidEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱格式不正确'**
  String get invalidEmail;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get enterPassword;

  /// No description provided for @passwordMinLength.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 6 位'**
  String get passwordMinLength;

  /// No description provided for @orUseApple.
  ///
  /// In zh, this message translates to:
  /// **'或'**
  String get orUseApple;

  /// No description provided for @bindApple.
  ///
  /// In zh, this message translates to:
  /// **'绑定 Apple'**
  String get bindApple;

  /// No description provided for @appleLinked.
  ///
  /// In zh, this message translates to:
  /// **'已绑定 Apple'**
  String get appleLinked;

  /// No description provided for @appleBindingSuccess.
  ///
  /// In zh, this message translates to:
  /// **'Apple 账号已绑定'**
  String get appleBindingSuccess;

  /// No description provided for @appleBindingFailed.
  ///
  /// In zh, this message translates to:
  /// **'Apple 账号绑定失败，请稍后重试'**
  String get appleBindingFailed;

  /// No description provided for @appleAccountDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'此账号使用 Apple 登录。确认后将撤销 Apple 授权并永久注销账号。'**
  String get appleAccountDeleteConfirm;

  /// No description provided for @localDataMergeNotice.
  ///
  /// In zh, this message translates to:
  /// **'注册后，你之前在本机的所有数据会自动合并到新账号'**
  String get localDataMergeNotice;

  /// No description provided for @importBook.
  ///
  /// In zh, this message translates to:
  /// **'导入书籍'**
  String get importBook;

  /// No description provided for @importEbook.
  ///
  /// In zh, this message translates to:
  /// **'导入电子书'**
  String get importEbook;

  /// No description provided for @supportedBookFormats.
  ///
  /// In zh, this message translates to:
  /// **'支持 EPUB · TXT · PDF'**
  String get supportedBookFormats;

  /// No description provided for @importLocalFile.
  ///
  /// In zh, this message translates to:
  /// **'从本地文件导入'**
  String get importLocalFile;

  /// No description provided for @importLocalFileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择 EPUB、TXT 或 PDF 文件'**
  String get importLocalFileSubtitle;

  /// No description provided for @downloadFromLink.
  ///
  /// In zh, this message translates to:
  /// **'从链接下载'**
  String get downloadFromLink;

  /// No description provided for @downloadFromLinkSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入 EPUB、TXT 或 PDF 下载地址'**
  String get downloadFromLinkSubtitle;

  /// No description provided for @downloadLinkHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入 EPUB / TXT / PDF 文件的下载链接'**
  String get downloadLinkHint;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @emptyBookshelf.
  ///
  /// In zh, this message translates to:
  /// **'书架空空如也'**
  String get emptyBookshelf;

  /// No description provided for @emptyBookshelfSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导入你的第一本电子书吧'**
  String get emptyBookshelfSubtitle;

  /// No description provided for @shareReadingThought.
  ///
  /// In zh, this message translates to:
  /// **'分享阅读想法'**
  String get shareReadingThought;

  /// No description provided for @shareReadingThoughtSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'只关联书籍信息，不上传电子书文件'**
  String get shareReadingThoughtSubtitle;

  /// No description provided for @legacyPublicBookDisabled.
  ///
  /// In zh, this message translates to:
  /// **'旧明台借阅入口已停用。请在私人书架重新导入你合法获得的电子书。'**
  String get legacyPublicBookDisabled;

  /// No description provided for @deleteBook.
  ///
  /// In zh, this message translates to:
  /// **'删除书籍'**
  String get deleteBook;

  /// No description provided for @deleteBookConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除《{title}》吗？\n相关的笔记和标注也会被删除。'**
  String deleteBookConfirm(Object title);

  /// No description provided for @settingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTooltip;

  /// No description provided for @refreshFailedRetained.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败，现有内容已保留。'**
  String get refreshFailedRetained;

  /// No description provided for @bookshelfUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'书架暂时没有打开'**
  String get bookshelfUnavailable;

  /// No description provided for @bookmarks.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get bookmarks;

  /// No description provided for @tableOfContents.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get tableOfContents;

  /// No description provided for @reloadContent.
  ///
  /// In zh, this message translates to:
  /// **'重新载入正文'**
  String get reloadContent;

  /// No description provided for @readerOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'书籍打开失败'**
  String get readerOpenFailed;

  /// No description provided for @readerAskXiaou.
  ///
  /// In zh, this message translates to:
  /// **'问小U'**
  String get readerAskXiaou;

  /// No description provided for @readerAskCompact.
  ///
  /// In zh, this message translates to:
  /// **'提问'**
  String get readerAskCompact;

  /// No description provided for @readerExplain.
  ///
  /// In zh, this message translates to:
  /// **'小U解读'**
  String get readerExplain;

  /// No description provided for @readerExplainCompact.
  ///
  /// In zh, this message translates to:
  /// **'解读'**
  String get readerExplainCompact;

  /// No description provided for @readerThought.
  ///
  /// In zh, this message translates to:
  /// **'写想法'**
  String get readerThought;

  /// No description provided for @readerThoughtCompact.
  ///
  /// In zh, this message translates to:
  /// **'想法'**
  String get readerThoughtCompact;

  /// No description provided for @readerHighlight.
  ///
  /// In zh, this message translates to:
  /// **'保存划线'**
  String get readerHighlight;

  /// No description provided for @readerTranslate.
  ///
  /// In zh, this message translates to:
  /// **'翻译'**
  String get readerTranslate;

  /// No description provided for @readerClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get readerClose;

  /// No description provided for @privateOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅自己可见'**
  String get privateOnly;

  /// No description provided for @shareToMingtai.
  ///
  /// In zh, this message translates to:
  /// **'分享到明台'**
  String get shareToMingtai;

  /// No description provided for @thoughtSavedPrivate.
  ///
  /// In zh, this message translates to:
  /// **'想法已保存为私密'**
  String get thoughtSavedPrivate;

  /// No description provided for @publishedToMingtai.
  ///
  /// In zh, this message translates to:
  /// **'已发布到明台'**
  String get publishedToMingtai;

  /// No description provided for @aiGeneratedNotice.
  ///
  /// In zh, this message translates to:
  /// **'由 AI 生成，可能存在错误，请结合原文判断。'**
  String get aiGeneratedNotice;

  /// No description provided for @freeNotesTitle.
  ///
  /// In zh, this message translates to:
  /// **'随心记'**
  String get freeNotesTitle;

  /// No description provided for @freeNotesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'留一处安静的地方，写下此刻经过心里的事'**
  String get freeNotesSubtitle;

  /// No description provided for @writeNote.
  ///
  /// In zh, this message translates to:
  /// **'写一笔'**
  String get writeNote;

  /// No description provided for @searchFreeNotes.
  ///
  /// In zh, this message translates to:
  /// **'找一找曾经写下的句子'**
  String get searchFreeNotes;

  /// No description provided for @writeWhatYouThink.
  ///
  /// In zh, this message translates to:
  /// **'写下此刻想到的。'**
  String get writeWhatYouThink;

  /// No description provided for @todayEcho.
  ///
  /// In zh, this message translates to:
  /// **'今日回响'**
  String get todayEcho;

  /// No description provided for @privateOnlyNote.
  ///
  /// In zh, this message translates to:
  /// **'仅自己可见'**
  String get privateOnlyNote;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中...'**
  String get saving;

  /// No description provided for @deleteRecord.
  ///
  /// In zh, this message translates to:
  /// **'删除记录'**
  String get deleteRecord;

  /// No description provided for @deleteRecordConfirm.
  ///
  /// In zh, this message translates to:
  /// **'这条随心记会从你的私密记录中删除，删除后不可恢复。'**
  String get deleteRecordConfirm;

  /// No description provided for @titleOptional.
  ///
  /// In zh, this message translates to:
  /// **'标题（可选）'**
  String get titleOptional;

  /// No description provided for @noteBodyHint.
  ///
  /// In zh, this message translates to:
  /// **'不必整理，也不必解释。\n写下此刻经过心里的东西...'**
  String get noteBodyHint;

  /// No description provided for @xiaouTitle.
  ///
  /// In zh, this message translates to:
  /// **'小U'**
  String get xiaouTitle;

  /// No description provided for @readingTraces.
  ///
  /// In zh, this message translates to:
  /// **'阅读痕迹'**
  String get readingTraces;

  /// No description provided for @searchTraces.
  ///
  /// In zh, this message translates to:
  /// **'找一句话、一本书或一个想法'**
  String get searchTraces;

  /// No description provided for @allBooks.
  ///
  /// In zh, this message translates to:
  /// **'全部书籍'**
  String get allBooks;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @thoughts.
  ///
  /// In zh, this message translates to:
  /// **'想法'**
  String get thoughts;

  /// No description provided for @highlights.
  ///
  /// In zh, this message translates to:
  /// **'划线'**
  String get highlights;

  /// No description provided for @xiaouExplanations.
  ///
  /// In zh, this message translates to:
  /// **'小U解读'**
  String get xiaouExplanations;

  /// No description provided for @xiaouQuestions.
  ///
  /// In zh, this message translates to:
  /// **'问小U'**
  String get xiaouQuestions;

  /// No description provided for @importantOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅看重要'**
  String get importantOnly;

  /// No description provided for @expand.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get expand;

  /// No description provided for @collapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get collapse;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @markImportant.
  ///
  /// In zh, this message translates to:
  /// **'标记重要'**
  String get markImportant;

  /// No description provided for @unmarkImportant.
  ///
  /// In zh, this message translates to:
  /// **'取消重要'**
  String get unmarkImportant;

  /// No description provided for @chatWithXiaou.
  ///
  /// In zh, this message translates to:
  /// **'和小U说话'**
  String get chatWithXiaou;

  /// No description provided for @askXiaouDirectly.
  ///
  /// In zh, this message translates to:
  /// **'直接问小U...'**
  String get askXiaouDirectly;

  /// No description provided for @newConversation.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get newConversation;

  /// No description provided for @conversationHistory.
  ///
  /// In zh, this message translates to:
  /// **'和小U说过的话'**
  String get conversationHistory;

  /// No description provided for @saveToFreeNotes.
  ///
  /// In zh, this message translates to:
  /// **'保存到随心记'**
  String get saveToFreeNotes;

  /// No description provided for @mingtaiTitle.
  ///
  /// In zh, this message translates to:
  /// **'明台'**
  String get mingtaiTitle;

  /// No description provided for @mingtaiSearch.
  ///
  /// In zh, this message translates to:
  /// **'找一本书、作者或一句话'**
  String get mingtaiSearch;

  /// No description provided for @recommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get recommended;

  /// No description provided for @following.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get following;

  /// No description provided for @readingTogether.
  ///
  /// In zh, this message translates to:
  /// **'同读'**
  String get readingTogether;

  /// No description provided for @leaveReadingTrace.
  ///
  /// In zh, this message translates to:
  /// **'留下一段阅读'**
  String get leaveReadingTrace;

  /// No description provided for @loginToJoin.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能参与明台讨论'**
  String get loginToJoin;

  /// No description provided for @reply.
  ///
  /// In zh, this message translates to:
  /// **'回应'**
  String get reply;

  /// No description provided for @quoteReply.
  ///
  /// In zh, this message translates to:
  /// **'引用回应'**
  String get quoteReply;

  /// No description provided for @favorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get unfavorite;

  /// No description provided for @viewSameBook.
  ///
  /// In zh, this message translates to:
  /// **'查看同书'**
  String get viewSameBook;

  /// No description provided for @notifications.
  ///
  /// In zh, this message translates to:
  /// **'明台消息'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In zh, this message translates to:
  /// **'这里还没有新的回声。'**
  String get noNotifications;

  /// No description provided for @report.
  ///
  /// In zh, this message translates to:
  /// **'举报'**
  String get report;

  /// No description provided for @blockUser.
  ///
  /// In zh, this message translates to:
  /// **'拉黑用户'**
  String get blockUser;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载…'**
  String get loading;

  /// No description provided for @empty.
  ///
  /// In zh, this message translates to:
  /// **'这里暂时还没有内容。'**
  String get empty;

  /// No description provided for @networkSlow.
  ///
  /// In zh, this message translates to:
  /// **'网络似乎有些慢，请稍后重试。'**
  String get networkSlow;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @stop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @tryIt.
  ///
  /// In zh, this message translates to:
  /// **'试一下'**
  String get tryIt;

  /// No description provided for @gotIt.
  ///
  /// In zh, this message translates to:
  /// **'我知道了'**
  String get gotIt;

  /// No description provided for @syncFailedLocalRetained.
  ///
  /// In zh, this message translates to:
  /// **'同步暂时失败，已保留本机记录。'**
  String get syncFailedLocalRetained;

  /// No description provided for @readerQuestionSelection.
  ///
  /// In zh, this message translates to:
  /// **'所选文字'**
  String get readerQuestionSelection;

  /// No description provided for @readerQuestionPage.
  ///
  /// In zh, this message translates to:
  /// **'当前页'**
  String get readerQuestionPage;

  /// No description provided for @readerQuestionChapter.
  ///
  /// In zh, this message translates to:
  /// **'本章'**
  String get readerQuestionChapter;

  /// No description provided for @readerQuestionPrompt.
  ///
  /// In zh, this message translates to:
  /// **'可以问一个具体的问题。\n小U会把回答放回你眼前的文字里。'**
  String get readerQuestionPrompt;

  /// No description provided for @readerQuestionHint.
  ///
  /// In zh, this message translates to:
  /// **'就眼前的文字问小U…'**
  String get readerQuestionHint;

  /// No description provided for @readerQuestionEmpty.
  ///
  /// In zh, this message translates to:
  /// **'小U暂时没有看清，可以换一种问法再试一次。'**
  String get readerQuestionEmpty;

  /// No description provided for @readerQuestionSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'回答已经生成，但这次记录暂时没有同步成功。'**
  String get readerQuestionSaveFailed;

  /// No description provided for @readerQuestionThinking.
  ///
  /// In zh, this message translates to:
  /// **'小U正在读这一段…'**
  String get readerQuestionThinking;

  /// No description provided for @readingTypography.
  ///
  /// In zh, this message translates to:
  /// **'阅读排版'**
  String get readingTypography;

  /// No description provided for @resetDefaults.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get resetDefaults;

  /// No description provided for @readingPreview.
  ///
  /// In zh, this message translates to:
  /// **'阅读效果'**
  String get readingPreview;

  /// No description provided for @font.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get font;

  /// No description provided for @fontSystem.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get fontSystem;

  /// No description provided for @fontSerif.
  ///
  /// In zh, this message translates to:
  /// **'宋体'**
  String get fontSerif;

  /// No description provided for @fontWenkai.
  ///
  /// In zh, this message translates to:
  /// **'文楷'**
  String get fontWenkai;

  /// No description provided for @typography.
  ///
  /// In zh, this message translates to:
  /// **'排版'**
  String get typography;

  /// No description provided for @fontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get fontSize;

  /// No description provided for @lineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行距'**
  String get lineHeight;

  /// No description provided for @pageMargin.
  ///
  /// In zh, this message translates to:
  /// **'页边距'**
  String get pageMargin;

  /// No description provided for @pagingMode.
  ///
  /// In zh, this message translates to:
  /// **'翻页方式'**
  String get pagingMode;

  /// No description provided for @verticalScroll.
  ///
  /// In zh, this message translates to:
  /// **'上下滚动'**
  String get verticalScroll;

  /// No description provided for @horizontalPaging.
  ///
  /// In zh, this message translates to:
  /// **'左右翻页'**
  String get horizontalPaging;

  /// No description provided for @paperBackground.
  ///
  /// In zh, this message translates to:
  /// **'纸张背景'**
  String get paperBackground;

  /// No description provided for @paperWhite.
  ///
  /// In zh, this message translates to:
  /// **'白色'**
  String get paperWhite;

  /// No description provided for @paperSepia.
  ///
  /// In zh, this message translates to:
  /// **'米纸'**
  String get paperSepia;

  /// No description provided for @paperGreen.
  ///
  /// In zh, this message translates to:
  /// **'护眼'**
  String get paperGreen;

  /// No description provided for @paperDark.
  ///
  /// In zh, this message translates to:
  /// **'夜间'**
  String get paperDark;

  /// No description provided for @readerGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'长按任意文字'**
  String get readerGuideTitle;

  /// No description provided for @readerGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'可以提问、解读、划线，或记下想法。'**
  String get readerGuideBody;

  /// No description provided for @readerGuideSelectionTip.
  ///
  /// In zh, this message translates to:
  /// **'在这里向小U提问，或查看解读。'**
  String get readerGuideSelectionTip;

  /// No description provided for @xiaouGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'这是小U。'**
  String get xiaouGuideTitle;

  /// No description provided for @xiaouGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'有疑问、想继续追问，或回望阅读痕迹时，点亮它。'**
  String get xiaouGuideBody;

  /// No description provided for @xiaouGuideAction.
  ///
  /// In zh, this message translates to:
  /// **'点一下看看'**
  String get xiaouGuideAction;

  /// No description provided for @mingtaiGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'欢迎来到明台'**
  String get mingtaiGuideTitle;

  /// No description provided for @mingtaiGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'在这里，你可以阅读大家公开分享的阅读片段、想法和书评，也可以分享自己的阅读痕迹，与其他读者讨论。'**
  String get mingtaiGuideBody;

  /// No description provided for @mingtaiGuidePrivacy.
  ///
  /// In zh, this message translates to:
  /// **'你的内容默认保持私人，只有主动确认后才会公开。'**
  String get mingtaiGuidePrivacy;

  /// No description provided for @browseMingtai.
  ///
  /// In zh, this message translates to:
  /// **'逛逛明台'**
  String get browseMingtai;

  /// No description provided for @learnSharing.
  ///
  /// In zh, this message translates to:
  /// **'看看如何分享'**
  String get learnSharing;

  /// No description provided for @sharingIsYourChoice.
  ///
  /// In zh, this message translates to:
  /// **'分享由你决定'**
  String get sharingIsYourChoice;

  /// No description provided for @sharingGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'在阅读页选中文字，写下想法后选择“分享到明台”；也可以从明台右下角留下一段阅读。每次发布前都会让你确认，私人记录不会自动公开。'**
  String get sharingGuideBody;

  /// No description provided for @newFreeNote.
  ///
  /// In zh, this message translates to:
  /// **'新建记录'**
  String get newFreeNote;

  /// No description provided for @freeNotesSyncUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时没能同步随心记'**
  String get freeNotesSyncUnavailable;

  /// No description provided for @freeNotesSyncRetained.
  ///
  /// In zh, this message translates to:
  /// **'本机记录没有被清空，网络恢复后可以重新加载。'**
  String get freeNotesSyncRetained;

  /// No description provided for @clearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get clearSearch;

  /// No description provided for @backToThatDay.
  ///
  /// In zh, this message translates to:
  /// **'回到那一天'**
  String get backToThatDay;

  /// No description provided for @thatDay.
  ///
  /// In zh, this message translates to:
  /// **'那一天'**
  String get thatDay;

  /// No description provided for @createdOnEditedOn.
  ///
  /// In zh, this message translates to:
  /// **'写于 {created} · 最近编辑 {updated}'**
  String createdOnEditedOn(Object created, Object updated);

  /// No description provided for @createdOn.
  ///
  /// In zh, this message translates to:
  /// **'写于 {created}'**
  String createdOn(Object created);

  /// No description provided for @earlier.
  ///
  /// In zh, this message translates to:
  /// **'更早以前'**
  String get earlier;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @thisWeek.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get thisMonth;

  /// No description provided for @untitledMoment.
  ///
  /// In zh, this message translates to:
  /// **'未命名的片刻'**
  String get untitledMoment;

  /// No description provided for @xiaouLoadRetained.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法刷新，已保留上次看到的内容。'**
  String get xiaouLoadRetained;

  /// No description provided for @deletedEntry.
  ///
  /// In zh, this message translates to:
  /// **'已删除{type}'**
  String deletedEntry(Object type);

  /// No description provided for @deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{error}'**
  String deleteFailed(Object error);

  /// No description provided for @importanceSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'重要标记保存失败：{error}'**
  String importanceSaveFailed(Object error);

  /// No description provided for @noMatchingTraces.
  ///
  /// In zh, this message translates to:
  /// **'这里暂时没有找到对应的阅读痕迹。'**
  String get noMatchingTraces;

  /// No description provided for @noNewTraces.
  ///
  /// In zh, this message translates to:
  /// **'还没有拿到新的阅读痕迹，可以稍后重试。'**
  String get noNewTraces;

  /// No description provided for @tracesEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'划线、想法和小U解读会被安静地记在这里。'**
  String get tracesEmptyBody;

  /// No description provided for @xiaouDiscovery.
  ///
  /// In zh, this message translates to:
  /// **'小U发现了一件事'**
  String get xiaouDiscovery;

  /// No description provided for @xiaouChatSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从你的阅读里聊起。'**
  String get xiaouChatSubtitle;

  /// No description provided for @xiaouStartFromReading.
  ///
  /// In zh, this message translates to:
  /// **'从正在读的地方开始'**
  String get xiaouStartFromReading;

  /// No description provided for @xiaouStartBody.
  ///
  /// In zh, this message translates to:
  /// **'你可以直接输入，也可以先从下面的一件事开始。'**
  String get xiaouStartBody;

  /// No description provided for @xiaouThinking.
  ///
  /// In zh, this message translates to:
  /// **'小U正在回看你的阅读痕迹…'**
  String get xiaouThinking;

  /// No description provided for @conversationDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这段对话？'**
  String get conversationDeleteTitle;

  /// No description provided for @conversationDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'删除后无法恢复，但已经存入随心记的内容不会受到影响。'**
  String get conversationDeleteBody;

  /// No description provided for @noConversationHistory.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存过的对话。'**
  String get noConversationHistory;

  /// No description provided for @mingtaiUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'明台暂时没有打开'**
  String get mingtaiUnavailable;

  /// No description provided for @tryAgain.
  ///
  /// In zh, this message translates to:
  /// **'再试一次'**
  String get tryAgain;

  /// No description provided for @shareCurrentReading.
  ///
  /// In zh, this message translates to:
  /// **'分享正在读'**
  String get shareCurrentReading;

  /// No description provided for @shareCurrentReadingSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'说说此刻读到哪里'**
  String get shareCurrentReadingSubtitle;

  /// No description provided for @publishHighlight.
  ///
  /// In zh, this message translates to:
  /// **'公开划线'**
  String get publishHighlight;

  /// No description provided for @publishHighlightSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'分享一小段原文与停留的原因'**
  String get publishHighlightSubtitle;

  /// No description provided for @writeThought.
  ///
  /// In zh, this message translates to:
  /// **'写下想法'**
  String get writeThought;

  /// No description provided for @writeThoughtSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'留下你对这本书的理解'**
  String get writeThoughtSubtitle;

  /// No description provided for @writeReview.
  ///
  /// In zh, this message translates to:
  /// **'写书评'**
  String get writeReview;

  /// No description provided for @writeReviewSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'写一段完整而克制的读后回声'**
  String get writeReviewSubtitle;

  /// No description provided for @mingtaiComposeTitle.
  ///
  /// In zh, this message translates to:
  /// **'分享阅读'**
  String get mingtaiComposeTitle;

  /// No description provided for @mingtaiComposePrivacy.
  ///
  /// In zh, this message translates to:
  /// **'内容默认私密；每条公开内容都会关联一本书。'**
  String get mingtaiComposePrivacy;

  /// No description provided for @composerReadingHint.
  ///
  /// In zh, this message translates to:
  /// **'说说你此刻读到哪里，为什么想停一停。'**
  String get composerReadingHint;

  /// No description provided for @composerExcerptHint.
  ///
  /// In zh, this message translates to:
  /// **'写下这段原文为什么让你停留。'**
  String get composerExcerptHint;

  /// No description provided for @composerThoughtHint.
  ///
  /// In zh, this message translates to:
  /// **'写下你对这本书或这一段的理解。'**
  String get composerThoughtHint;

  /// No description provided for @composerReviewHint.
  ///
  /// In zh, this message translates to:
  /// **'写下这本书留给你的回声。'**
  String get composerReviewHint;

  /// No description provided for @loginRequiredMingtai.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能参与明台讨论'**
  String get loginRequiredMingtai;

  /// No description provided for @noMeaningfulMingtaiContent.
  ///
  /// In zh, this message translates to:
  /// **'明台还在等第一句话。'**
  String get noMeaningfulMingtaiContent;

  /// No description provided for @startWithBook.
  ///
  /// In zh, this message translates to:
  /// **'从一本正在读的书开始，留下一个真实的问题或想法。'**
  String get startWithBook;

  /// No description provided for @sameBookSpace.
  ///
  /// In zh, this message translates to:
  /// **'同读空间'**
  String get sameBookSpace;

  /// No description provided for @publicExpressions.
  ///
  /// In zh, this message translates to:
  /// **'公开想法与问题'**
  String get publicExpressions;

  /// No description provided for @xiaouAsksMe.
  ///
  /// In zh, this message translates to:
  /// **'小U问我'**
  String get xiaouAsksMe;

  /// No description provided for @xiaouAsksSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从你的阅读里开始一场开放对谈。'**
  String get xiaouAsksSubtitle;

  /// No description provided for @chatHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get chatHistory;

  /// No description provided for @conversationActions.
  ///
  /// In zh, this message translates to:
  /// **'对话操作'**
  String get conversationActions;

  /// No description provided for @saveWholeConversation.
  ///
  /// In zh, this message translates to:
  /// **'整段存入随心记'**
  String get saveWholeConversation;

  /// No description provided for @changeQuestion.
  ///
  /// In zh, this message translates to:
  /// **'换个问题'**
  String get changeQuestion;

  /// No description provided for @endConversation.
  ///
  /// In zh, this message translates to:
  /// **'结束对谈'**
  String get endConversation;

  /// No description provided for @xiaouAnswerHint.
  ///
  /// In zh, this message translates to:
  /// **'回答、反问，或继续说…'**
  String get xiaouAnswerHint;

  /// No description provided for @xiaouAskMeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'让小U从你的阅读里提出一个问题'**
  String get xiaouAskMeSubtitle;

  /// No description provided for @quickExplainLabel.
  ///
  /// In zh, this message translates to:
  /// **'解读刚才读到的内容'**
  String get quickExplainLabel;

  /// No description provided for @quickExplainPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请结合我最近读到的内容，帮我看清其中最需要理解的一处。'**
  String get quickExplainPrompt;

  /// No description provided for @quickReviewLabel.
  ///
  /// In zh, this message translates to:
  /// **'回顾我的划线与批注'**
  String get quickReviewLabel;

  /// No description provided for @quickReviewPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请回看我最近的划线与批注，告诉我其中有没有值得继续追问的联系。'**
  String get quickReviewPrompt;

  /// No description provided for @quickBookChatLabel.
  ///
  /// In zh, this message translates to:
  /// **'和小U聊聊这本书'**
  String get quickBookChatLabel;

  /// No description provided for @quickBookChatPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请从我最近正在读的书开始，陪我聊聊我停留最多的那个问题。'**
  String get quickBookChatPrompt;

  /// No description provided for @sameBookReaders.
  ///
  /// In zh, this message translates to:
  /// **'同书读者'**
  String get sameBookReaders;

  /// No description provided for @latest.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get latest;

  /// No description provided for @mostDiscussed.
  ///
  /// In zh, this message translates to:
  /// **'热议'**
  String get mostDiscussed;

  /// No description provided for @nearMyProgress.
  ///
  /// In zh, this message translates to:
  /// **'与你读到相近位置'**
  String get nearMyProgress;

  /// No description provided for @publicExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'公开摘录'**
  String get publicExcerpt;

  /// No description provided for @fragmentThought.
  ///
  /// In zh, this message translates to:
  /// **'片段想法'**
  String get fragmentThought;

  /// No description provided for @readingReflection.
  ///
  /// In zh, this message translates to:
  /// **'阅读感受'**
  String get readingReflection;

  /// No description provided for @bookReview.
  ///
  /// In zh, this message translates to:
  /// **'书评'**
  String get bookReview;

  /// No description provided for @publicReadingExpressions.
  ///
  /// In zh, this message translates to:
  /// **'这本书下的公开表达'**
  String get publicReadingExpressions;

  /// No description provided for @noSameBookThoughts.
  ///
  /// In zh, this message translates to:
  /// **'还没有人认真写下这本书带来的问题。'**
  String get noSameBookThoughts;

  /// No description provided for @selectBook.
  ///
  /// In zh, this message translates to:
  /// **'关联书籍'**
  String get selectBook;

  /// No description provided for @postType.
  ///
  /// In zh, this message translates to:
  /// **'这是一段'**
  String get postType;

  /// No description provided for @shortExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'短摘录'**
  String get shortExcerpt;

  /// No description provided for @shortExcerptOptional.
  ///
  /// In zh, this message translates to:
  /// **'短摘录（可选）'**
  String get shortExcerptOptional;

  /// No description provided for @shortExcerptHint.
  ///
  /// In zh, this message translates to:
  /// **'只摘录讨论所需的一小段原文'**
  String get shortExcerptHint;

  /// No description provided for @readingPositionOptional.
  ///
  /// In zh, this message translates to:
  /// **'阅读位置（可选）'**
  String get readingPositionOptional;

  /// No description provided for @readingPositionHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：第一卷 第三章'**
  String get readingPositionHint;

  /// No description provided for @publishing.
  ///
  /// In zh, this message translates to:
  /// **'正在发布…'**
  String get publishing;

  /// No description provided for @publishToMingtai.
  ///
  /// In zh, this message translates to:
  /// **'发布到明台'**
  String get publishToMingtai;

  /// No description provided for @continueDiscussion.
  ///
  /// In zh, this message translates to:
  /// **'围绕这段阅读继续讨论'**
  String get continueDiscussion;

  /// No description provided for @noReplies.
  ///
  /// In zh, this message translates to:
  /// **'还没有人回应。'**
  String get noReplies;

  /// No description provided for @writeReply.
  ///
  /// In zh, this message translates to:
  /// **'写下回应…'**
  String get writeReply;

  /// No description provided for @selectQuote.
  ///
  /// In zh, this message translates to:
  /// **'选择要回应的一句话'**
  String get selectQuote;

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟前'**
  String minutesAgo(Object count);

  /// No description provided for @hoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时前'**
  String hoursAgo(Object count);

  /// No description provided for @daysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天前'**
  String daysAgo(Object count);

  /// No description provided for @explainModeAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get explainModeAuto;

  /// No description provided for @explainModePlain.
  ///
  /// In zh, this message translates to:
  /// **'通俗'**
  String get explainModePlain;

  /// No description provided for @explainModeStructure.
  ///
  /// In zh, this message translates to:
  /// **'拆解'**
  String get explainModeStructure;

  /// No description provided for @explainModeConcept.
  ///
  /// In zh, this message translates to:
  /// **'概念'**
  String get explainModeConcept;

  /// No description provided for @explainModeArgument.
  ///
  /// In zh, this message translates to:
  /// **'论证'**
  String get explainModeArgument;

  /// No description provided for @explainModeAutoFull.
  ///
  /// In zh, this message translates to:
  /// **'小U解读'**
  String get explainModeAutoFull;

  /// No description provided for @explainModePlainFull.
  ///
  /// In zh, this message translates to:
  /// **'通俗解释'**
  String get explainModePlainFull;

  /// No description provided for @explainModeStructureFull.
  ///
  /// In zh, this message translates to:
  /// **'结构拆解'**
  String get explainModeStructureFull;

  /// No description provided for @explainModeConceptFull.
  ///
  /// In zh, this message translates to:
  /// **'概念辨析'**
  String get explainModeConceptFull;

  /// No description provided for @explainModeArgumentFull.
  ///
  /// In zh, this message translates to:
  /// **'论证脉络'**
  String get explainModeArgumentFull;

  /// No description provided for @xiaouOrganizing.
  ///
  /// In zh, this message translates to:
  /// **'小U正在组织语言'**
  String get xiaouOrganizing;

  /// No description provided for @followUpHint.
  ///
  /// In zh, this message translates to:
  /// **'继续问一句…'**
  String get followUpHint;

  /// No description provided for @passageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这一段暂时没能打开，请稍后重试。'**
  String get passageUnavailable;

  /// No description provided for @aiLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能使用小U'**
  String get aiLoginRequired;

  /// No description provided for @aiConsentTitle.
  ///
  /// In zh, this message translates to:
  /// **'使用小U前，请先了解'**
  String get aiConsentTitle;

  /// No description provided for @aiConsentBody.
  ///
  /// In zh, this message translates to:
  /// **'为生成小U解读，你选择的原文、相关上下文、提问和必要的阅读痕迹将发送至第三方人工智能服务 DeepSeek 处理。\n\n小U全局对话还可能使用你的划线、想法、小U解读，以及你主动授权的随心记。私人书籍文件不会发送。\n\n请不要提交身份证、医疗信息、密码等敏感个人信息。AI 生成内容可能存在错误，请结合原文判断。'**
  String get aiConsentBody;

  /// No description provided for @decline.
  ///
  /// In zh, this message translates to:
  /// **'暂不同意'**
  String get decline;

  /// No description provided for @agreeContinue.
  ///
  /// In zh, this message translates to:
  /// **'同意并继续'**
  String get agreeContinue;

  /// No description provided for @aiConsentLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法读取 AI 授权状态：{error}'**
  String aiConsentLoadFailed(Object error);

  /// No description provided for @aiConsentSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存授权失败：{error}'**
  String aiConsentSaveFailed(Object error);

  /// No description provided for @view.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get view;

  /// No description provided for @writeThoughtFirst.
  ///
  /// In zh, this message translates to:
  /// **'先写下你的想法'**
  String get writeThoughtFirst;

  /// No description provided for @publicThoughtMinLength.
  ///
  /// In zh, this message translates to:
  /// **'公开想法至少需要 5 个字'**
  String get publicThoughtMinLength;

  /// No description provided for @thoughtPrompt.
  ///
  /// In zh, this message translates to:
  /// **'这段文字让你想到什么？'**
  String get thoughtPrompt;

  /// No description provided for @privateThoughtExplanation.
  ///
  /// In zh, this message translates to:
  /// **'保存在私人阅读记录中，不会自动公开。'**
  String get privateThoughtExplanation;

  /// No description provided for @publicThoughtExplanation.
  ///
  /// In zh, this message translates to:
  /// **'这段话会出现在书页边缘。未发布的记录仍只属于你。'**
  String get publicThoughtExplanation;

  /// No description provided for @keepPrivate.
  ///
  /// In zh, this message translates to:
  /// **'暂时留给自己'**
  String get keepPrivate;

  /// No description provided for @loginToPublish.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能公开到明台'**
  String get loginToPublish;

  /// No description provided for @writeThisMoment.
  ///
  /// In zh, this message translates to:
  /// **'写下此刻'**
  String get writeThisMoment;

  /// No description provided for @returnToThisPage.
  ///
  /// In zh, this message translates to:
  /// **'回到这一页'**
  String get returnToThisPage;

  /// No description provided for @privatePageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'只属于你的私人书页'**
  String get privatePageSubtitle;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @authorizeXiaou.
  ///
  /// In zh, this message translates to:
  /// **'交给小U思考'**
  String get authorizeXiaou;

  /// No description provided for @revokeXiaou.
  ///
  /// In zh, this message translates to:
  /// **'撤回小U授权'**
  String get revokeXiaou;

  /// No description provided for @shareText.
  ///
  /// In zh, this message translates to:
  /// **'分享文本'**
  String get shareText;

  /// No description provided for @shareImage.
  ///
  /// In zh, this message translates to:
  /// **'分享图片'**
  String get shareImage;

  /// No description provided for @authorizedToXiaou.
  ///
  /// In zh, this message translates to:
  /// **'已授权给小U · 可随时撤回'**
  String get authorizedToXiaou;

  /// No description provided for @noSearchResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有找到那句话'**
  String get noSearchResultTitle;

  /// No description provided for @noSearchResultBody.
  ///
  /// In zh, this message translates to:
  /// **'换个词，再慢慢找找'**
  String get noSearchResultBody;

  /// No description provided for @noBookmarks.
  ///
  /// In zh, this message translates to:
  /// **'还没有书签'**
  String get noBookmarks;

  /// No description provided for @deleteBookmarkTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除书签'**
  String get deleteBookmarkTitle;

  /// No description provided for @deleteBookmarkBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这个书签吗？'**
  String get deleteBookmarkBody;

  /// No description provided for @expandFullExplanation.
  ///
  /// In zh, this message translates to:
  /// **'展开完整解读'**
  String get expandFullExplanation;

  /// No description provided for @followUpCount.
  ///
  /// In zh, this message translates to:
  /// **'已继续追问 {count} 次'**
  String followUpCount(Object count);

  /// No description provided for @followUpCountWithQuestion.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次追问 · {question}'**
  String followUpCountWithQuestion(Object count, Object question);

  /// No description provided for @chapterNumber.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 章'**
  String chapterNumber(Object number);

  /// No description provided for @chapterUnknown.
  ///
  /// In zh, this message translates to:
  /// **'章节未记录'**
  String get chapterUnknown;

  /// No description provided for @bookUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未记录书名'**
  String get bookUnknown;

  /// No description provided for @selectedPassage.
  ///
  /// In zh, this message translates to:
  /// **'选中的原文'**
  String get selectedPassage;

  /// No description provided for @xiaouInterpretation.
  ///
  /// In zh, this message translates to:
  /// **'小U的解读'**
  String get xiaouInterpretation;

  /// No description provided for @followUpsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'追问记录暂时没有同步，请稍后再试。'**
  String get followUpsUnavailable;

  /// No description provided for @continueFollowUp.
  ///
  /// In zh, this message translates to:
  /// **'继续追问'**
  String get continueFollowUp;

  /// No description provided for @xiaouThinkingSentence.
  ///
  /// In zh, this message translates to:
  /// **'小U正在想这一句…'**
  String get xiaouThinkingSentence;

  /// No description provided for @traceType.
  ///
  /// In zh, this message translates to:
  /// **'阅读痕迹'**
  String get traceType;

  /// No description provided for @originalHighlight.
  ///
  /// In zh, this message translates to:
  /// **'原始划线'**
  String get originalHighlight;

  /// No description provided for @bookTracesTitle.
  ///
  /// In zh, this message translates to:
  /// **'这本书的阅读痕迹'**
  String get bookTracesTitle;

  /// No description provided for @personalTraceCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条属于你的阅读痕迹'**
  String personalTraceCount(Object count);

  /// No description provided for @noBookTraces.
  ///
  /// In zh, this message translates to:
  /// **'这里暂时没有对应的阅读痕迹。'**
  String get noBookTraces;

  /// No description provided for @topic.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get topic;

  /// No description provided for @lookBack.
  ///
  /// In zh, this message translates to:
  /// **'回望'**
  String get lookBack;

  /// No description provided for @excerptCountRecent.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条摘录 · 最近记录 {date}'**
  String excerptCountRecent(Object count, Object date);

  /// No description provided for @entryCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String entryCount(Object count);

  /// No description provided for @noTopicEntries.
  ///
  /// In zh, this message translates to:
  /// **'这个主题下还没有条目'**
  String get noTopicEntries;

  /// No description provided for @dateUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂无'**
  String get dateUnavailable;

  /// No description provided for @unnamedBook.
  ///
  /// In zh, this message translates to:
  /// **'未命名书籍'**
  String get unnamedBook;

  /// No description provided for @topicRelatedSummary.
  ///
  /// In zh, this message translates to:
  /// **'小U轻轻看了一眼：你常在这个主题下关注：{topics}。'**
  String topicRelatedSummary(Object topics);

  /// No description provided for @topicBooksSummary.
  ///
  /// In zh, this message translates to:
  /// **'小U轻轻看了一眼：你常在这个主题下回到：{books}。'**
  String topicBooksSummary(Object books);

  /// No description provided for @topicQuietSummary.
  ///
  /// In zh, this message translates to:
  /// **'小U轻轻看了一眼：这个主题还很安静，更多摘录会慢慢显出线索。'**
  String get topicQuietSummary;

  /// No description provided for @thatDayUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'那一天的记录暂时没有打开。'**
  String get thatDayUnavailable;

  /// No description provided for @thatDayEmpty.
  ///
  /// In zh, this message translates to:
  /// **'那一天没有留下更多记录。'**
  String get thatDayEmpty;

  /// No description provided for @readingRecords.
  ///
  /// In zh, this message translates to:
  /// **'阅读记录'**
  String get readingRecords;

  /// No description provided for @writeBeforeXiaou.
  ///
  /// In zh, this message translates to:
  /// **'先写下一点内容，再交给小U观察'**
  String get writeBeforeXiaou;

  /// No description provided for @authorizingXiaou.
  ///
  /// In zh, this message translates to:
  /// **'正在交给小U观察…'**
  String get authorizingXiaou;

  /// No description provided for @revokingXiaou.
  ///
  /// In zh, this message translates to:
  /// **'正在撤回小U授权…'**
  String get revokingXiaou;

  /// No description provided for @authorizedXiaouMessage.
  ///
  /// In zh, this message translates to:
  /// **'已交给小U观察'**
  String get authorizedXiaouMessage;

  /// No description provided for @revokedXiaouMessage.
  ///
  /// In zh, this message translates to:
  /// **'已撤回小U授权'**
  String get revokedXiaouMessage;

  /// No description provided for @operationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String operationFailed(Object error);

  /// No description provided for @shareFailed.
  ///
  /// In zh, this message translates to:
  /// **'分享失败：{error}'**
  String shareFailed(Object error);

  /// No description provided for @editedOn.
  ///
  /// In zh, this message translates to:
  /// **'最近编辑 {date}'**
  String editedOn(Object date);

  /// No description provided for @readerContentLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'正文载入失败：{error}'**
  String readerContentLoadFailed(Object error);

  /// No description provided for @restoringTypography.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复阅读排版…'**
  String get restoringTypography;

  /// No description provided for @pageTextUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前格式暂时无法提取这一页的文字'**
  String get pageTextUnavailable;

  /// No description provided for @organizedByXiaou.
  ///
  /// In zh, this message translates to:
  /// **'已由小U整理'**
  String get organizedByXiaou;

  /// No description provided for @untitledBook.
  ///
  /// In zh, this message translates to:
  /// **'未命名书籍'**
  String get untitledBook;

  /// No description provided for @thoughtSavedPrivateNotShared.
  ///
  /// In zh, this message translates to:
  /// **'想法已保存为私密，尚未公开到明台'**
  String get thoughtSavedPrivateNotShared;

  /// No description provided for @thoughtPrivatePublishFailed.
  ///
  /// In zh, this message translates to:
  /// **'想法已保存为私密，公开失败：{error}'**
  String thoughtPrivatePublishFailed(Object error);

  /// No description provided for @pleaseTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'请稍后重试'**
  String get pleaseTryAgain;

  /// No description provided for @todayQuestion.
  ///
  /// In zh, this message translates to:
  /// **'今日问题 · 《{title}》'**
  String todayQuestion(Object title);

  /// No description provided for @leaveResponse.
  ///
  /// In zh, this message translates to:
  /// **'留下回应'**
  String get leaveResponse;

  /// No description provided for @enterBookPage.
  ///
  /// In zh, this message translates to:
  /// **'进入书页'**
  String get enterBookPage;

  /// No description provided for @meetReaders.
  ///
  /// In zh, this message translates to:
  /// **'也许可以先认识这些读者'**
  String get meetReaders;

  /// No description provided for @loginFollowingHint.
  ///
  /// In zh, this message translates to:
  /// **'登录后，这里会优先出现你关注的读者。'**
  String get loginFollowingHint;

  /// No description provided for @loginSameBookHint.
  ///
  /// In zh, this message translates to:
  /// **'登录后，明台会寻找与你读过同一本书的人。'**
  String get loginSameBookHint;

  /// No description provided for @followingQuietFallback.
  ///
  /// In zh, this message translates to:
  /// **'关注的读者暂时没有更新，先从这些公开阅读痕迹开始。'**
  String get followingQuietFallback;

  /// No description provided for @sameBookQuietFallback.
  ///
  /// In zh, this message translates to:
  /// **'同读的新回应还很少，先看看明台里最近留下的话。'**
  String get sameBookQuietFallback;

  /// No description provided for @mingtaiFirstResponse.
  ///
  /// In zh, this message translates to:
  /// **'明台还在等第一句话。'**
  String get mingtaiFirstResponse;

  /// No description provided for @sameBookReaderCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位公开读者'**
  String sameBookReaderCount(Object count);

  /// No description provided for @noPublicReadingStatus.
  ///
  /// In zh, this message translates to:
  /// **'还没有人公开自己的阅读状态。'**
  String get noPublicReadingStatus;

  /// No description provided for @writeDownThought.
  ///
  /// In zh, this message translates to:
  /// **'写下想法'**
  String get writeDownThought;

  /// No description provided for @noPublicBookThoughts.
  ///
  /// In zh, this message translates to:
  /// **'还没有人认真写下这本书带来的问题。'**
  String get noPublicBookThoughts;

  /// No description provided for @reportUser.
  ///
  /// In zh, this message translates to:
  /// **'举报用户'**
  String get reportUser;

  /// No description provided for @blockUserTitle.
  ///
  /// In zh, this message translates to:
  /// **'拉黑 {name}？'**
  String blockUserTitle(Object name);

  /// No description provided for @blockUserBody.
  ///
  /// In zh, this message translates to:
  /// **'双方将不再看到彼此的动态，也会自动取消关注关系。'**
  String get blockUserBody;

  /// No description provided for @confirmBlock.
  ///
  /// In zh, this message translates to:
  /// **'确认拉黑'**
  String get confirmBlock;

  /// No description provided for @readingProfile.
  ///
  /// In zh, this message translates to:
  /// **'阅读档案'**
  String get readingProfile;

  /// No description provided for @editProfile.
  ///
  /// In zh, this message translates to:
  /// **'编辑资料'**
  String get editProfile;

  /// No description provided for @bioEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有写下一句话介绍。'**
  String get bioEmpty;

  /// No description provided for @follow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get follow;

  /// No description provided for @followed.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get followed;

  /// No description provided for @profileFollowSummary.
  ///
  /// In zh, this message translates to:
  /// **'{followers} 位读者关注 · 正在读 {books} 本'**
  String profileFollowSummary(Object books, Object followers);

  /// No description provided for @currentlyReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读'**
  String get currentlyReading;

  /// No description provided for @finishedReading.
  ///
  /// In zh, this message translates to:
  /// **'读过'**
  String get finishedReading;

  /// No description provided for @wantToRead.
  ///
  /// In zh, this message translates to:
  /// **'想读'**
  String get wantToRead;

  /// No description provided for @savedReadingTraces.
  ///
  /// In zh, this message translates to:
  /// **'收藏的阅读痕迹'**
  String get savedReadingTraces;

  /// No description provided for @publicThoughtsDiscussions.
  ///
  /// In zh, this message translates to:
  /// **'公开想法与讨论'**
  String get publicThoughtsDiscussions;

  /// No description provided for @noPublicThoughts.
  ///
  /// In zh, this message translates to:
  /// **'还没有公开留下阅读想法。'**
  String get noPublicThoughts;

  /// No description provided for @deletePublicContentTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这条公开内容？'**
  String get deletePublicContentTitle;

  /// No description provided for @deletePublicContentBody.
  ///
  /// In zh, this message translates to:
  /// **'相关短摘录、评论和共鸣也会一起删除，且无法恢复。'**
  String get deletePublicContentBody;

  /// No description provided for @publicContentDeleted.
  ///
  /// In zh, this message translates to:
  /// **'公开内容已删除'**
  String get publicContentDeleted;

  /// No description provided for @originalTextPrefix.
  ///
  /// In zh, this message translates to:
  /// **'原文 · '**
  String get originalTextPrefix;

  /// No description provided for @expandOriginal.
  ///
  /// In zh, this message translates to:
  /// **'展开原文'**
  String get expandOriginal;

  /// No description provided for @collapseOriginal.
  ///
  /// In zh, this message translates to:
  /// **'收起原文'**
  String get collapseOriginal;

  /// No description provided for @loginBeforePublishing.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再发布'**
  String get loginBeforePublishing;

  /// No description provided for @thoughtMinFive.
  ///
  /// In zh, this message translates to:
  /// **'请至少写下 5 个字的完整想法'**
  String get thoughtMinFive;

  /// No description provided for @reviewMinTen.
  ///
  /// In zh, this message translates to:
  /// **'公开书评至少需要 10 个字'**
  String get reviewMinTen;

  /// No description provided for @highlightRequiresExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'公开划线需要包含一段短摘录'**
  String get highlightRequiresExcerpt;

  /// No description provided for @excerptTooLong.
  ///
  /// In zh, this message translates to:
  /// **'公开摘录不能超过 240 个字符'**
  String get excerptTooLong;

  /// No description provided for @selectBookFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一本书'**
  String get selectBookFirst;

  /// No description provided for @privateShelfNoBooks.
  ///
  /// In zh, this message translates to:
  /// **'私人书架还没有可关联的书。'**
  String get privateShelfNoBooks;

  /// No description provided for @readingUpdate.
  ///
  /// In zh, this message translates to:
  /// **'正在读'**
  String get readingUpdate;

  /// No description provided for @publicHighlight.
  ///
  /// In zh, this message translates to:
  /// **'公开划线'**
  String get publicHighlight;

  /// No description provided for @readingThought.
  ///
  /// In zh, this message translates to:
  /// **'阅读想法'**
  String get readingThought;

  /// No description provided for @sameBookDiscussion.
  ///
  /// In zh, this message translates to:
  /// **'同书讨论'**
  String get sameBookDiscussion;

  /// No description provided for @reportComment.
  ///
  /// In zh, this message translates to:
  /// **'举报评论'**
  String get reportComment;

  /// No description provided for @cancelQuote.
  ///
  /// In zh, this message translates to:
  /// **'取消引用'**
  String get cancelQuote;

  /// No description provided for @searchUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'搜索暂时没有回应'**
  String get searchUnavailable;

  /// No description provided for @noSearchCommunityResults.
  ///
  /// In zh, this message translates to:
  /// **'明台还没有找到相关书页或讨论。'**
  String get noSearchCommunityResults;

  /// No description provided for @books.
  ///
  /// In zh, this message translates to:
  /// **'书籍'**
  String get books;

  /// No description provided for @sharedQuestion.
  ///
  /// In zh, this message translates to:
  /// **'提出了一个问题'**
  String get sharedQuestion;

  /// No description provided for @sharedFragmentThought.
  ///
  /// In zh, this message translates to:
  /// **'在一段原文旁留下想法'**
  String get sharedFragmentThought;

  /// No description provided for @sharedReadingStatus.
  ///
  /// In zh, this message translates to:
  /// **'分享了阅读阶段感受'**
  String get sharedReadingStatus;

  /// No description provided for @sharedCurrentReading.
  ///
  /// In zh, this message translates to:
  /// **'分享了正在读'**
  String get sharedCurrentReading;

  /// No description provided for @sharedExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'分享了一段摘录'**
  String get sharedExcerpt;

  /// No description provided for @sharedReview.
  ///
  /// In zh, this message translates to:
  /// **'留下了一段短评'**
  String get sharedReview;

  /// No description provided for @sharedReadingThought.
  ///
  /// In zh, this message translates to:
  /// **'写下了阅读想法'**
  String get sharedReadingThought;

  /// No description provided for @autosaving.
  ///
  /// In zh, this message translates to:
  /// **'正在安静保存…'**
  String get autosaving;

  /// No description provided for @dailyQuestionOne.
  ///
  /// In zh, this message translates to:
  /// **'这本书里，哪一句话改变了你理解它的方式？'**
  String get dailyQuestionOne;

  /// No description provided for @dailyQuestionTwo.
  ///
  /// In zh, this message translates to:
  /// **'你在这本书的哪一处停了下来？'**
  String get dailyQuestionTwo;

  /// No description provided for @dailyQuestionThree.
  ///
  /// In zh, this message translates to:
  /// **'读到现在，你最想和同书读者确认什么？'**
  String get dailyQuestionThree;

  /// No description provided for @dailyQuestionFour.
  ///
  /// In zh, this message translates to:
  /// **'如果只留下一个问题，你会把什么带出这本书？'**
  String get dailyQuestionFour;

  /// No description provided for @translatorLabel.
  ///
  /// In zh, this message translates to:
  /// **'{name} 译'**
  String translatorLabel(Object name);

  /// No description provided for @bookCommunitySummary.
  ///
  /// In zh, this message translates to:
  /// **'{posts} 条公开表达 · {readers} 人正在读'**
  String bookCommunitySummary(Object posts, Object readers);

  /// No description provided for @deleteThisContent.
  ///
  /// In zh, this message translates to:
  /// **'删除这条内容'**
  String get deleteThisContent;

  /// No description provided for @reportThisContent.
  ///
  /// In zh, this message translates to:
  /// **'举报这条内容'**
  String get reportThisContent;

  /// No description provided for @responseCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条回应'**
  String responseCount(Object count);

  /// No description provided for @quotedText.
  ///
  /// In zh, this message translates to:
  /// **'引用：“{text}”'**
  String quotedText(Object text);

  /// No description provided for @readingStatusHint.
  ///
  /// In zh, this message translates to:
  /// **'此刻读到哪里，为什么停下来'**
  String get readingStatusHint;

  /// No description provided for @excerptThoughtHint.
  ///
  /// In zh, this message translates to:
  /// **'这段原文为什么值得留下'**
  String get excerptThoughtHint;

  /// No description provided for @reviewHint.
  ///
  /// In zh, this message translates to:
  /// **'这本书给你留下了什么'**
  String get reviewHint;

  /// No description provided for @questionHint.
  ///
  /// In zh, this message translates to:
  /// **'你想和同书读者讨论什么'**
  String get questionHint;

  /// No description provided for @yourThought.
  ///
  /// In zh, this message translates to:
  /// **'你的想法'**
  String get yourThought;

  /// No description provided for @notificationFollow.
  ///
  /// In zh, this message translates to:
  /// **'{name} 关注了你的阅读档案'**
  String notificationFollow(Object name);

  /// No description provided for @notificationComment.
  ///
  /// In zh, this message translates to:
  /// **'{name} 回应了你的阅读想法'**
  String notificationComment(Object name);

  /// No description provided for @notificationQuote.
  ///
  /// In zh, this message translates to:
  /// **'{name} 引用了你的阅读想法'**
  String notificationQuote(Object name);

  /// No description provided for @notificationResonance.
  ///
  /// In zh, this message translates to:
  /// **'{name} 与你的想法产生了共鸣'**
  String notificationResonance(Object name);

  /// No description provided for @notificationDefault.
  ///
  /// In zh, this message translates to:
  /// **'{name} 在明台留下了回应'**
  String notificationDefault(Object name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
