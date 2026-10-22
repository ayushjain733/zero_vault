# 🛡️ ZeroVault

**ZeroVault** is a local, offline-first, zero-knowledge password manager built with Flutter for Android and Windows. 

Designed for users who prioritize absolute control over their data, ZeroVault eliminates the risks associated with cloud-based supply chain attacks, server breaches, and cross-site scripting by keeping all cryptography and data strictly local.

---

## ✨ Features

*   **Zero-Knowledge Architecture:** Your master password is never stored anywhere. It is used strictly in-memory to derive your encryption key, then instantly scrubbed from RAM.
*   **Hardware-Backed Biometrics:** Seamlessly unlock your vault using Android Fingerprint or Windows Hello, integrated securely with the OS hardware Keystore/TPM.
*   **Encrypted Offline Backups:** Export and import your vault as a securely encrypted `.bin` file, completely safe to transfer via USB, email, or personal cloud storage.
*   **Hierarchical Folders:** Organize passwords, bank details, and secure notes into custom folders.
*   **Live In-Memory Search:** Search across all folders and credentials instantly while the vault is unlocked.
*   **Clipboard Auto-Scrub:** Copies credentials to your OS clipboard and automatically securely wipes them after 15 seconds to prevent background app snooping.

---

## 🔐 Security & Cryptography

ZeroVault follows Kerckhoffs's Principle: the system is secure even though the source code is public. The security relies entirely on the mathematical strength of the algorithms and your Master Password.

### 1. Key Derivation: Argon2id
To thwart GPU brute-force attacks, the Master Password is run through **Argon2id**, a memory-hard key derivation function.
*   **Memory Cost:** 64 MB
*   **Iterations:** 3
*   **Parallelism:** 4 lanes
*   **Output:** 256-bit (32-byte) Master Encryption Key

### 2. Authenticated Encryption: AES-256-GCM
The vault data (structured as JSON) is encrypted using **AES-256-GCM**. This provides both *confidentiality* (hiding the data) and *authenticity* (ensuring the data has not been maliciously altered).
*   Unique 12-byte Nonce generated for every save.
*   16-byte Authentication Tag validates file integrity before decryption.

### 3. Binary File Structure
The exported `zerovault_data.bin` file follows a strict, zero-metadata binary structure:
| Bytes | Size | Purpose | Secret? |
| :--- | :--- | :--- | :--- |
| `0-15` | 16 Bytes | Argon2id Salt (needed to regenerate the key) | No |
| `16-27` | 12 Bytes | AES-GCM Nonce | No |
| `28-43` | 16 Bytes | GCM Authentication Tag (MAC) | No |
| `44+` | Variable | The AES-256 Encrypted Vault Payload | **Yes** |

---

## 🚀 Getting Started

### Prerequisites
To compile ZeroVault from source, you will need:
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.0+)
*   **For Windows:** Visual Studio 2022 (with "Desktop development with C++" workload).
*   **For Android:** Android Studio (with Android SDK and Command-line Tools).

### Installation & Build

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YourUsername/zero_vault.git
   cd zero_vault
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on Windows (Desktop):**
   ```bash
   flutter run -d windows
   ```

4. **Run on Android (USB Debugging Enabled):**
   ```bash
   flutter run --release -d android
   ```

---

## 🛠️ Built With
*   [Flutter](https://flutter.dev/) - UI and App Framework
*   [cryptography](https://pub.dev/packages/cryptography) - Dart cryptographic library for Argon2id and AES-GCM
*   [local_auth](https://pub.dev/packages/local_auth) - Biometric hardware integration
*   [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) - Secure hardware keystore usage
*   [file_picker](https://pub.dev/packages/file_picker) - Native OS file handling for backups

---

## ⚠️ Disclaimer
This application was built as a personal security tool. While it uses audited cryptographic algorithms, modifying the cryptographic implementations (`crypto_service.dart`) without a deep understanding of memory management and cryptography can result in silent security vulnerabilities or permanent data loss. **Always keep a backup of your `.bin` file and never forget your Master Password.**