import 'package:ai_reader/services/apple_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelled authorization does not call backend completion', () async {
    var completed = false;
    final result = await AppleAuthService.authorize(
      bind: false,
      availabilityCheck: () async => true,
      preparationLoader: () async => {'state': 'state-1'},
      credentialRequest: ({required nonce, required state}) async => null,
      completion: ({required bind, required credential}) async {
        completed = true;
      },
    );

    expect(result.status, AppleAuthStatus.cancelled);
    expect(completed, isFalse);
  });

  test('successful authorization forwards raw nonce and credentials', () async {
    Map<String, dynamic>? sent;
    final result = await AppleAuthService.authorize(
      bind: false,
      availabilityCheck: () async => true,
      preparationLoader: () async => {'state': 'state-2'},
      credentialRequest: ({required nonce, required state}) async {
        expect(nonce, hasLength(64));
        expect(state, 'state-2');
        return const AppleCredentialPayload(
          authorizationCode: 'code',
          identityToken: 'identity-token',
          state: 'state-2',
          givenName: 'Read',
          familyName: 'U',
        );
      },
      completion: ({required bind, required credential}) async {
        expect(bind, isFalse);
        sent = credential;
      },
    );

    expect(result.status, AppleAuthStatus.success);
    expect(sent?['authorizationCode'], 'code');
    expect(sent?['identityToken'], 'identity-token');
    expect(sent?['rawNonce'], isNotEmpty);
    expect(sent?['state'], 'state-2');
    expect((sent?['fullName'] as Map?)?['givenName'], 'Read');
  });

  test('mismatched state is rejected before backend completion', () async {
    var completed = false;

    expect(
      () => AppleAuthService.authorize(
        bind: false,
        availabilityCheck: () async => true,
        preparationLoader: () async => {'state': 'expected'},
        credentialRequest: ({required nonce, required state}) async =>
            const AppleCredentialPayload(
              authorizationCode: 'code',
              identityToken: 'token',
              state: 'unexpected',
            ),
        completion: ({required bind, required credential}) async {
          completed = true;
        },
      ),
      throwsA(isA<Exception>()),
    );
    expect(completed, isFalse);
  });
}
