// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ReadU';

  @override
  String get appTagline => 'Let your reading traces slowly come into view';

  @override
  String get tabBookshelf => 'Library';

  @override
  String get tabXiaou => 'Xiaou';

  @override
  String get tabFreeNotes => 'Free Notes';

  @override
  String get tabMingtai => 'Mingtai';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'Follow your device or choose a language';

  @override
  String get followSystem => 'System Default';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get featureGuide => 'Feature Guide';

  @override
  String get viewGuideAgain => 'View Feature Guide Again';

  @override
  String get viewGuideAgainSubtitle =>
      'Show the short guide the next time you enter each area';

  @override
  String get guideResetMessage => 'Feature guides have been reset.';

  @override
  String get about => 'About';

  @override
  String versionLabel(Object version) {
    return 'Version $version';
  }

  @override
  String get aboutTagline => 'Thoughtful AI-assisted reading';

  @override
  String get loginRegister => 'Sign In / Register';

  @override
  String get notSignedIn => 'Not Signed In';

  @override
  String get signInSyncSubtitle =>
      'Sign in to sync reading progress and Xiaou entries';

  @override
  String get myReadingProfile => 'My Reading Profile';

  @override
  String get myReadingProfileSubtitle =>
      'Avatar, name, current books, and public thoughts';

  @override
  String get cloudAccountConnected => 'Cloud account connected';

  @override
  String get switchAccount => 'Switch Account';

  @override
  String get logout => 'Sign Out';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountTitle => 'Delete ReadU Account';

  @override
  String get deleteAccountBody =>
      'Your account, cloud reading records, free notes, Xiaou conversations, and public content will be permanently deleted. Local ebook files on this device will not be removed automatically. This action cannot be undone.';

  @override
  String get currentPassword => 'Current password';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get deletePermanently => 'Delete Permanently';

  @override
  String get accountDeleted =>
      'Your account and associated cloud data have been deleted.';

  @override
  String deleteAccountFailed(Object error) {
    return 'Account deletion failed: $error';
  }

  @override
  String get privacySecurity => 'Privacy & Safety';

  @override
  String get xiaouThirdPartyAi => 'Xiaou & Third-Party AI';

  @override
  String get xiaouThirdPartyAiSubtitle =>
      'Review or withdraw DeepSeek data processing consent';

  @override
  String get mingtaiVisibility => 'Mingtai Visibility';

  @override
  String get mingtaiVisibilitySubtitle =>
      'Control reading status, progress, follows, and same-book discovery';

  @override
  String get communityRules => 'Community Rules & Reports';

  @override
  String get communityRulesSubtitle =>
      'View public content rules and contact information';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicySubtitle =>
      'How ReadU processes and protects your data';

  @override
  String get dataCollectionList => 'Data Collection List';

  @override
  String get dataCollectionListSubtitle =>
      'Review data types, purposes, uploads, and retention';

  @override
  String get thirdPartyList => 'Third-Party Services';

  @override
  String get thirdPartyListSubtitle =>
      'Cloud services, DeepSeek, and Apple system capabilities';

  @override
  String get aiDataProcessing => 'AI & Data Processing';

  @override
  String get aiDataProcessingSubtitle =>
      'What Xiaou sends and how to withdraw consent';

  @override
  String get accountDataDeletion => 'Account & Data Deletion';

  @override
  String get accountDataDeletionSubtitle =>
      'Deletion path, scope, and processing time';

  @override
  String get pageUnavailable =>
      'This page is temporarily unavailable. Check your connection and try again.';

  @override
  String get retry => 'Try Again';

  @override
  String get authAccount => 'Account';

  @override
  String get login => 'Sign In';

  @override
  String get register => 'Register';

  @override
  String get welcomeBack => 'Welcome Back';

  @override
  String get createAccount => 'Create Account';

  @override
  String get loginSubtitle => 'Sign in to sync your reading data';

  @override
  String get registerSubtitle =>
      'Sync reading progress and notes across devices';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get enterEmail => 'Enter your email';

  @override
  String get invalidEmail => 'Enter a valid email address';

  @override
  String get enterPassword => 'Enter your password';

  @override
  String get passwordMinLength => 'Password must be at least 6 characters';

  @override
  String get localDataMergeNotice =>
      'After registration, existing data on this device will be merged into your new account.';

  @override
  String get importBook => 'Import Book';

  @override
  String get importEbook => 'Import Ebook';

  @override
  String get supportedBookFormats => 'Supports EPUB · TXT · PDF';

  @override
  String get importLocalFile => 'Import from Device';

  @override
  String get importLocalFileSubtitle => 'Choose an EPUB, TXT, or PDF file';

  @override
  String get downloadFromLink => 'Download from Link';

  @override
  String get downloadFromLinkSubtitle =>
      'Enter an EPUB, TXT, or PDF download URL';

  @override
  String get downloadLinkHint => 'Enter the EPUB / TXT / PDF file URL';

  @override
  String get download => 'Download';

  @override
  String get emptyBookshelf => 'Your library is empty';

  @override
  String get emptyBookshelfSubtitle => 'Import your first ebook to begin';

  @override
  String get shareReadingThought => 'Share a Reading Thought';

  @override
  String get shareReadingThoughtSubtitle =>
      'Links book information only; the ebook file is never uploaded';

  @override
  String get legacyPublicBookDisabled =>
      'Legacy Mingtai borrowing is no longer available. Please import an ebook you are legally entitled to read into your private library.';

  @override
  String get deleteBook => 'Delete Book';

  @override
  String deleteBookConfirm(Object title) {
    return 'Delete “$title”?\nIts related notes and highlights will also be deleted.';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get refreshFailedRetained =>
      'Refresh failed. Existing content has been kept.';

  @override
  String get bookshelfUnavailable => 'Your library is temporarily unavailable';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get tableOfContents => 'Contents';

  @override
  String get reloadContent => 'Reload Content';

  @override
  String get readerOpenFailed => 'Unable to Open Book';

  @override
  String get readerAskXiaou => 'Ask Xiaou';

  @override
  String get readerAskCompact => 'Ask';

  @override
  String get readerExplain => 'Explain';

  @override
  String get readerExplainCompact => 'Explain';

  @override
  String get readerThought => 'Add Thought';

  @override
  String get readerThoughtCompact => 'Thought';

  @override
  String get readerHighlight => 'Highlight';

  @override
  String get readerTranslate => 'Translate';

  @override
  String get readerClose => 'Close';

  @override
  String get privateOnly => 'Only Me';

  @override
  String get shareToMingtai => 'Share to Mingtai';

  @override
  String get thoughtSavedPrivate => 'Thought saved privately';

  @override
  String get publishedToMingtai => 'Published to Mingtai';

  @override
  String get aiGeneratedNotice =>
      'AI-generated content may be inaccurate. Please check it against the original text.';

  @override
  String get freeNotesTitle => 'Free Notes';

  @override
  String get freeNotesSubtitle =>
      'A quiet place for whatever passes through your mind';

  @override
  String get writeNote => 'Write';

  @override
  String get searchFreeNotes => 'Search something you once wrote';

  @override
  String get writeWhatYouThink => 'Write what comes to mind.';

  @override
  String get todayEcho => 'Today’s Echo';

  @override
  String get privateOnlyNote => 'Only visible to you';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving...';

  @override
  String get deleteRecord => 'Delete Note';

  @override
  String get deleteRecordConfirm =>
      'This private note will be permanently deleted.';

  @override
  String get titleOptional => 'Title (optional)';

  @override
  String get noteBodyHint =>
      'No need to organize or explain.\nWrite what is passing through your mind...';

  @override
  String get xiaouTitle => 'Xiaou';

  @override
  String get readingTraces => 'Reading Traces';

  @override
  String get searchTraces => 'Search a sentence, book, or thought';

  @override
  String get allBooks => 'All Books';

  @override
  String get all => 'All';

  @override
  String get thoughts => 'Thoughts';

  @override
  String get highlights => 'Highlights';

  @override
  String get xiaouExplanations => 'Explanations';

  @override
  String get xiaouQuestions => 'Questions';

  @override
  String get importantOnly => 'Important Only';

  @override
  String get expand => 'Expand';

  @override
  String get collapse => 'Collapse';

  @override
  String get delete => 'Delete';

  @override
  String get undo => 'Undo';

  @override
  String get markImportant => 'Mark Important';

  @override
  String get unmarkImportant => 'Remove Important';

  @override
  String get chatWithXiaou => 'Talk with Xiaou';

  @override
  String get askXiaouDirectly => 'Ask Xiaou directly...';

  @override
  String get newConversation => 'New Conversation';

  @override
  String get conversationHistory => 'Past Conversations';

  @override
  String get saveToFreeNotes => 'Save to Free Notes';

  @override
  String get mingtaiTitle => 'Mingtai';

  @override
  String get mingtaiSearch => 'Find a book, author, or sentence';

  @override
  String get recommended => 'For You';

  @override
  String get following => 'Following';

  @override
  String get readingTogether => 'Same Book';

  @override
  String get leaveReadingTrace => 'Leave a Reading Note';

  @override
  String get loginToJoin => 'Sign in to join the conversation on Mingtai';

  @override
  String get reply => 'Respond';

  @override
  String get quoteReply => 'Quote & Respond';

  @override
  String get favorite => 'Save';

  @override
  String get unfavorite => 'Unsave';

  @override
  String get viewSameBook => 'More from This Book';

  @override
  String get notifications => 'Mingtai Activity';

  @override
  String get noNotifications => 'No new echoes yet.';

  @override
  String get report => 'Report';

  @override
  String get blockUser => 'Block User';

  @override
  String get loading => 'Loading…';

  @override
  String get empty => 'Nothing here yet.';

  @override
  String get networkSlow => 'The network seems slow. Please try again shortly.';

  @override
  String get close => 'Close';

  @override
  String get clear => 'Clear';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String get tryIt => 'Try It';

  @override
  String get gotIt => 'Got It';

  @override
  String get syncFailedLocalRetained =>
      'Sync is temporarily unavailable. Notes on this device are safe.';

  @override
  String get readerQuestionSelection => 'Selection';

  @override
  String get readerQuestionPage => 'Current Page';

  @override
  String get readerQuestionChapter => 'Chapter';

  @override
  String get readerQuestionPrompt =>
      'Ask a specific question.\nXiaou will ground its answer in the text in front of you.';

  @override
  String get readerQuestionHint => 'Ask Xiaou about this text…';

  @override
  String get readerQuestionEmpty =>
      'Xiaou could not make this out yet. Try asking in another way.';

  @override
  String get readerQuestionSaveFailed =>
      'The answer was generated, but this turn could not be synced.';

  @override
  String get readerQuestionThinking => 'Xiaou is reading this passage…';

  @override
  String get readingTypography => 'Reading Layout';

  @override
  String get resetDefaults => 'Reset';

  @override
  String get readingPreview => 'Preview';

  @override
  String get font => 'Font';

  @override
  String get fontSystem => 'System';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontWenkai => 'WenKai';

  @override
  String get typography => 'Layout';

  @override
  String get fontSize => 'Text Size';

  @override
  String get lineHeight => 'Line Spacing';

  @override
  String get pageMargin => 'Margins';

  @override
  String get pagingMode => 'Page Movement';

  @override
  String get verticalScroll => 'Vertical Scroll';

  @override
  String get horizontalPaging => 'Horizontal Pages';

  @override
  String get paperBackground => 'Paper';

  @override
  String get paperWhite => 'White';

  @override
  String get paperSepia => 'Warm';

  @override
  String get paperGreen => 'Eye Comfort';

  @override
  String get paperDark => 'Night';

  @override
  String get readerGuideTitle => 'Press and hold any text';

  @override
  String get readerGuideBody =>
      'Ask a question, get an explanation, highlight it, or add a thought.';

  @override
  String get readerGuideSelectionTip =>
      'Ask Xiaou here, or open an explanation.';

  @override
  String get xiaouGuideTitle => 'This is Xiaou.';

  @override
  String get xiaouGuideBody =>
      'Open it when you have a question, want to follow a thought, or look back on your reading traces.';

  @override
  String get xiaouGuideAction => 'Take a Look';

  @override
  String get mingtaiGuideTitle => 'Welcome to Mingtai';

  @override
  String get mingtaiGuideBody =>
      'Read passages, thoughts, and reviews people have chosen to share, or join a discussion around a book.';

  @override
  String get mingtaiGuidePrivacy =>
      'Your content stays private unless you explicitly choose to share it.';

  @override
  String get browseMingtai => 'Browse Mingtai';

  @override
  String get learnSharing => 'How Sharing Works';

  @override
  String get sharingIsYourChoice => 'Sharing is always your choice';

  @override
  String get sharingGuideBody =>
      'Select text in the reader, add a thought, then choose Share to Mingtai. You can also leave a reading note from Mingtai. You will always see a confirmation before anything becomes public.';

  @override
  String get newFreeNote => 'New Note';

  @override
  String get freeNotesSyncUnavailable => 'Free Notes could not sync';

  @override
  String get freeNotesSyncRetained =>
      'Notes on this device were not cleared. Try again when your connection returns.';

  @override
  String get clearSearch => 'Clear Search';

  @override
  String get backToThatDay => 'Back to That Day';

  @override
  String get thatDay => 'That Day';

  @override
  String createdOnEditedOn(Object created, Object updated) {
    return 'Written $created · Edited $updated';
  }

  @override
  String createdOn(Object created) {
    return 'Written $created';
  }

  @override
  String get earlier => 'Earlier';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get thisWeek => 'This Week';

  @override
  String get thisMonth => 'This Month';

  @override
  String get untitledMoment => 'Untitled Moment';

  @override
  String get xiaouLoadRetained =>
      'Could not refresh. The last content you saw has been kept.';

  @override
  String deletedEntry(Object type) {
    return 'Deleted $type';
  }

  @override
  String deleteFailed(Object error) {
    return 'Could not delete: $error';
  }

  @override
  String importanceSaveFailed(Object error) {
    return 'Could not update importance: $error';
  }

  @override
  String get noMatchingTraces => 'No reading traces match these filters yet.';

  @override
  String get noNewTraces =>
      'No new reading traces are available yet. Try again shortly.';

  @override
  String get tracesEmptyBody =>
      'Highlights, thoughts, and Xiaou explanations will gather quietly here.';

  @override
  String get xiaouDiscovery => 'Xiaou noticed something';

  @override
  String get xiaouChatSubtitle =>
      'Ask directly. Xiaou will try to ground the question in your reading.';

  @override
  String get xiaouStartFromReading => 'Begin with what you are reading';

  @override
  String get xiaouStartBody =>
      'Type anything, or begin with one of these starting points.';

  @override
  String get xiaouThinking =>
      'Xiaou is looking back through your reading traces…';

  @override
  String get conversationDeleteTitle => 'Delete this conversation?';

  @override
  String get conversationDeleteBody =>
      'This cannot be undone. Anything already saved to Free Notes will stay there.';

  @override
  String get noConversationHistory => 'No saved conversations yet.';

  @override
  String get mingtaiUnavailable => 'Mingtai is temporarily unavailable';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get shareCurrentReading => 'Share What You’re Reading';

  @override
  String get shareCurrentReadingSubtitle =>
      'Say where you are and why you paused';

  @override
  String get publishHighlight => 'Share a Highlight';

  @override
  String get publishHighlightSubtitle =>
      'Share a short excerpt and why it held you';

  @override
  String get writeThought => 'Write a Thought';

  @override
  String get writeThoughtSubtitle => 'Leave your understanding of this book';

  @override
  String get writeReview => 'Write a Review';

  @override
  String get writeReviewSubtitle =>
      'Leave a considered reflection after reading';

  @override
  String get mingtaiComposeTitle => 'Leave a Reading Note';

  @override
  String get mingtaiComposePrivacy =>
      'Every public post must be connected to a book.';

  @override
  String get loginRequiredMingtai => 'Sign in to join discussions on Mingtai';

  @override
  String get noMeaningfulMingtaiContent =>
      'Mingtai is waiting for its first thought.';

  @override
  String get startWithBook =>
      'Begin with a book you are reading and leave one honest question or thought.';

  @override
  String get sameBookSpace => 'Same-Book Space';

  @override
  String get publicExpressions => 'Public Thoughts & Questions';

  @override
  String get xiaouAsksMe => 'Xiaou Asks Me';

  @override
  String get xiaouAsksSubtitle =>
      'Begin an open conversation from your reading.';

  @override
  String get chatHistory => 'History';

  @override
  String get conversationActions => 'Conversation Actions';

  @override
  String get saveWholeConversation => 'Save Conversation to Free Notes';

  @override
  String get changeQuestion => 'Another Question';

  @override
  String get endConversation => 'End Conversation';

  @override
  String get xiaouAnswerHint => 'Answer, ask back, or keep going…';

  @override
  String get xiaouAskMeSubtitle => 'Let Xiaou ask a question from your reading';

  @override
  String get quickExplainLabel => 'Explain What I Just Read';

  @override
  String get quickExplainPrompt =>
      'Look at what I have read recently and help me identify the one part I most need to understand.';

  @override
  String get quickReviewLabel => 'Look Back on My Highlights';

  @override
  String get quickReviewPrompt =>
      'Look back on my recent highlights and notes. Is there a connection worth following?';

  @override
  String get quickBookChatLabel => 'Talk About This Book';

  @override
  String get quickBookChatPrompt =>
      'Start with the book I have been reading recently and talk with me about the question where I paused most often.';

  @override
  String get sameBookReaders => 'Readers of This Book';

  @override
  String get latest => 'Latest';

  @override
  String get mostDiscussed => 'Discussed';

  @override
  String get nearMyProgress => 'Near My Progress';

  @override
  String get publicExcerpt => 'Public Excerpts';

  @override
  String get fragmentThought => 'Passage Thoughts';

  @override
  String get readingReflection => 'Reading Reflections';

  @override
  String get bookReview => 'Reviews';

  @override
  String get publicReadingExpressions => 'Public Notes on This Book';

  @override
  String get noSameBookThoughts =>
      'No one has left a considered question about this book yet.';

  @override
  String get selectBook => 'Book';

  @override
  String get postType => 'Type';

  @override
  String get shortExcerpt => 'Short Excerpt';

  @override
  String get shortExcerptOptional => 'Short Excerpt (Optional)';

  @override
  String get shortExcerptHint =>
      'Use only the short passage needed for this discussion';

  @override
  String get readingPositionOptional => 'Reading Position (Optional)';

  @override
  String get readingPositionHint => 'For example: Part I, Chapter 3';

  @override
  String get publishing => 'Publishing…';

  @override
  String get publishToMingtai => 'Publish to Mingtai';

  @override
  String get continueDiscussion => 'Continue the Discussion';

  @override
  String get noReplies => 'No responses yet.';

  @override
  String get writeReply => 'Write a response…';

  @override
  String get selectQuote => 'Choose a sentence to respond to';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(Object count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(Object count) {
    return '$count hr ago';
  }

  @override
  String daysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String get explainModeAuto => 'Auto';

  @override
  String get explainModePlain => 'Plain';

  @override
  String get explainModeStructure => 'Structure';

  @override
  String get explainModeConcept => 'Concepts';

  @override
  String get explainModeArgument => 'Argument';

  @override
  String get explainModeAutoFull => 'Xiaou Explanation';

  @override
  String get explainModePlainFull => 'Plain Explanation';

  @override
  String get explainModeStructureFull => 'Structural Breakdown';

  @override
  String get explainModeConceptFull => 'Concept Distinctions';

  @override
  String get explainModeArgumentFull => 'Argument Flow';

  @override
  String get xiaouOrganizing => 'Xiaou is organizing an answer';

  @override
  String get followUpHint => 'Ask a follow-up…';

  @override
  String get passageUnavailable =>
      'This passage could not be opened. Please try again shortly.';

  @override
  String get aiLoginRequired => 'Sign in to use Xiaou';

  @override
  String get aiConsentTitle => 'Before Using Xiaou';

  @override
  String get aiConsentBody =>
      'To generate a Xiaou explanation, the selected text, relevant context, your question, and the minimum reading traces needed for the answer will be sent to the third-party AI service DeepSeek.\n\nXiaou conversations may also use your highlights, thoughts, Xiaou explanations, and Free Notes you explicitly authorize. Your private ebook files are not sent.\n\nDo not submit sensitive information such as identity documents, medical information, or passwords. AI-generated content may be inaccurate; check it against the original text.';

  @override
  String get decline => 'Not Now';

  @override
  String get agreeContinue => 'Agree & Continue';

  @override
  String aiConsentLoadFailed(Object error) {
    return 'Could not check AI consent: $error';
  }

  @override
  String aiConsentSaveFailed(Object error) {
    return 'Could not save AI consent: $error';
  }

  @override
  String get view => 'View';

  @override
  String get writeThoughtFirst => 'Write your thought first';

  @override
  String get publicThoughtMinLength =>
      'A public thought must contain at least 5 characters';

  @override
  String get thoughtPrompt => 'What did this passage bring to mind?';

  @override
  String get privateThoughtExplanation =>
      'Saved to your private reading traces. It will not be shared automatically.';

  @override
  String get publicThoughtExplanation =>
      'This will appear at the edge of the book’s public page. Anything not shared remains private.';

  @override
  String get keepPrivate => 'Keep Private';

  @override
  String get loginToPublish => 'Sign in to publish on Mingtai';

  @override
  String get writeThisMoment => 'Write This Moment';

  @override
  String get returnToThisPage => 'Return to This Page';

  @override
  String get privatePageSubtitle => 'A private page that belongs only to you';

  @override
  String get more => 'More';

  @override
  String get authorizeXiaou => 'Let Xiaou Reflect on This';

  @override
  String get revokeXiaou => 'Remove Xiaou Access';

  @override
  String get shareText => 'Share as Text';

  @override
  String get shareImage => 'Share as Image';

  @override
  String get authorizedToXiaou =>
      'Shared with Xiaou · You can revoke access anytime';

  @override
  String get noSearchResultTitle => 'That sentence wasn’t found';

  @override
  String get noSearchResultBody => 'Try another word and look again';

  @override
  String get noBookmarks => 'No bookmarks yet';

  @override
  String get deleteBookmarkTitle => 'Delete Bookmark';

  @override
  String get deleteBookmarkBody => 'Delete this bookmark?';

  @override
  String get expandFullExplanation => 'Open Full Explanation';

  @override
  String followUpCount(Object count) {
    return '$count follow-ups';
  }

  @override
  String followUpCountWithQuestion(Object count, Object question) {
    return '$count follow-ups · $question';
  }

  @override
  String chapterNumber(Object number) {
    return 'Chapter $number';
  }

  @override
  String get chapterUnknown => 'Chapter not recorded';

  @override
  String get bookUnknown => 'Book not recorded';

  @override
  String get selectedPassage => 'Selected Passage';

  @override
  String get xiaouInterpretation => 'Xiaou’s Explanation';

  @override
  String get followUpsUnavailable =>
      'Follow-ups could not sync. Please try again later.';

  @override
  String get continueFollowUp => 'Continue the Conversation';

  @override
  String get xiaouThinkingSentence => 'Xiaou is thinking about this…';

  @override
  String get traceType => 'Reading Trace';

  @override
  String get originalHighlight => 'Original Highlight';

  @override
  String get bookTracesTitle => 'Reading Traces from This Book';

  @override
  String personalTraceCount(Object count) {
    return '$count personal reading traces';
  }

  @override
  String get noBookTraces => 'No reading traces match this view yet.';

  @override
  String get topic => 'Theme';

  @override
  String get lookBack => 'Looking Back';

  @override
  String excerptCountRecent(Object count, Object date) {
    return '$count excerpts · Last recorded $date';
  }

  @override
  String entryCount(Object count) {
    return '$count entries';
  }

  @override
  String get noTopicEntries => 'No entries under this theme yet';

  @override
  String get dateUnavailable => 'Not available';

  @override
  String get unnamedBook => 'Untitled Book';

  @override
  String topicRelatedSummary(Object topics) {
    return 'Xiaou noticed that you often return to these ideas here: $topics.';
  }

  @override
  String topicBooksSummary(Object books) {
    return 'Xiaou noticed that this theme often brings you back to $books.';
  }

  @override
  String get topicQuietSummary =>
      'This theme is still quiet. More excerpts may reveal a clearer connection over time.';

  @override
  String get thatDayUnavailable => 'Records from that day could not be opened.';

  @override
  String get thatDayEmpty => 'Nothing else was recorded that day.';

  @override
  String get readingRecords => 'Reading Records';

  @override
  String get writeBeforeXiaou => 'Write something before sharing it with Xiaou';

  @override
  String get authorizingXiaou => 'Sharing with Xiaou…';

  @override
  String get revokingXiaou => 'Removing Xiaou access…';

  @override
  String get authorizedXiaouMessage => 'Shared with Xiaou';

  @override
  String get revokedXiaouMessage => 'Xiaou access removed';

  @override
  String operationFailed(Object error) {
    return 'Could not complete this action: $error';
  }

  @override
  String shareFailed(Object error) {
    return 'Could not share: $error';
  }

  @override
  String editedOn(Object date) {
    return 'Edited $date';
  }

  @override
  String readerContentLoadFailed(Object error) {
    return 'Could not load the text: $error';
  }

  @override
  String get restoringTypography => 'Restoring reading layout…';

  @override
  String get pageTextUnavailable =>
      'Text extraction is not available for this page format';

  @override
  String get organizedByXiaou => 'Organized by Xiaou';

  @override
  String get untitledBook => 'Untitled Book';

  @override
  String get thoughtSavedPrivateNotShared =>
      'Thought saved privately and not shared to Mingtai';

  @override
  String thoughtPrivatePublishFailed(Object error) {
    return 'Thought saved privately, but publishing failed: $error';
  }

  @override
  String get pleaseTryAgain => 'Please try again shortly';

  @override
  String todayQuestion(Object title) {
    return 'Today’s Question · $title';
  }

  @override
  String get leaveResponse => 'Leave a Response';

  @override
  String get enterBookPage => 'Open Book Page';

  @override
  String get meetReaders => 'Readers you may want to meet';

  @override
  String get loginFollowingHint =>
      'Sign in to see updates from readers you follow.';

  @override
  String get loginSameBookHint =>
      'Sign in to find readers who have read the same books.';

  @override
  String get followingQuietFallback =>
      'Readers you follow have no recent updates. Here are a few public reading traces instead.';

  @override
  String get sameBookQuietFallback =>
      'There are few new same-book responses. Here are recent thoughts from Mingtai.';

  @override
  String get mingtaiFirstResponse =>
      'Mingtai is waiting for its first response.';

  @override
  String sameBookReaderCount(Object count) {
    return '$count public readers';
  }

  @override
  String get noPublicReadingStatus =>
      'No one has made their reading status public yet.';

  @override
  String get writeDownThought => 'Write a Thought';

  @override
  String get noPublicBookThoughts =>
      'No one has left a considered question about this book yet.';

  @override
  String get reportUser => 'Report User';

  @override
  String blockUserTitle(Object name) {
    return 'Block $name?';
  }

  @override
  String get blockUserBody =>
      'You will no longer see each other’s posts, and any follow relationship will be removed.';

  @override
  String get confirmBlock => 'Block';

  @override
  String get readingProfile => 'Reading Profile';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get bioEmpty => 'No introduction yet.';

  @override
  String get follow => 'Follow';

  @override
  String get followed => 'Following';

  @override
  String profileFollowSummary(Object books, Object followers) {
    return '$followers followers · Reading $books books';
  }

  @override
  String get currentlyReading => 'Currently Reading';

  @override
  String get finishedReading => 'Finished';

  @override
  String get wantToRead => 'Want to Read';

  @override
  String get savedReadingTraces => 'Saved Reading Traces';

  @override
  String get publicThoughtsDiscussions => 'Public Thoughts & Discussions';

  @override
  String get noPublicThoughts => 'No public reading thoughts yet.';

  @override
  String get deletePublicContentTitle => 'Delete this public post?';

  @override
  String get deletePublicContentBody =>
      'Its excerpt, comments, and resonances will also be deleted. This cannot be undone.';

  @override
  String get publicContentDeleted => 'Public post deleted';

  @override
  String get originalTextPrefix => 'Passage · ';

  @override
  String get expandOriginal => 'Expand Passage';

  @override
  String get collapseOriginal => 'Collapse Passage';

  @override
  String get loginBeforePublishing => 'Sign in before publishing';

  @override
  String get thoughtMinFive =>
      'Write at least 5 characters of a complete thought';

  @override
  String get reviewMinTen =>
      'A public review must contain at least 10 characters';

  @override
  String get highlightRequiresExcerpt =>
      'A public highlight needs a short excerpt';

  @override
  String get excerptTooLong => 'A public excerpt cannot exceed 240 characters';

  @override
  String get selectBookFirst => 'Choose a book first';

  @override
  String get privateShelfNoBooks =>
      'Your private library has no books to link yet.';

  @override
  String get readingUpdate => 'Reading Update';

  @override
  String get publicHighlight => 'Public Highlight';

  @override
  String get readingThought => 'Reading Thought';

  @override
  String get sameBookDiscussion => 'Same-Book Discussion';

  @override
  String get reportComment => 'Report Comment';

  @override
  String get cancelQuote => 'Cancel Quote';

  @override
  String get searchUnavailable => 'Search is temporarily unavailable';

  @override
  String get noSearchCommunityResults =>
      'Mingtai did not find a matching book page or discussion.';

  @override
  String get books => 'Books';

  @override
  String get sharedQuestion => 'asked a question';

  @override
  String get sharedFragmentThought => 'left a thought beside a passage';

  @override
  String get sharedReadingStatus => 'shared a reading reflection';

  @override
  String get sharedCurrentReading => 'shared what they are reading';

  @override
  String get sharedExcerpt => 'shared an excerpt';

  @override
  String get sharedReview => 'left a short review';

  @override
  String get sharedReadingThought => 'shared a reading thought';

  @override
  String get autosaving => 'Saving quietly…';

  @override
  String get dailyQuestionOne =>
      'Which sentence changed the way you understood this book?';

  @override
  String get dailyQuestionTwo => 'Where did you pause in this book?';

  @override
  String get dailyQuestionThree =>
      'What would you most like to ask another reader at this point?';

  @override
  String get dailyQuestionFour =>
      'If you carried one question out of this book, what would it be?';

  @override
  String translatorLabel(Object name) {
    return 'Translated by $name';
  }

  @override
  String bookCommunitySummary(Object posts, Object readers) {
    return '$posts public notes · $readers currently reading';
  }

  @override
  String get deleteThisContent => 'Delete Post';

  @override
  String get reportThisContent => 'Report Post';

  @override
  String responseCount(Object count) {
    return '$count responses';
  }

  @override
  String quotedText(Object text) {
    return 'Quoted: “$text”';
  }

  @override
  String get readingStatusHint => 'Where are you now, and why did you pause?';

  @override
  String get excerptThoughtHint => 'Why was this passage worth keeping?';

  @override
  String get reviewHint => 'What stayed with you after reading this book?';

  @override
  String get questionHint =>
      'What would you like to discuss with readers of this book?';

  @override
  String get yourThought => 'Your thought';

  @override
  String notificationFollow(Object name) {
    return '$name followed your reading profile';
  }

  @override
  String notificationComment(Object name) {
    return '$name responded to your reading thought';
  }

  @override
  String notificationQuote(Object name) {
    return '$name quoted your reading thought';
  }

  @override
  String notificationResonance(Object name) {
    return '$name resonated with your thought';
  }

  @override
  String notificationDefault(Object name) {
    return '$name left a response on Mingtai';
  }
}
