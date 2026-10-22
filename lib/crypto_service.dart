import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

class CryptoService {
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int macLength = 16;

  // Argon2id configuration (64MB RAM, 3 iterations, 4 lanes)
  final Argon2id _kdf = Argon2id(
    memory: 65536,
    iterations: 3,
    parallelism: 4,
    hashLength: 32,
  );

  final AesGcm _cipher = AesGcm.with256bits();

  /// Generates cryptographically secure random bytes
  Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rnd.nextInt(256)),
    );
  }

  /// Overwrites a byte array in memory with zeros
  void scrubBytes(List<int> bytes) {
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  /// Returns the local file path where the encrypted vault is stored
  Future<File> getVaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}zerovault_data.bin');
  }

  Future<bool> doesVaultExist() async {
    final file = await getVaultFile();
    return file.exists();
  }

  /// Encrypts the JSON string and writes the binary structure to disk
  Future<void> encryptAndSaveVault(
    String jsonPlaintext,
    String masterPassword,
  ) async {
    final salt = _randomBytes(saltLength);
    final nonce = _randomBytes(nonceLength);
    final plaintextBytes = utf8.encode(jsonPlaintext);

    // 1. Derive 256-bit key using Argon2id
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: masterPassword,
      nonce: salt,
    );

    // 2. Encrypt using AES-256-GCM
    final secretBox = await _cipher.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    // 3. Scrub plaintext bytes from memory immediately
    scrubBytes(plaintextBytes);

    // 4. Pack binary file: [Salt (16B)] + [Nonce (12B)] + [AuthTag (16B)] + [Ciphertext]
    final builder = BytesBuilder(copy: false)
      ..add(salt)
      ..add(nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

    final file = await getVaultFile();
    await file.writeAsBytes(builder.toBytes(), flush: true);
  }

  /// Reads the binary file, verifies the GCM Auth Tag, and decrypts the vault
  Future<String> loadAndDecryptVault(String masterPassword) async {
    final file = await getVaultFile();
    if (!await file.exists()) {
      throw Exception('Vault file does not exist.');
    }

    final fileBytes = await file.readAsBytes();
    if (fileBytes.length < (saltLength + nonceLength + macLength)) {
      throw Exception('Vault file is corrupted or truncated.');
    }

    // 1. Extract binary segments
    final salt = fileBytes.sublist(0, saltLength);
    final nonce = fileBytes.sublist(saltLength, saltLength + nonceLength);
    final macBytes = fileBytes.sublist(
      saltLength + nonceLength,
      saltLength + nonceLength + macLength,
    );
    final cipherText = fileBytes.sublist(saltLength + nonceLength + macLength);

    // 2. Re-derive the 256-bit key using Argon2id and the stored salt
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: masterPassword,
      nonce: salt,
    );

    // 3. Authenticate and decrypt with AES-256-GCM
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

    // Throws SecretBoxAuthenticationError if password is wrong or file was tampered with
    final decryptedBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    final jsonString = utf8.decode(decryptedBytes);
    scrubBytes(decryptedBytes);
    return jsonString;
  }

  /// Copies the encrypted vault to a user-selected external directory
  Future<void> exportVault(String destinationPath) async {
  final file = await getVaultFile();
  if (await file.exists()) {
    await file.copy(destinationPath);
  } else {
    throw Exception('No vault file exists to export.');
  }
  }

  /// Replaces the local vault with an external encrypted file
  Future<void> importVault(String sourcePath) async {
  final sourceFile = File(sourcePath);
  if (await sourceFile.exists()) {
    final destFile = await getVaultFile();
    await sourceFile.copy(destFile.path);
  } else {
    throw Exception('Selected file does not exist.');
  }
  }
}
