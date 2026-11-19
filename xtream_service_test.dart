/// Fixed, app-wide configuration for the FreeF1 Cockpit client.
///
/// The username and password are provided at build time with Dart defines so
/// they are not stored in a public source repository. They are still embedded
/// in the compiled app and may be recovered by anyone who receives it.
abstract final class AppConfig {
  static const portalServer = 'http://lordstreams.live:80';
  static const portalUsername = String.fromEnvironment('PORTAL_USERNAME');
  static const portalPassword = String.fromEnvironment('PORTAL_PASSWORD');
  static const categoryName = 'LIVE | FORMULA 1 F1';
  static const season = 2026;
  static const website = 'https://freef1-live.vercel.app';
}
