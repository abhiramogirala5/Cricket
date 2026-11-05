/// Checks for the sign-in and sign-up forms. They mirror the server's rules
/// (docs/API_CONTRACT.md §3.2) so that mistakes are caught before a request is made.
abstract final class AuthRules {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int maxEmailLength = 255;
  static const int maxNameLength = 100;
  static const int minPhoneLength = 5;
  static const int maxPhoneLength = 25;
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final RegExp _phonePattern = RegExp(r'^[0-9+\-() ]+$');

String? validateEmail(String? value) {
  final String email = (value ?? '').trim();
  if (email.isEmpty) {
    return 'Enter your email address.';
  }
  if (email.length > AuthRules.maxEmailLength || !_emailPattern.hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

/// For signing in: any non-empty password (the server decides whether it is right).
String? validateLoginPassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter your password.';
  }
  return null;
}

/// For choosing a password.
String? validateNewPassword(String? value) {
  final String password = value ?? '';
  if (password.isEmpty) {
    return 'Choose a password.';
  }
  if (password.length < AuthRules.minPasswordLength) {
    return 'Use at least ${AuthRules.minPasswordLength} characters.';
  }
  if (password.length > AuthRules.maxPasswordLength) {
    return 'Use at most ${AuthRules.maxPasswordLength} characters.';
  }
  return null;
}

String? validateDisplayName(String? value) {
  final String name = (value ?? '').trim();
  if (name.isEmpty) {
    return 'Enter your name.';
  }
  if (name.length > AuthRules.maxNameLength) {
    return 'The name is too long.';
  }
  return null;
}

/// The phone number is optional.
String? validateOptionalPhone(String? value) {
  final String phone = (value ?? '').trim();
  if (phone.isEmpty) {
    return null;
  }
  if (phone.length < AuthRules.minPhoneLength ||
      phone.length > AuthRules.maxPhoneLength ||
      !_phonePattern.hasMatch(phone)) {
    return 'Use 5 to 25 digits, spaces, + - ( ).';
  }
  return null;
}
