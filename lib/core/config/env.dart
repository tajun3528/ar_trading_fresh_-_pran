/// InsForge backend connection details.
///
/// The anon key is safe to ship in the client — it identifies the project,
/// not a user. Row Level Security on the backend is what actually restricts
/// what each request is allowed to see or change.
class Env {
  Env._();

  static const String insforgeBaseUrl = 'https://geb7edv6.ap-southeast.insforge.app';
  static const String insforgeAnonKey =
      'anon_325d65e7ecdfd782312bd9ffe51f6a25c46b523cb8b92ebc406ea48b853565e5';
}
