import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_service.dart';

enum AppleAuthStatus { success, cancelled, unavailable }

class AppleAuthResult {
  final AppleAuthStatus status;

  const AppleAuthResult(this.status);
}

class AppleCredentialPayload {
  final String authorizationCode;
  final String identityToken;
  final String? state;
  final String? givenName;
  final String? familyName;

  const AppleCredentialPayload({
    required this.authorizationCode,
    required this.identityToken,
    required this.state,
    this.givenName,
    this.familyName,
  });
}

typedef AppleCredentialRequest =
    Future<AppleCredentialPayload?> Function({
      required String nonce,
      required String state,
    });
typedef AppleAuthPreparation = Future<Map<String, dynamic>> Function();
typedef AppleAuthCompletion =
    Future<void> Function({
      required bool bind,
      required Map<String, dynamic> credential,
    });

class AppleAuthService {
  static Future<bool> isAvailable() => SignInWithApple.isAvailable();

  static Future<AppleAuthResult> authorize({
    required bool bind,
    Future<bool> Function()? availabilityCheck,
    AppleAuthPreparation? preparationLoader,
    AppleCredentialRequest? credentialRequest,
    AppleAuthCompletion? completion,
  }) async {
    final checkAvailability = availabilityCheck ?? isAvailable;
    if (!await checkAvailability()) {
      return const AppleAuthResult(AppleAuthStatus.unavailable);
    }
    final preparation =
        await (preparationLoader ?? AuthService.prepareAppleAuth)();
    final expectedState = preparation['state']?.toString() ?? '';
    if (expectedState.isEmpty) throw Exception('Apple 登录准备失败');

    final rawNonce = generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final requestCredential = credentialRequest ?? _requestCredential;
    final credential = await requestCredential(
      nonce: hashedNonce,
      state: expectedState,
    );
    if (credential == null) {
      return const AppleAuthResult(AppleAuthStatus.cancelled);
    }
    if (credential.state != expectedState) {
      throw Exception('Apple 登录 state 校验失败');
    }
    if (credential.identityToken.isEmpty) {
      throw Exception('Apple 未返回身份凭证');
    }
    final complete = completion ?? _complete;
    await complete(
      bind: bind,
      credential: {
        'authorizationCode': credential.authorizationCode,
        'identityToken': credential.identityToken,
        'rawNonce': rawNonce,
        'state': expectedState,
        'fullName': {
          'givenName': credential.givenName,
          'familyName': credential.familyName,
        },
      },
    );
    return const AppleAuthResult(AppleAuthStatus.success);
  }

  static Future<AppleCredentialPayload?> _requestCredential({
    required String nonce,
    required String state,
  }) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
        state: state,
      );
      return AppleCredentialPayload(
        authorizationCode: credential.authorizationCode,
        identityToken: credential.identityToken ?? '',
        state: credential.state,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  static Future<void> _complete({
    required bool bind,
    required Map<String, dynamic> credential,
  }) async {
    await AuthService.completeAppleAuth(bind: bind, credential: credential);
  }
}
