import 'dart:async';
import 'dart:io'; // Required for File handling
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart'; // Required for Import/Export

import 'vault_models.dart';
import 'crypto_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZeroVaultApp());
}

class ZeroVaultApp extends StatelessWidget {
  const ZeroVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZeroVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const VaultGateScreen(),
    );
  }
}

class VaultGateScreen extends StatefulWidget {
  const VaultGateScreen({super.key});

  @override
  State<VaultGateScreen> createState() => _VaultGateScreenState();
}

class _VaultGateScreenState extends State<VaultGateScreen>
    with WidgetsBindingObserver {
  final CryptoService _crypto = CryptoService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = true;
  bool _vaultExists = false;
  bool _biometricsEnabled = false;
  String? _errorMessage;

  VaultDatabase? _UnlockedDb;
  String? _activeMasterPassword;
  String _searchQuery = '';
  Timer? _clipboardTimer;

  @override
  void initState() {
    super.initState();
    // Register the lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    _checkInitialState();
  }

  @override
  void dispose() {
    // Clean up observer and timers to prevent memory leaks
    WidgetsBinding.instance.removeObserver(this);
    _clipboardTimer?.cancel();
    super.dispose();
  }

  // --- NEW: AUTO-LOCK LIFECYCLE METHOD ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the app is minimized, hidden, or the screen turns off, lock it instantly.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_UnlockedDb != null) {
        _lockVault();
      }
    }
  }

  // --- NEW: SECURE PASSWORD GENERATOR ---
  String _generateSecurePassword({int length = 16}) {
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890!@#\$%^&*()-_=+';
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  Future<void> _checkInitialState() async {
    final exists = await _crypto.doesVaultExist();
    final savedBioSecret = await _secureStorage.read(key: 'bio_master_pw');
    setState(() {
      _vaultExists = exists;
      _biometricsEnabled = savedBioSecret != null;
      _isLoading = false;
    });
  }

  Future<void> _createOrUnlockVault({String? overridePassword}) async {
    final password = overridePassword ?? _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Master password cannot be empty.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!_vaultExists) {
        // First time setup: create a starter "Banking" folder
        final initialDb = VaultDatabase(
          folders: [
            VaultFolder(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: 'Banking (Sample)',
              items: [
                VaultItem(
                  id: '1',
                  title: 'Primary Credit Card PIN',
                  username: 'Card ending 4321',
                  secret: '9081',
                  notes: 'Do not share',
                ),
                VaultItem(
                  id: '2',
                  title: 'UPI MPIN',
                  username: 'user@okaxis',
                  secret: '445566',
                  notes: 'PhonePe / GPay',
                ),
              ],
            ),
          ],
        );
        await _crypto.encryptAndSaveVault(initialDb.toJsonString(), password);
        _UnlockedDb = initialDb;
        _vaultExists = true;
      } else {
        // Decrypt existing vault
        final decryptedJson = await _crypto.loadAndDecryptVault(password);
        _UnlockedDb = VaultDatabase.fromJsonString(decryptedJson);
      }

      _activeMasterPassword = password;
      _passwordController.clear();
    } catch (e) {
      _errorMessage =
          'Decryption failed: Invalid Master Password or tampered file.';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unlockWithBiometrics() async {
    try {
      final canCheck =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canCheck) {
        setState(
          () => _errorMessage =
              'Biometrics / Windows Hello not available on this device.',
        );
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock your ZeroVault',
      );

      if (authenticated) {
        final storedPw = await _secureStorage.read(key: 'bio_master_pw');
        if (storedPw != null) {
          await _createOrUnlockVault(overridePassword: storedPw);
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Biometric authentication failed.');
    }
  }

  Future<void> _toggleBiometrics() async {
    if (_biometricsEnabled) {
      await _secureStorage.delete(key: 'bio_master_pw');
      setState(() => _biometricsEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric unlock disabled.')),
        );
      }
    } else if (_activeMasterPassword != null) {
      await _secureStorage.write(
        key: 'bio_master_pw',
        value: _activeMasterPassword,
      );
      setState(() => _biometricsEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric unlock enabled via OS Keystore!'),
          ),
        );
      }
    }
  }

  Future<void> _saveCurrentVault() async {
    if (_UnlockedDb == null || _activeMasterPassword == null) return;
    await _crypto.encryptAndSaveVault(
      _UnlockedDb!.toJsonString(),
      _activeMasterPassword!,
    );
  }

  void _lockVault() {
    setState(() {
      if (_UnlockedDb != null) {
        for (final folder in _UnlockedDb!.folders) {
          for (final item in folder.items) {
            item.secret = '';
            item.notes = '';
          }
          folder.items.clear();
        }
        _UnlockedDb!.folders.clear();
      }
      _UnlockedDb = null;
      _activeMasterPassword = null;
      _searchQuery = '';
      _passwordController.clear();
    });
  }

  void _copySecretWithAutoScrub(String secret, String label) {
    Clipboard.setData(ClipboardData(text: secret));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied! Clipboard will auto-clear in 15 seconds.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(const Duration(seconds: 15), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Running Argon2id (64MB Memory-Hard Key Derivation)...'),
            ],
          ),
        ),
      );
    }

    if (_UnlockedDb == null) {
      return _buildLockScreen();
    }

    return _buildUnlockedVaultScreen();
  }

  Widget _buildLockScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Import Vault Backup',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _importVault,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 56,
                    color: Colors.tealAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _vaultExists ? 'Unlock ZeroVault' : 'Create Master Vault',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _vaultExists
                        ? 'Enter your Master Password to decrypt your local file.'
                        : 'Set a strong Master Password. It is never stored anywhere.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: (_) => _createOrUnlockVault(),
                    decoration: const InputDecoration(
                      labelText: 'Master Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: Icon(
                        _vaultExists
                            ? Icons.lock_open
                            : Icons.enhanced_encryption,
                      ),
                      label: Text(
                        _vaultExists
                            ? 'Decrypt Vault'
                            : 'Initialize Encrypted Vault',
                      ),
                      onPressed: () => _createOrUnlockVault(),
                    ),
                  ),
                  if (_vaultExists && _biometricsEnabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Unlock with Biometrics'),
                        onPressed: _unlockWithBiometrics,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockedVaultScreen() {
    final query = _searchQuery.toLowerCase().trim();
    final filteredFolders = _UnlockedDb!.folders.where((folder) {
      if (query.isEmpty) return true;
      if (folder.name.toLowerCase().contains(query)) return true;
      return folder.items.any(
        (item) =>
            item.title.toLowerCase().contains(query) ||
            item.username.toLowerCase().contains(query),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZeroVault'),
        actions: [
          IconButton(
            tooltip: _biometricsEnabled
                ? 'Disable Biometrics'
                : 'Enable Biometrics',
            icon: Icon(
              Icons.fingerprint,
              color: _biometricsEnabled ? Colors.tealAccent : null,
            ),
            onPressed: _toggleBiometrics,
          ),
          IconButton(
            tooltip: 'Create New Folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _showAddFolderDialog,
          ),
          IconButton(
            tooltip: 'Lock Vault & Scrub RAM',
            icon: const Icon(Icons.lock_outline),
            onPressed: _lockVault,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') _exportVault();
              if (value == 'import') _importVault();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Export Backup (.bin)'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import & Overwrite Vault'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search folders, apps, UPI, cards...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredFolders.isEmpty
                ? const Center(
                    child: Text('No matching folders or passwords found.'),
                  )
                : ListView.builder(
                    itemCount: filteredFolders.length,
                    itemBuilder: (context, index) {
                      final folder = filteredFolders[index];
                      final itemsToShow = query.isEmpty
                          ? folder.items
                          : folder.items.where((item) {
                              return folder.name.toLowerCase().contains(
                                    query,
                                  ) ||
                                  item.title.toLowerCase().contains(query) ||
                                  item.username.toLowerCase().contains(query);
                            }).toList();

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: query.isNotEmpty || index == 0,
                          leading: const Icon(
                            Icons.folder_special,
                            color: Colors.tealAccent,
                          ),
                          title: Text(
                            folder.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('${itemsToShow.length} item(s)'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Add Password / PIN to Folder',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => _showAddItemDialog(folder),
                              ),
                              IconButton(
                                tooltip: 'Delete Folder',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () async {
                                  setState(
                                    () => _UnlockedDb!.folders.remove(folder),
                                  );
                                  await _saveCurrentVault();
                                },
                              ),
                            ],
                          ),
                          children: itemsToShow.map((item) {
                            return ListTile(
                              leading: const Icon(Icons.vpn_key_outlined),
                              title: Text(item.title),
                              subtitle: Text(
                                item.username.isEmpty
                                    ? 'No username/ID'
                                    : item.username,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Copy Secret (15s auto-clear)',
                                    icon: const Icon(Icons.copy),
                                    onPressed: () => _copySecretWithAutoScrub(
                                      item.secret,
                                      item.title,
                                    ),
                                  ),
                                  IconButton(
                                    // <--- NEW EDIT BUTTON
                                    tooltip: 'Edit Item',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () =>
                                        _showEditItemDialog(folder, item),
                                  ),
                                  IconButton(
                                    tooltip: 'View Details',
                                    icon: const Icon(Icons.visibility_outlined),
                                    onPressed: () =>
                                        _showItemDetailsDialog(folder, item),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFolderDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name (e.g., Banking, Social, Work)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _UnlockedDb!.folders.add(
                    VaultFolder(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim(),
                      items: [],
                    ),
                  );
                });
                await _saveCurrentVault();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog(VaultFolder folder) async {
    final titleCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to ${folder.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title (e.g., Credit Card PIN, UPI MPIN)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account / Username / Card Number',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: secretCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password / PIN / MPIN',
                  // NEW: Generator Button
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.casino_outlined,
                      color: Colors.tealAccent,
                    ),
                    tooltip: 'Generate Strong Password',
                    onPressed: () {
                      // Generate and fill the text field
                      secretCtrl.text = _generateSecurePassword();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isNotEmpty &&
                  secretCtrl.text.isNotEmpty) {
                setState(() {
                  folder.items.add(
                    VaultItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleCtrl.text.trim(),
                      username: userCtrl.text.trim(),
                      secret: secretCtrl.text,
                      notes: notesCtrl.text.trim(),
                    ),
                  );
                });
                await _saveCurrentVault();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Encrypt & Save'),
          ),
        ],
      ),
    );
  }

  void _showItemDetailsDialog(VaultFolder folder, VaultItem item) {
    bool reveal = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(item.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Folder: ${folder.name}'),
              const SizedBox(height: 8),
              Text(
                'Username/ID: ${item.username.isEmpty ? "N/A" : item.username}',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Secret: ${reveal ? item.secret : "••••••••"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      reveal ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setDialogState(() => reveal = !reveal),
                  ),
                ],
              ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Notes: ${item.notes}'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                setState(() => folder.items.remove(item));
                await _saveCurrentVault();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportVault() async {
    try {
      // 1. Get the current encrypted vault file
      final vaultFile = await _crypto.getVaultFile();
      if (!await vaultFile.exists()) {
        throw Exception('No vault file exists to export.');
      }

      // 2. Read the raw encrypted bytes from memory
      final vaultBytes = await vaultFile.readAsBytes();

      // 3. Pass the 'bytes' directly to the file picker!
      // The OS will securely write these bytes to wherever the user chooses.
      final Uri? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Export Encrypted Vault',
        fileName: 'zerovault_backup.bin',
        bytes: vaultBytes,
      );

      if (outputFile != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vault exported successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importVault() async {
    try {
      // v13 update: pickFile is used for single files, FilePickerResult is gone
      final PlatformFile? result = await FilePicker.pickFile(
        dialogTitle: 'Select Encrypted Vault File',
      );

      if (result != null && result.path != null) {
        await _crypto.importVault(result.path!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Vault imported! Please enter your Master Password to unlock it.',
              ),
            ),
          );
        }

        // Lock the vault so the user is forced to decrypt the newly imported file
        _lockVault();
        _checkInitialState(); // Refresh UI to show the decrypt screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _showEditItemDialog(VaultFolder folder, VaultItem item) async {
    // Pre-fill the controllers with the existing data
    final titleCtrl = TextEditingController(text: item.title);
    final userCtrl = TextEditingController(text: item.username);
    final secretCtrl = TextEditingController(text: item.secret);
    final notesCtrl = TextEditingController(text: item.notes);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${item.title}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account / Username',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: secretCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password / PIN / MPIN',
                  // NEW: Generator Button
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.casino_outlined,
                      color: Colors.tealAccent,
                    ),
                    tooltip: 'Generate Strong Password',
                    onPressed: () {
                      // Generate and fill the text field
                      secretCtrl.text = _generateSecurePassword();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isNotEmpty &&
                  secretCtrl.text.isNotEmpty) {
                setState(() {
                  // Update the existing item directly
                  item.title = titleCtrl.text.trim();
                  item.username = userCtrl.text.trim();
                  item.secret = secretCtrl.text;
                  item.notes = notesCtrl.text.trim();
                });
                await _saveCurrentVault(); // Encrypt and save to disk
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
