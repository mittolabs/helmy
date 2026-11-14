/// Helmy's version, as release-please sets it on each release.
const helmyVersion = '0.12.0'; // x-release-please-version

/// The version this build says it is: set at build time, else the above.
const shownVersion = String.fromEnvironment('HELMY_VERSION', defaultValue: helmyVersion);
