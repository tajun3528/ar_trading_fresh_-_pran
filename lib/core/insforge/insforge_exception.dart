/// Error surfaced by [InsforgeClient] for any failed request — REST error
/// bodies from InsForge, RPC exceptions raised by Postgres, or transport
/// failures. `message` is always plain-language and safe to show a user
/// directly (matches NFR-4's "clear error messages" requirement).
class InsforgeException implements Exception {
  InsforgeException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
