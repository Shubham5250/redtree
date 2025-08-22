import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'lang/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
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
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

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
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi')
  ];

  /// No description provided for @activateRedTree.
  ///
  /// In en, this message translates to:
  /// **'Activate RedTree'**
  String get activateRedTree;

  /// No description provided for @redTreeDefaultSettings.
  ///
  /// In en, this message translates to:
  /// **'When not activated RedTree Default Settings'**
  String get redTreeDefaultSettings;

  /// No description provided for @rtBoxDelay.
  ///
  /// In en, this message translates to:
  /// **'RT box delay'**
  String get rtBoxDelay;

  /// No description provided for @timeBeforeOpeningRTbox.
  ///
  /// In en, this message translates to:
  /// **'Time before opening RTbox'**
  String get timeBeforeOpeningRTbox;

  /// No description provided for @fileNaming.
  ///
  /// In en, this message translates to:
  /// **'File Naming'**
  String get fileNaming;

  /// No description provided for @yourPresentPrefix.
  ///
  /// In en, this message translates to:
  /// **'Your present prefix naming'**
  String get yourPresentPrefix;

  /// No description provided for @folderPath.
  ///
  /// In en, this message translates to:
  /// **'Folder path'**
  String get folderPath;

  /// No description provided for @yourPresentDesignatedFolder.
  ///
  /// In en, this message translates to:
  /// **'Your present designated folder'**
  String get yourPresentDesignatedFolder;

  /// No description provided for @fileAspect.
  ///
  /// In en, this message translates to:
  /// **'File aspect'**
  String get fileAspect;

  /// No description provided for @yourPresentDesignatedFile.
  ///
  /// In en, this message translates to:
  /// **'Your Present Designated File'**
  String get yourPresentDesignatedFile;

  /// No description provided for @smallImage.
  ///
  /// In en, this message translates to:
  /// **'Small Image'**
  String get smallImage;

  /// No description provided for @formatPreferences.
  ///
  /// In en, this message translates to:
  /// **'Format Preferences'**
  String get formatPreferences;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @format24h.
  ///
  /// In en, this message translates to:
  /// **'24h'**
  String get format24h;

  /// No description provided for @formatAMPM.
  ///
  /// In en, this message translates to:
  /// **'am/pm'**
  String get formatAMPM;

  /// No description provided for @format_yyyy_mm_dd.
  ///
  /// In en, this message translates to:
  /// **'yyyy/mm/dd'**
  String get format_yyyy_mm_dd;

  /// No description provided for @format_yy_mm_dd.
  ///
  /// In en, this message translates to:
  /// **'yy/mm/dd'**
  String get format_yy_mm_dd;

  /// No description provided for @format_dd_mm_yy.
  ///
  /// In en, this message translates to:
  /// **'dd/mm/yy'**
  String get format_dd_mm_yy;

  /// No description provided for @format_dd_mm_yyyy.
  ///
  /// In en, this message translates to:
  /// **'dd/mm/yyyy'**
  String get format_dd_mm_yyyy;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get hindi;

  /// No description provided for @midImage.
  ///
  /// In en, this message translates to:
  /// **'Mid Image'**
  String get midImage;

  /// No description provided for @largeImage.
  ///
  /// In en, this message translates to:
  /// **'Large Image'**
  String get largeImage;

  /// No description provided for @setFileNamingPrefix.
  ///
  /// In en, this message translates to:
  /// **'Set File Naming Prefix'**
  String get setFileNamingPrefix;

  /// No description provided for @prefix.
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get prefix;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @folderIcon.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folderIcon;

  /// No description provided for @noteIcon.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteIcon;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @typeYourNoteHere.
  ///
  /// In en, this message translates to:
  /// **'Type your note here...'**
  String get typeYourNoteHere;

  /// No description provided for @annotate.
  ///
  /// In en, this message translates to:
  /// **'Annotate'**
  String get annotate;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get moveTo;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @suppress.
  ///
  /// In en, this message translates to:
  /// **'Suppress'**
  String get suppress;

  /// No description provided for @createNewFolder.
  ///
  /// In en, this message translates to:
  /// **'Create New Folder'**
  String get createNewFolder;

  /// No description provided for @enterFolderName.
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get enterFolderName;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @fileManager.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get fileManager;

  /// No description provided for @searchByNameOrNote.
  ///
  /// In en, this message translates to:
  /// **'Search by name or note...'**
  String get searchByNameOrNote;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SDe();
    case 'en':
      return SEn();
    case 'es':
      return SEs();
    case 'fr':
      return SFr();
    case 'hi':
      return SHi();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
