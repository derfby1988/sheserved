/// Result of a change-current-user-password attempt.
///
/// Used by [UserRepository.changeCurrentUserPassword] to let the UI display
/// the correct feedback without exposing internal error details.
enum PasswordChangeResult {
  success,
  unauthorized,
  currentPasswordIncorrect,
  invalidPassword,
  socialAccountNoPassword,
  tooManyAttempts,
  unsupportedOffline,
  failed,
}
