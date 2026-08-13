/// Returns a release-provided privacy policy URL only when it is a normal,
/// credential-free HTTPS address.
Uri? privacyPolicyUriFrom(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Uri? get configuredPrivacyPolicyUri =>
    privacyPolicyUriFrom(const String.fromEnvironment('STARFORGE_PRIVACY_URL'));
