import 'dart:convert';

class VaultItem {
  String id;
  String title;       // e.g., "HDFC Credit Card", "UPI MPIN"
  String username;    // e.g., Account Number or User ID
  String secret;      // The PIN or Password
  String notes;       // Extra details (CVV, expiry, etc.)

  VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.secret,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'secret': secret,
        'notes': notes,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        secret: json['secret'] as String,
        notes: json['notes'] as String? ?? '',
      );
}

class VaultFolder {
  String id;
  String name; // e.g., "Banking", "Social Media", "Work"
  List<VaultItem> items;

  VaultFolder({
    required this.id,
    required this.name,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory VaultFolder.fromJson(Map<String, dynamic> json) => VaultFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        items: (json['items'] as List<dynamic>)
            .map((e) => VaultItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VaultDatabase {
  List<VaultFolder> folders;

  VaultDatabase({required this.folders});

  String toJsonString() => jsonEncode({
        'folders': folders.map((f) => f.toJson()).toList(),
      });

  factory VaultDatabase.fromJsonString(String jsonStr) {
    final Map<String, dynamic> data = jsonDecode(jsonStr);
    final foldersList = (data['folders'] as List<dynamic>)
        .map((f) => VaultFolder.fromJson(f as Map<String, dynamic>))
        .toList();
    return VaultDatabase(folders: foldersList);
  }
}