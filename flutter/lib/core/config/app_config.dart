class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const googleOAuthWebClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_WEB_CLIENT_ID',
  );
}
