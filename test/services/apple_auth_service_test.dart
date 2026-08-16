import 'dart:convert';

import 'package:ai_reader/services/apple_auth_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns cancelled without completing a server login', () async {
    var completed = false;
    final result = await AppleAuthService.authorize(
      bind: false,
      availabilityCheck: () async => true,
      preparationLoader: () async => {'state': 'server-state'},
      credentialRequest: ({required nonce, required state}) async => null,
      completion: ({required bind, required credential}) async {
        completed = true;
      },
    );

    expect(result.status, AppleAuthStatus.cancelled);
    expect(completed, isFalse);
  });

  test('passes nonce, state, and only required Apple credentials', () async {
    String? platformNonce;
    Map<String, dynamic>? sent;
    final result = await AppleAuthService.authorize(
      bind: true,
      availabilityCheck: () async => true,
      preparationLoader: () async => {'state': 'server-state'},
      credentialRequest: ({required nonce, required state}) async {
        platformNonce = nonce;
        expect(state, 'server-state');
        return const AppleCredentialPayload(
          authorizationCode: 'authorization-code',
          identityToken: 'identity-token',
          state: 'server-state',
          givenName: 'You',
          familyName: 'Xugarden',
        );
      },
      completion: ({required bind, required credential}) async {
        expect(bind, isTrue);
        sent = credential;
      },
    );

    expect(result.status, AppleAuthStatus.success);
    expect(platformNonce, hasLength(64));
    expect(sent?['authorizationCode'], 'authorization-code');
    expect(sent?['identityToken'], 'identity-token');
    expect(sent?['state'], 'server-state');
    expect(sent?['email'], isNull);
    final rawNonce = sent?['rawNonce'] as String;
    expect(sha256.convert(utf8.encode(rawNonce)).toString(), platformNonce);
  });

  test('rejects a credential with a mismatched state', () async {
    await expectLater(
      AppleAuthService.authorize(
        bind: false,
        availabilityCheck: () async => true,
        preparationLoader: () async => {'state': 'server-state'},
        credentialRequest: ({required nonce, required state}) async =>
            const AppleCredentialPayload(
              authorizationCode: 'authorization-code',
              identityToken: 'identity-token',
              state: 'attacker-state',
            ),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
