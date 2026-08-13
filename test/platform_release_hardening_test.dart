import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android release boundary', () {
    test('manifest minimizes privileges and blocks platform data export', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');

      for (final permission in const {
        'android.permission.INTERNET',
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
      }) {
        expect(
          _occurrences(manifest, 'android:name="$permission"'),
          1,
          reason: permission,
        );
      }
      for (final forbidden in const {
        'READ_CONTACTS',
        'READ_PHONE_STATE',
        'READ_MEDIA_IMAGES',
        'READ_MEDIA_VIDEO',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'MANAGE_EXTERNAL_STORAGE',
      }) {
        expect(manifest, isNot(contains(forbidden)), reason: forbidden);
      }

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(manifest, contains('android:localeConfig="@xml/locales_config"'));
      expect(manifest, isNot(contains('android:appCategory=')));
      expect(
        manifest,
        contains('android:roundIcon="@mipmap/ic_launcher_round"'),
      );

      for (final feature in const {
        'android.hardware.camera',
        'android.hardware.camera.any',
        'android.hardware.microphone',
      }) {
        expect(
          RegExp(
            'android:name="$feature"\\s+android:required="false"',
          ).hasMatch(manifest),
          isTrue,
          reason:
              '$feature must not filter camera-less or microphone-less devices',
        );
      }

      final exported = RegExp(
        r'<(?:activity|activity-alias|service|receiver|provider)\b[^>]*android:exported="true"',
      ).allMatches(manifest);
      expect(exported, hasLength(1));
      expect(exported.single.group(0), contains('activity'));
      expect(manifest, contains('android:taskAffinity=""'));
    });

    test('backup, trust-store, and locale resources are fail closed', () {
      final legacy = _read('android/app/src/main/res/xml/backup_rules.xml');
      final modern = _read(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );
      const domains = {
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      };
      for (final domain in domains) {
        expect(
          legacy,
          contains('<exclude domain="$domain" path="." />'),
          reason: 'legacy $domain',
        );
        expect(
          _occurrences(modern, '<exclude domain="$domain" path="." />'),
          2,
          reason: 'cloud backup and device transfer $domain',
        );
      }
      expect(modern, contains('<cloud-backup>'));
      expect(modern, contains('<device-transfer>'));

      final network = _read(
        'android/app/src/main/res/xml/network_security_config.xml',
      );
      expect(network, contains('cleartextTrafficPermitted="false"'));
      final baseConfig = RegExp(
        r'<base-config[^>]*>(.*?)</base-config>',
        dotAll: true,
      ).firstMatch(network)!.group(1)!;
      expect(baseConfig, contains('<certificates src="system" />'));
      expect(baseConfig, contains('<certificates src="@raw/isrg_root_x1" />'));
      expect(baseConfig, isNot(contains('<certificates src="user" />')));
      final debugOverrides = RegExp(
        r'<debug-overrides>(.*?)</debug-overrides>',
        dotAll: true,
      ).firstMatch(network)!.group(1)!;
      expect(debugOverrides, contains('<certificates src="user" />'));

      final legacyRootPath = 'android/app/src/main/res/raw/isrg_root_x1.pem';
      final legacyRoot = _read(legacyRootPath);
      expect(legacyRoot, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(legacyRoot.trim(), endsWith('-----END CERTIFICATE-----'));
      // Verify the bundled public root against ISRG's published identity.
      // OpenSSL ships on the macOS/Linux build hosts used for release QA.
      if (Platform.isLinux || Platform.isMacOS) {
        final certificate = Process.runSync('openssl', [
          'x509',
          '-in',
          legacyRootPath,
          '-noout',
          '-subject',
          '-issuer',
          '-dates',
          '-fingerprint',
          '-sha256',
        ]);
        expect(certificate.exitCode, 0, reason: '${certificate.stderr}');
        final identity = certificate.stdout.toString();
        expect(identity.replaceAll(' = ', '='), contains('CN=ISRG Root X1'));
        expect(
          _occurrences(identity, 'Internet Security Research Group'),
          2,
          reason: 'ISRG Root X1 must remain self-issued',
        );
        expect(identity, contains('notBefore=Jun  4 11:04:38 2015 GMT'));
        expect(identity, contains('notAfter=Jun  4 11:04:38 2035 GMT'));
        expect(
          identity.replaceAll(':', ''),
          contains(
            'sha256 Fingerprint=96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6',
          ),
        );
      }

      final locales = _read('android/app/src/main/res/xml/locales_config.xml');
      expect(_localeNames(locales), {'uz', 'en', 'ru'});

      final adaptive = _read(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      final themed = _read(
        'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml',
      );
      final round = _read(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
      );
      final themedRound = _read(
        'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher_round.xml',
      );
      expect(adaptive, contains('<adaptive-icon'));
      expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
      expect(themed, contains('@drawable/ic_launcher_monochrome'));
      expect(round, contains('@mipmap/ic_launcher_foreground'));
      expect(themedRound, contains('@drawable/ic_launcher_monochrome'));
      for (final density in const {
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      }) {
        expect(
          File(
            'android/app/src/main/res/mipmap-$density/ic_launcher_round.png',
          ).existsSync(),
          isTrue,
          reason: 'legacy round launcher icon for $density',
        );
      }
      expect(
        File(
          'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
        ).existsSync(),
        isTrue,
      );
    });

    test('release build shrinks and refuses missing signing credentials', () {
      final gradle = _read('android/app/build.gradle.kts');
      final release = RegExp(
        r'buildTypes\s*\{.*?release\s*\{(.*?)\n\s*\}\n\s*\}',
        dotAll: true,
      ).firstMatch(gradle)!.group(1)!;

      expect(gradle, contains('applicationId = "com.starforge.staff"'));
      expect(gradle, contains('namespace = "com.starforge.staff"'));
      expect(gradle, contains('compileSdk = 36'));
      expect(gradle, contains('targetSdk = 36'));
      expect(release, contains('isDebuggable = false'));
      expect(release, contains('isJniDebuggable = false'));
      expect(release, contains('isMinifyEnabled = true'));
      expect(release, contains('isShrinkResources = true'));
      expect(release, isNot(contains('signingConfigs.getByName("debug")')));
      expect(gradle, contains('val verifyReleaseSigning by tasks.registering'));
      expect(gradle, contains('dependsOn(verifyReleaseSigning)'));
      expect(gradle, contains('check(hasReleaseSigning)'));
      expect(
        gradle,
        contains('val storeFile = requireNotNull(releaseStoreFile)'),
      );
      expect(gradle, contains('check(storeFile.isFile)'));
      expect(gradle, contains('certificate.subjectX500Principal.name'));
      expect(gradle, contains('CN=Android Debug'));
      expect(gradle, contains('enableV1Signing = false'));
      expect(gradle, contains('enableV2Signing = true'));
      expect(gradle, contains('enableV3Signing = true'));
      expect(gradle, contains('enableV4Signing = true'));

      final ignore = _read('android/.gitignore');
      for (final secretPattern in const {
        'key.properties',
        '**/*.keystore',
        '**/*.jks',
        '**/*.p12',
        '**/*.pfx',
        '**/*.pem',
        '**/*.key',
      }) {
        expect(ignore, contains(secretPattern));
      }
      final iosIgnore = _read('ios/.gitignore');
      for (final secretPattern in const {
        '**/*.p12',
        '**/*.pfx',
        '**/*.p8',
        '**/*.pem',
        '**/*.key',
        '**/*.mobileprovision',
      }) {
        expect(iosIgnore, contains(secretPattern));
      }
      for (final root in const {'android', 'ios'}) {
        expect(
          Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (file) =>
                    RegExp(
                      r'\.(?:jks|keystore|p12|pfx|p8|mobileprovision|pem|key)$',
                      caseSensitive: false,
                    ).hasMatch(file.path) &&
                    file.path !=
                        'android/app/src/main/res/raw/isrg_root_x1.pem',
              ),
          isEmpty,
          reason: 'private signing material under $root',
        );
      }

      final wrapper = _read('android/gradle/wrapper/gradle-wrapper.properties');
      expect(
        wrapper,
        contains(
          'distributionUrl=https\\://services.gradle.org/distributions/gradle-9.1.0-all.zip',
        ),
      );
      expect(
        wrapper,
        contains(
          'distributionSha256Sum=b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85',
        ),
      );
      expect(ignore, isNot(contains('gradle-wrapper.jar')));
      expect(ignore, isNot(contains('/gradlew')));
      expect(ignore, contains('!app/src/main/res/raw/isrg_root_x1.pem'));
      expect(File('android/gradlew').existsSync(), isTrue);
      expect(
        File('android/gradle/wrapper/gradle-wrapper.jar').existsSync(),
        isTrue,
      );
      expect(
        _read('android/gradle.properties'),
        isNot(contains('HeapDumpOnOutOfMemoryError')),
      );
    });

    test('native activity protects recent-app snapshots', () {
      final activity = _read(
        'android/app/src/main/kotlin/com/starforge/starforge_staff/MainActivity.kt',
      );
      expect(activity, contains('private var protectsContent = false'));
      expect(activity, contains('override fun onPause()'));
      expect(activity, contains('override fun onResume()'));
      expect(
        activity,
        contains('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      expect(
        activity,
        contains('window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
      expect(activity, contains('private fun applyContentProtection()'));
    });
  });

  group('iOS release boundary', () {
    test(
      'transport, file export, permissions, and encryption are explicit',
      () {
        final info = _read('ios/Runner/Info.plist');
        for (final key in const {
          'NSCameraUsageDescription',
          'NSMicrophoneUsageDescription',
          'NSPhotoLibraryUsageDescription',
        }) {
          expect(_occurrences(info, '<key>$key</key>'), 1, reason: key);
        }
        expect(info, contains('<key>NSAppTransportSecurity</key>'));
        expect(
          RegExp(
            r'<key>NSAllowsArbitraryLoads</key>\s*<false/>',
          ).hasMatch(info),
          isTrue,
        );
        expect(
          RegExp(
            r'<key>NSAllowsArbitraryLoadsInWebContent</key>\s*<false/>',
          ).hasMatch(info),
          isTrue,
        );
        expect(
          RegExp(
            r'<key>NSAllowsLocalNetworking</key>\s*<false/>',
          ).hasMatch(info),
          isTrue,
        );
        expect(
          RegExp(r'<key>UIFileSharingEnabled</key>\s*<false/>').hasMatch(info),
          isTrue,
        );
        expect(
          RegExp(
            r'<key>LSSupportsOpeningDocumentsInPlace</key>\s*<false/>',
          ).hasMatch(info),
          isTrue,
        );
        expect(
          RegExp(
            r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>',
          ).hasMatch(info),
          isTrue,
        );
        expect(
          info,
          isNot(contains('NSAllowsArbitraryLoads</key>\n\t<true/>')),
        );
      },
    );

    test('privacy manifest describes app data use without tracking', () {
      final privacy = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(
        RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(privacy),
        isTrue,
      );
      expect(
        RegExp(
          r'<key>NSPrivacyTrackingDomains</key>\s*<array/>',
        ).hasMatch(privacy),
        isTrue,
      );
      expect(
        RegExp(
          r'<key>NSPrivacyAccessedAPIType</key>\s*<string>NSPrivacyAccessedAPICategoryUserDefaults</string>',
        ).hasMatch(privacy),
        isTrue,
      );
      expect(
        RegExp(
          r'<key>NSPrivacyAccessedAPITypeReasons</key>\s*<array>\s*<string>CA92\.1</string>\s*</array>',
        ).hasMatch(privacy),
        isTrue,
      );
      const declaredTypes = {
        'NSPrivacyCollectedDataTypeName',
        'NSPrivacyCollectedDataTypeEmailAddress',
        'NSPrivacyCollectedDataTypePhoneNumber',
        'NSPrivacyCollectedDataTypeUserID',
        'NSPrivacyCollectedDataTypeDeviceID',
        'NSPrivacyCollectedDataTypeEmailsOrTextMessages',
        'NSPrivacyCollectedDataTypePhotosorVideos',
        'NSPrivacyCollectedDataTypeAudioData',
        'NSPrivacyCollectedDataTypeOtherUserContent',
        'NSPrivacyCollectedDataTypeOtherFinancialInfo',
      };
      for (final type in declaredTypes) {
        expect(
          _occurrences(privacy, '<string>$type</string>'),
          1,
          reason: type,
        );
      }
      final records = RegExp(
        r'<dict>\s*<key>NSPrivacyCollectedDataType</key>(.*?)</dict>',
        dotAll: true,
      ).allMatches(privacy);
      expect(records, hasLength(declaredTypes.length));
      for (final record in records) {
        final source = record.group(0)!;
        expect(source, contains('<key>NSPrivacyCollectedDataTypeLinked</key>'));
        expect(
          source,
          contains('<key>NSPrivacyCollectedDataTypeTracking</key>'),
        );
        expect(source, contains('<false/>'));
        expect(
          source,
          contains(
            '<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>',
          ),
        );
      }
    });

    test('complete file protection and privacy manifest ship in every build', () {
      final entitlements = _read('ios/Runner/Runner.entitlements');
      expect(
        RegExp(
          r'<key>com\.apple\.developer\.default-data-protection</key>\s*<string>NSFileProtectionComplete</string>',
        ).hasMatch(entitlements),
        isTrue,
      );

      final project = _read('ios/Runner.xcodeproj/project.pbxproj');
      expect(
        _occurrences(
          project,
          'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
        ),
        3,
      );
      expect(_occurrences(project, 'PrivacyInfo.xcprivacy in Resources'), 2);
      expect(
        project,
        contains('PrivacyInfo.xcprivacy */ = {isa = PBXFileReference'),
      );
      expect(project, contains('CODE_SIGN_STYLE = Automatic;'));
      expect(project, isNot(contains('DEVELOPMENT_TEAM =')));
      expect(project, isNot(contains('PROVISIONING_PROFILE_SPECIFIER =')));
      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.starforge.staff;'),
      );
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;'));
    });

    test(
      'snapshot overlay uses selected in-app language before OS language',
      () {
        final appDelegate = _read('ios/Runner/AppDelegate.swift');
        final sceneDelegate = _read('ios/Runner/SceneDelegate.swift');

        expect(appDelegate, contains('func protectApplicationSnapshot()'));
        expect(appDelegate, contains('func refreshContentProtection()'));
        expect(appDelegate, contains('showPrivacyOverlay()'));
        expect(
          appDelegate,
          contains('UserDefaults.standard.string(forKey: "flutter.locale")'),
        );
        expect(appDelegate, contains('arguments?["language"] as? String'));
        expect(appDelegate, contains('protectedContentLanguage'));
        expect(appDelegate, contains('["uz", "ru", "en"].contains(language)'));
        for (final message in const {
          'Your workspace is protected',
          'Ваше рабочее пространство защищено',
          'Ish joyingiz himoyalangan',
        }) {
          expect(appDelegate, contains(message));
        }
        expect(sceneDelegate, contains('override func sceneWillResignActive'));
        expect(sceneDelegate, contains('protectApplicationSnapshot()'));
        expect(sceneDelegate, contains('override func sceneDidBecomeActive'));
        expect(sceneDelegate, contains('refreshContentProtection()'));
      },
    );
  });
}

String _read(String path) => File(path).readAsStringSync();

int _occurrences(String source, String value) =>
    value.allMatches(source).length;

Set<String> _localeNames(String source) => RegExp(
  r'<locale android:name="([^"]+)"\s*/>',
).allMatches(source).map((match) => match.group(1)!).toSet();
