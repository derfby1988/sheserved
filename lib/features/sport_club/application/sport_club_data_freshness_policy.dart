class SportClubDataFreshnessPolicy {
  const SportClubDataFreshnessPolicy({
    this.maxAge = const Duration(seconds: 60),
  });

  final Duration maxAge;

  bool shouldRefresh(DateTime? lastSuccessfulAt, {required DateTime now}) {
    if (lastSuccessfulAt == null) return true;
    return now.difference(lastSuccessfulAt) >= maxAge;
  }
}
