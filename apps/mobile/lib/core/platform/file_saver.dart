import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Salva um texto num arquivo escolhido pela pessoa ("Salvar como" do Android, ADR-063).
abstract interface class FileSaver {
  /// Verdadeiro se salvou; falso se a pessoa cancelou. Lança [FileSaveException] se
  /// não deu para gravar.
  Future<bool> saveText({
    required String fileName,
    required String content,
    String mimeType,
  });
}

class FileSaveException implements Exception {
  const FileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// O canal com o código nativo (MainActivity.kt).
class PlatformFileSaver implements FileSaver {
  const PlatformFileSaver();

  static const _channel = MethodChannel('br.tcc.evofit/files');

  @override
  Future<bool> saveText({
    required String fileName,
    required String content,
    String mimeType = 'application/json',
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('saveText', {
        'fileName': fileName,
        'content': content,
        'mimeType': mimeType,
      });
      return saved ?? false;
    } on PlatformException catch (error) {
      throw FileSaveException(
        error.message ?? 'Não foi possível salvar o arquivo.',
      );
    } on MissingPluginException {
      throw const FileSaveException(
        'Salvar arquivos não está disponível neste aparelho.',
      );
    }
  }
}

final fileSaverProvider = Provider<FileSaver>(
  (ref) => const PlatformFileSaver(),
);
