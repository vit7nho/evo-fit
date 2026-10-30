/// Situação do backend informada por `GET /api/v1/health`.
class HealthStatus {
  const HealthStatus({
    required this.databaseOk,
    required this.version,
    required this.environment,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
    databaseOk: json['database'] == 'ok',
    version: json['version'] as String? ?? '?',
    environment: json['environment'] as String? ?? '?',
  );

  /// A API respondeu; se o banco falhar ela responde 503 com `database: unavailable`.
  final bool databaseOk;
  final String version;
  final String environment;
}
