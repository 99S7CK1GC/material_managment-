import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

late Pool dbPool;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  String host = 'ep-divine-tree-b5uupalq-pooler.c-7.us-east-2.aws.neon.tech';
  String database = 'neondb';
  String username = 'neondb_owner';
  String password = 'npg_cNKL5vGwQ9st';
  int port = 5432;

  try {
    await dotenv.load(fileName: ".env");
    final dbUrl = dotenv.env['DATABASE_URL'];
    if (dbUrl != null && dbUrl.trim().isNotEmpty) {
      final uri = Uri.parse(dbUrl.trim());
      if (uri.host.isNotEmpty) host = uri.host;
      if (uri.pathSegments.isNotEmpty) database = uri.pathSegments.first;
      if (uri.userInfo.isNotEmpty) {
        final parts = uri.userInfo.split(':');
        username = parts[0];
        if (parts.length > 1) {
          password = Uri.decodeComponent(parts.sublist(1).join(':'));
        }
      }
      if (uri.hasPort && uri.port != 0) {
        port = uri.port;
      }
    } else {
      host = dotenv.env['DB_HOST'] ?? host;
      database = dotenv.env['DB_NAME'] ?? database;
      username = dotenv.env['DB_USER'] ?? username;
      password = dotenv.env['DB_PASSWORD'] ?? password;
      port = int.tryParse(dotenv.env['DB_PORT'] ?? '') ?? port;
    }
  } catch (e) {
    debugPrint('Could not load .env file, using default database config: $e');
  }

  dbPool = Pool.withEndpoints([
    Endpoint(
      host: host,
      database: database,
      username: username,
      password: password,
      port: port,
    )
  ], settings: const PoolSettings(maxConnectionCount: 5));

  // Initialize DB tables
  await dbPool.execute('CREATE TABLE IF NOT EXISTS categories (name TEXT PRIMARY KEY)');
  await dbPool.execute('''
    CREATE TABLE IF NOT EXISTS inventory (
      id TEXT PRIMARY KEY, name TEXT, quantity INT, category TEXT, date TEXT, image_data TEXT
    )
  ''');
  await dbPool.execute('''
    CREATE TABLE IF NOT EXISTS borrowers (
      id TEXT PRIMARY KEY, person_name TEXT, email TEXT, phone TEXT,
      inventory_id TEXT, item_taken TEXT, topic TEXT, quantity_taken INT, date TEXT
    )
  ''');
  
  // Migrations for older database tables
  await dbPool.execute('ALTER TABLE borrowers ADD COLUMN IF NOT EXISTS inventory_id TEXT');
  await dbPool.execute('ALTER TABLE inventory ADD COLUMN IF NOT EXISTS image_data TEXT');
  await dbPool.execute('ALTER TABLE inventory ADD COLUMN IF NOT EXISTS description TEXT');

  runApp(const WameedhApp());
}

class WameedhApp extends StatelessWidget {
  const WameedhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wameedh Material Organizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0f2027),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.amberAccent,
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

// --- Data Models ---
class MaterialItem {
  final String id;
  String name;
  int quantity;
  String category; 
  final String date;
  String? _imageData;
  String? description;
  Uint8List? _cachedBytes;

  MaterialItem(this.id, this.name, this.quantity, this.category, this.date, [String? imageData, this.description]) {
    this.imageData = imageData;
  }

  String? get imageData => _imageData;
  set imageData(String? val) {
    _imageData = val;
    if (val != null && val.isNotEmpty) {
      try {
        _cachedBytes = base64Decode(val);
      } catch (_) {
        _cachedBytes = null;
      }
    } else {
      _cachedBytes = null;
    }
  }

  Uint8List? get imageBytes => _cachedBytes;
}

class BorrowerLog {
  final String id;
  final String personName;
  final String email;
  final String phone;
  final String inventoryId;
  final String itemTaken;
  String topic;      
  int quantityTaken; 
  final String date;
  BorrowerLog(this.id, this.personName, this.email, this.phone, this.inventoryId, this.itemTaken, this.topic, this.quantityTaken, this.date);
}

// --- Main Application State ---
class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentViewIndex = 0; 

  final List<String> _categories = [];
  final List<MaterialItem> _inventory = [];
  final List<BorrowerLog> _borrowers = [];

  final TextEditingController _matNameController = TextEditingController();
  final TextEditingController _matQtyController = TextEditingController(text: "1");
  String? _selectedCategory;
  String _filterCategory = "All";

  final TextEditingController _personNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _borrowQtyController = TextEditingController(text: "1");
  final TextEditingController _matDescController = TextEditingController();
  final TextEditingController _searchNameController = TextEditingController();
  final TextEditingController _searchTopicController = TextEditingController();
  final TextEditingController _borrowTopicController = TextEditingController();
  final TextEditingController _borrowMaterialController = TextEditingController();
  final TextEditingController _borrowHistorySearchController = TextEditingController();
  String _searchName = "";
  String _searchTopic = "";
  String _borrowTopicFilter = "All";
  String _borrowHistorySearch = "";
  String? _selectedInventoryItemId;
  String? _selectedImageBase64;
  
  bool _isCardView = false;
  bool _isLoading = true;

  Future<String?> _pickAndProcessImage() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return null;

      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) return null;

      final codec = await instantiateImageCodec(bytes, targetWidth: 300);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return null;

      return base64Encode(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint("Error picking image: $e");
      return null;
    }
  }

  Future<void> _saveMaterialPhoto(MaterialItem item) async {
    if (item.imageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No photo available to save"), backgroundColor: Colors.orangeAccent),
        );
      }
      return;
    }
    try {
      final cleanName = item.name.replaceAll(RegExp(r'[^\w\s-]'), '_').replaceAll(' ', '_');
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save Material Photo',
        fileName: '$cleanName.png',
        bytes: item.imageBytes!,
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (uri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo saved successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error saving photo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving photo: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _changeMaterialPhoto(MaterialItem item, StateSetter setDialogState) async {
    final newBase64 = await _pickAndProcessImage();
    if (newBase64 == null) return;

    try {
      await dbPool.execute('UPDATE inventory SET image_data = \$1 WHERE id = \$2', parameters: [newBase64, item.id]);

      setState(() {
        final idx = _inventory.indexWhere((m) => m.id == item.id);
        if (idx != -1) {
          _inventory[idx].imageData = newBase64;
        }
        item.imageData = newBase64;
      });

      setDialogState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo updated successfully!"), backgroundColor: Colors.blueAccent),
        );
      }
    } catch (e) {
      debugPrint("Error updating photo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error updating photo: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showMaterialDetailsDialog(MaterialItem item) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int borrowedCount = _borrowers
                .where((b) => b.inventoryId == item.id || b.itemTaken.toLowerCase() == item.name.toLowerCase())
                .fold(0, (sum, b) => sum + b.quantityTaken);

            final bool hasImage = item.imageBytes != null;
            final bool hasDesc = item.description != null && item.description!.trim().isNotEmpty;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3545),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Photo Container with Options Menu
                          PopupMenuButton<String>(
                            tooltip: "Photo Options",
                            color: const Color(0xFF182A34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Colors.white24, width: 1),
                            ),
                            offset: const Offset(120, 20),
                            onSelected: (action) {
                              if (action == 'save') {
                                _saveMaterialPhoto(item);
                              } else if (action == 'change') {
                                _changeMaterialPhoto(item, setDialogState);
                              }
                            },
                            itemBuilder: (menuContext) => [
                              if (hasImage) ...[
                                const PopupMenuItem(
                                  value: 'save',
                                  child: Row(
                                    children: [
                                      Icon(Icons.file_download_outlined, color: Colors.tealAccent, size: 20),
                                      SizedBox(width: 10),
                                      Text("Save photo", style: TextStyle(color: Colors.white, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 1),
                              ],
                              PopupMenuItem(
                                value: 'change',
                                child: Row(
                                  children: [
                                    Icon(hasImage ? Icons.photo_library_outlined : Icons.add_photo_alternate_outlined, color: Colors.blueAccent, size: 20),
                                    const SizedBox(width: 10),
                                    Text(hasImage ? "Change photo" : "Upload photo", style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              height: 230,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFF152631),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // The Photo or Placeholder
                                  if (hasImage)
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          item.imageBytes!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 60, color: Colors.white38),
                                        ),
                                      ),
                                    )
                                  else
                                    const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inventory_2_outlined, size: 56, color: Colors.white24),
                                        SizedBox(height: 8),
                                        Text("No photo uploaded", style: TextStyle(color: Colors.white38, fontSize: 13)),
                                      ],
                                    ),
                                  // Bottom Pill Badge
                                  Positioned(
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
                                          const SizedBox(width: 6),
                                          Text(
                                            hasImage ? "Click the photo for options" : "Click to upload photo",
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 2. Material Name
                          Text(
                            item.name,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),

                          // 3. Topic / Category Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              item.category,
                              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 4. Three Stats Grid: In stock, Borrowed, Added
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("In stock", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${item.quantity}",
                                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Borrowed", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text(
                                        "$borrowedCount",
                                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Added", style: TextStyle(color: Colors.white54, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.date,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 5. Description Block
                          const Text(
                            "DESCRIPTION",
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasDesc ? item.description!.trim() : "No description provided.",
                            style: TextStyle(
                              color: hasDesc ? Colors.white70 : Colors.white38,
                              fontSize: 13,
                              height: 1.4,
                              fontStyle: hasDesc ? FontStyle.normal : FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 22),

                          // 6. Action Buttons: Edit and Delete
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _editInventoryItemDialog(item);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: const Text("Edit", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _confirmDeleteDialog(item);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF331E23),
                                    foregroundColor: const Color(0xFFF87171),
                                    side: BorderSide(color: const Color(0xFF7F2626).withValues(alpha: 0.6)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Close button at top-right
                    Positioned(
                      top: 14,
                      right: 14,
                      child: InkWell(
                        onTap: () => Navigator.pop(dialogContext),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: const Icon(Icons.close, size: 18, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showExportInventoryDialog(List<MaterialItem> currentFiltered) {
    bool exportAll = true;
    bool isExporting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final itemsToExport = exportAll ? _inventory : currentFiltered;
          final totalUnits = itemsToExport.fold<int>(0, (sum, m) => sum + m.quantity);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 480,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF162a35), Color(0xFF1f3844), Color(0xFF0d1e25)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4), width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.file_download_outlined, color: Colors.amberAccent, size: 26),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Export Inventory List",
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Download components table as Excel or PDF",
                                    style: TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 14),

                        if (currentFiltered.length != _inventory.length) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.filter_list, color: Colors.amberAccent, size: 18),
                                const SizedBox(width: 8),
                                const Text("Items to export:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                                const Spacer(),
                                DropdownButton<bool>(
                                  value: exportAll,
                                  dropdownColor: const Color(0xFF1f3844),
                                  underline: const SizedBox(),
                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  items: [
                                    DropdownMenuItem(value: true, child: Text("All (${_inventory.length} items)")),
                                    DropdownMenuItem(value: false, child: Text("Filtered (${currentFiltered.length} items)")),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setDialogState(() => exportAll = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Exporting ${itemsToExport.length} materials ($totalUnits units in stock)",
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        if (isExporting)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(color: Colors.amberAccent),
                                  SizedBox(height: 12),
                                  Text("Generating file, please wait...", style: TextStyle(color: Colors.white70, fontSize: 13)),
                                ],
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    setDialogState(() => isExporting = true);
                                    await _exportInventoryToCsv(itemsToExport);
                                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF107C41).withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF107C41).withValues(alpha: 0.7)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: const Color(0xFF107C41), borderRadius: BorderRadius.circular(8)),
                                          child: const Icon(Icons.table_chart, color: Colors.white, size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Download as Excel (.csv)",
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Opens directly in Microsoft Excel, Google Sheets, Calc",
                                                style: TextStyle(color: Colors.white60, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    setDialogState(() => isExporting = true);
                                    await _exportInventoryToPdf(itemsToExport);
                                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE11D48).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.7)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(8)),
                                          child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Download as PDF (.pdf)",
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Printable organized table report with totals & headers",
                                                style: TextStyle(color: Colors.white60, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: InkWell(
                      onTap: () => Navigator.pop(dialogCtx),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(Icons.close, size: 18, color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportInventoryToCsv(List<MaterialItem> items) async {
    try {
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final defaultFileName = "wameedh_inventory_$dateStr.csv";

      final buffer = StringBuffer();
      buffer.write('\uFEFF'); // UTF-8 BOM for Microsoft Excel
      buffer.writeln('"#","Material Name","Topic / Category","Quantity in Stock","Date Added","Description"');

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final num = i + 1;
        final name = item.name.replaceAll('"', '""');
        final cat = item.category.replaceAll('"', '""');
        final qty = item.quantity;
        final date = item.date.replaceAll('"', '""');
        final desc = (item.description ?? "").replaceAll('"', '""').replaceAll('\n', ' ');
        buffer.writeln('$num,"$name","$cat",$qty,"$date","$desc"');
      }

      final csvContent = buffer.toString();
      final bytes = Uint8List.fromList(utf8.encode(csvContent));

      if (Platform.isAndroid || Platform.isIOS) {
        final tempDir = await Directory.systemTemp.createTemp();
        final file = File("${tempDir.path}/$defaultFileName");
        await file.writeAsBytes(bytes);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: "Wameedh Inventory Export ($dateStr)",
            text: "Wameedh Electronics Inventory List ($dateStr)",
          ),
        );
      } else {
        final uri = await FilePicker.saveFile(
          dialogTitle: "Save Excel / CSV Inventory",
          fileName: defaultFileName,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );

        if (uri != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ Exported successfully to: $uri"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error exporting CSV: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _exportInventoryToPdf(List<MaterialItem> items) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      final totalStock = items.fold<int>(0, (sum, m) => sum + m.quantity);
      final totalCategories = items.map((m) => m.category).toSet().length;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 1.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "WAMEEDH",
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.Text(
                      "Electronics & Components Inventory Report",
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Generated on: $dateStr $timeStr", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    pw.Text("Total Items: ${items.length} | Total Stock: $totalStock units",
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                  ],
                ),
              ],
            ),
          ),
          footer: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Wameedh Inventory Management System", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (context) => [
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.blue200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Unique Materials", style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800)),
                        pw.SizedBox(height: 3),
                        pw.Text("${items.length}", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.green200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Total Units in Stock", style: const pw.TextStyle(fontSize: 9, color: PdfColors.green800)),
                        pw.SizedBox(height: 3),
                        pw.Text("$totalStock", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.amber200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Active Topics", style: const pw.TextStyle(fontSize: 9, color: PdfColors.amber800)),
                        pw.SizedBox(height: 3),
                        pw.Text("$totalCategories", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['#', 'Material Name', 'Topic', 'Qty', 'Date Added', 'Description'],
              data: List<List<dynamic>>.generate(items.length, (index) {
                final item = items[index];
                return [
                  (index + 1).toString(),
                  item.name,
                  item.category,
                  item.quantity.toString(),
                  item.date,
                  (item.description != null && item.description!.trim().isNotEmpty) ? item.description!.trim() : "-",
                ];
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              columnWidths: {
                0: const pw.FixedColumnWidth(24),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FixedColumnWidth(38),
                4: const pw.FixedColumnWidth(64),
                5: const pw.FlexColumnWidth(3),
              },
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final defaultFileName = "wameedh_inventory_$dateStr.pdf";

      if (Platform.isAndroid || Platform.isIOS) {
        await Printing.sharePdf(bytes: pdfBytes, filename: defaultFileName);
      } else {
        final uri = await FilePicker.saveFile(
          dialogTitle: "Save PDF Inventory Report",
          fileName: defaultFileName,
          bytes: pdfBytes,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (uri != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ PDF report saved to: $uri"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error generating PDF: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildQuantityStepper(TextEditingController controller, {int min = 1, String label = "Qty", double height = 56}) {
    return StatefulBuilder(
      builder: (context, setStepperState) {
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, color: Colors.amberAccent, size: 18),
                tooltip: "Decrease Quantity",
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () {
                  int current = int.tryParse(controller.text) ?? min;
                  if (current > min) {
                    controller.text = (current - 1).toString();
                    setStepperState(() {});
                  }
                },
              ),
              SizedBox(
                width: 48,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    hintText: label,
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onChanged: (_) => setStepperState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.greenAccent, size: 18),
                tooltip: "Increase Quantity",
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () {
                  int current = int.tryParse(controller.text) ?? min;
                  controller.text = (current + 1).toString();
                  setStepperState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final catRes = await dbPool.execute('SELECT name FROM categories');
      _categories.clear();
      for (final row in catRes) {
        _categories.add(row[0].toString());
      }
      if (_categories.isEmpty) {
        _categories.addAll(["Sensors", "Microcontrollers", "Resistors & Capacitors"]);
        for (var c in _categories) {
          await dbPool.execute('INSERT INTO categories (name) VALUES (\$1) ON CONFLICT DO NOTHING', parameters: [c]);
        }
      }

      final invRes = await dbPool.execute('SELECT id, name, quantity, category, date, image_data, description FROM inventory ORDER BY date DESC');
      _inventory.clear();
      for (final row in invRes) {
        final img = row[5] != null ? row[5] as String : null;
        final desc = row[6] != null ? row[6] as String : null;
        _inventory.add(MaterialItem(row[0] as String, row[1] as String, row[2] as int, row[3] as String, row[4] as String, img, desc));
      }

      final borRes = await dbPool.execute('SELECT id, person_name, email, phone, inventory_id, item_taken, topic, quantity_taken, date FROM borrowers ORDER BY date DESC');
      _borrowers.clear();
      for (final row in borRes) {
        // Handle migration where inventory_id might be null
        String invId = row[4] != null ? row[4] as String : "";
        _borrowers.add(BorrowerLog(row[0] as String, row[1] as String, row[2] as String, row[3] as String, invId, row[5] as String, row[6] as String, row[7] as int, row[8] as String));
      }

      setState(() {
        if (_categories.isNotEmpty) _selectedCategory = _categories.first;
        if (_inventory.isNotEmpty) {
          _selectedInventoryItemId = _inventory.first.id;
          _borrowMaterialController.text = _inventory.first.name;
        }
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading data from DB: $e");
    }
  }

  @override
  void dispose() {
    _matNameController.dispose();
    _matQtyController.dispose();
    _matDescController.dispose();
    _personNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _borrowQtyController.dispose();
    _searchNameController.dispose();
    _searchTopicController.dispose();
    _borrowTopicController.dispose();
    _borrowMaterialController.dispose();
    _borrowHistorySearchController.dispose();
    super.dispose();
  }

  void _showAddCategoryDialog() {
    final TextEditingController newCatController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF203a43),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Add New Topic", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: newCatController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "e.g. Cables", hintStyle: TextStyle(color: Colors.white54)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () async {
                final newCat = newCatController.text.trim();
                if (newCat.isNotEmpty && !_categories.contains(newCat)) {
                  await dbPool.execute('INSERT INTO categories (name) VALUES (\$1) ON CONFLICT DO NOTHING', parameters: [newCat]);
                  setState(() {
                    _categories.add(newCat);
                    _selectedCategory = newCat;
                  });
                }
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
              child: const Text("Add Topic", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    );
  }

  void _showEditCategoryDialog() {
    if (_categories.isEmpty) return;
    String targetCat = _selectedCategory ?? _categories.first;
    final TextEditingController editCatController = TextEditingController(text: targetCat);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF203a43),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.edit_note, color: Colors.amberAccent, size: 28),
                  SizedBox(width: 10),
                  Text("Edit Topic Name", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Topic to Edit:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: targetCat,
                        dropdownColor: const Color(0xFF203a43),
                        isExpanded: true,
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              targetCat = val;
                              editCatController.text = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("Updated Topic Name:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: editCatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      hintText: "Enter updated topic name",
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
                  onPressed: () async {
                    final newName = editCatController.text.trim();
                    if (newName.isEmpty) return;
                    if (newName == targetCat) {
                      Navigator.pop(context);
                      return;
                    }
                    if (_categories.contains(newName)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Topic "$newName" already exists!'), backgroundColor: Colors.orange.shade800),
                      );
                      return;
                    }

                    // Update database tables
                    await dbPool.execute('INSERT INTO categories (name) VALUES (\$1) ON CONFLICT DO NOTHING', parameters: [newName]);
                    await dbPool.execute('UPDATE inventory SET category = \$1 WHERE category = \$2', parameters: [newName, targetCat]);
                    await dbPool.execute('UPDATE borrowers SET topic = \$1 WHERE topic = \$2', parameters: [newName, targetCat]);
                    await dbPool.execute('DELETE FROM categories WHERE name = \$1', parameters: [targetCat]);

                    setState(() {
                      final idx = _categories.indexOf(targetCat);
                      if (idx != -1) _categories[idx] = newName;
                      for (var item in _inventory) {
                        if (item.category == targetCat) item.category = newName;
                      }
                      for (var b in _borrowers) {
                        if (b.topic == targetCat) b.topic = newName;
                      }
                      if (_selectedCategory == targetCat) _selectedCategory = newName;
                      if (_filterCategory == targetCat) _filterCategory = newName;
                      if (_searchTopic == targetCat) {
                        _searchTopic = newName;
                        _searchTopicController.text = newName;
                      }
                      if (_borrowTopicFilter == targetCat) {
                        _borrowTopicFilter = newName;
                        _borrowTopicController.text = newName;
                      }
                    });

                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Topic renamed to "$newName" successfully!'), backgroundColor: Colors.green),
                    );
                  },
                  child: const Text("Save Topic", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addInventoryItem() async {
    final name = _matNameController.text.trim();
    if (name.isEmpty) return;

    // Check duplicate material name
    final bool duplicate = _inventory.any(
      (item) => item.name.trim().toLowerCase() == name.toLowerCase(),
    );

    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.amber.shade900,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Material "$name" already exists in the inventory! Use the pencil icon to update its quantity.',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    
    final desc = _matDescController.text.trim();
    final newItemId = DateTime.now().millisecondsSinceEpoch.toString();
    final newItem = MaterialItem(
      newItemId,
      name,
      int.tryParse(_matQtyController.text) ?? 1,
      _selectedCategory ?? _categories.first,
      _getCurrentDate(),
      _selectedImageBase64,
      desc.isNotEmpty ? desc : null,
    );

    await dbPool.execute('INSERT INTO inventory (id, name, quantity, category, date, image_data, description) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7)', 
      parameters: [newItem.id, newItem.name, newItem.quantity, newItem.category, newItem.date, newItem.imageData, newItem.description]);

    setState(() {
      _inventory.insert(0, newItem);
      _matNameController.clear();
      _matDescController.clear();
      _matQtyController.text = "1";
      _selectedImageBase64 = null;
      if (_selectedInventoryItemId == null) _selectedInventoryItemId = newItemId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "$name" to inventory!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteInventoryItem(String id) async {
    await dbPool.execute('DELETE FROM inventory WHERE id = \$1', parameters: [id]);
    setState(() {
      _inventory.removeWhere((item) => item.id == id);
      if (_selectedInventoryItemId == id) {
        _selectedInventoryItemId = _inventory.isNotEmpty ? _inventory.first.id : null;
      }
    });
  }

  void _confirmDeleteDialog(MaterialItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF203a43),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text("Confirm Deletion", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Are you sure you want to permanently delete \"${item.name}\"?",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                "Current Stock: ${item.quantity}  •  Category: ${item.category}",
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 10),
              const Text(
                "This action cannot be undone.",
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.delete, color: Colors.white, size: 18),
              label: const Text("Delete Item", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.pop(context);
                _deleteInventoryItem(item.id);
              },
            ),
          ],
        );
      },
    );
  }

  void _editInventoryItemDialog(MaterialItem item) {
    final nameCtrl = TextEditingController(text: item.name);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final descCtrl = TextEditingController(text: item.description ?? "");
    String selectedCat = item.category;
    if (!_categories.contains(selectedCat) && _categories.isNotEmpty) {
      selectedCat = _categories.first;
    }
    String? currentImage = item.imageData;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF203a43),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.edit, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Text("Edit Material", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: currentImage != null && currentImage!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: Image.memory(
                                      base64Decode(currentImage!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                                    ),
                                  )
                                : const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 48),
                          ),
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: InkWell(
                              onTap: () async {
                                final newImg = await _pickAndProcessImage();
                                if (newImg != null) {
                                  setDialogState(() => currentImage = newImg);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: const BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                          if (currentImage != null && currentImage!.isNotEmpty)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: InkWell(
                                onTap: () => setDialogState(() => currentImage = null),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 13),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Material Name", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Category / Topic", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _categories.contains(selectedCat) ? selectedCat : null,
                          dropdownColor: const Color(0xFF203a43),
                          isExpanded: true,
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedCat = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Quantity in Stock", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    _buildQuantityStepper(qtyCtrl, min: 0, label: "Stock", height: 50),
                    const SizedBox(height: 16),
                    const Text("Description (Optional)", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        hintText: "Optional details, storage location, notes...",
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final newName = nameCtrl.text.trim();
                    final newQty = int.tryParse(qtyCtrl.text.trim());
                    if (newName.isEmpty || newQty == null || newQty < 0) {
                      return;
                    }
                    // Check if renaming collides with another existing material
                    final bool conflict = _inventory.any(
                      (m) => m.id != item.id && m.name.trim().toLowerCase() == newName.toLowerCase(),
                    );
                    if (conflict) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.amber.shade900,
                          content: Text('Another material with name "$newName" already exists!'),
                        ),
                      );
                      return;
                    }

                    final newDesc = descCtrl.text.trim();
                    await _updateInventoryItem(item.id, newName, newQty, selectedCat, currentImage, newDesc.isNotEmpty ? newDesc : null);
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateInventoryItem(String id, String newName, int newQty, String newCategory, String? newImage, String? newDesc) async {
    await dbPool.execute(
      'UPDATE inventory SET name = \$1, quantity = \$2, category = \$3, image_data = \$4, description = \$5 WHERE id = \$6',
      parameters: [newName, newQty, newCategory, newImage, newDesc, id],
    );
    setState(() {
      final index = _inventory.indexWhere((m) => m.id == id);
      if (index != -1) {
        _inventory[index].name = newName;
        _inventory[index].quantity = newQty;
        _inventory[index].category = newCategory;
        _inventory[index].imageData = newImage;
        _inventory[index].description = newDesc;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Material updated successfully!"), backgroundColor: Colors.blueAccent),
      );
    }
  }

  List<MaterialItem> _getFilteredBorrowMaterials() {
    if (_borrowTopicFilter.isEmpty || _borrowTopicFilter == "All") {
      return _inventory;
    }
    final cleanTopic = _borrowTopicFilter.toLowerCase();
    return _inventory.where((m) => m.category.toLowerCase().contains(cleanTopic)).toList();
  }

  void _syncSelectedMaterialOnTopicChange() {
    final available = _getFilteredBorrowMaterials();
    if (_selectedInventoryItemId == null || !available.any((m) => m.id == _selectedInventoryItemId)) {
      if (available.isNotEmpty) {
        _selectedInventoryItemId = available.first.id;
        _borrowMaterialController.text = available.first.name;
      } else {
        _selectedInventoryItemId = null;
        _borrowMaterialController.clear();
      }
    }
  }

  void _addBorrowerLog() async {
    if (_personNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the borrower's name"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    // Resolve selected material if null or invalid
    if (_selectedInventoryItemId == null || !_inventory.any((m) => m.id == _selectedInventoryItemId)) {
      final typedName = _borrowMaterialController.text.trim().toLowerCase();
      final exactMatch = _inventory.where((m) => m.name.toLowerCase() == typedName).toList();
      if (exactMatch.isNotEmpty) {
        _selectedInventoryItemId = exactMatch.first.id;
      } else {
        final partialMatch = _inventory.where((m) => m.name.toLowerCase().contains(typedName)).toList();
        if (partialMatch.length == 1) {
          _selectedInventoryItemId = partialMatch.first.id;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please select a material to checkout"), backgroundColor: Colors.orangeAccent),
          );
          return;
        }
      }
    }

    final int qtyTaken = int.tryParse(_borrowQtyController.text) ?? 1;

    final invIndex = _inventory.indexWhere((m) => m.id == _selectedInventoryItemId);
    if (invIndex != -1) {
      final item = _inventory[invIndex];
      if (item.quantity < qtyTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: Cannot checkout $qtyTaken. Only ${item.quantity} in stock!"), backgroundColor: Colors.redAccent)
        );
        return;
      }

      int newStock = item.quantity - qtyTaken;
      
      await dbPool.execute('UPDATE inventory SET quantity = \$1 WHERE id = \$2', parameters: [newStock, item.id]);

      final newLog = BorrowerLog(
        DateTime.now().millisecondsSinceEpoch.toString(),
        _personNameController.text.trim(),
        _emailController.text.trim(),
        _phoneController.text.trim(),
        item.id,
        item.name, 
        item.category,
        qtyTaken,
        _getCurrentDate(),
      );

      await dbPool.execute('INSERT INTO borrowers (id, person_name, email, phone, inventory_id, item_taken, topic, quantity_taken, date) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)', 
        parameters: [newLog.id, newLog.personName, newLog.email, newLog.phone, newLog.inventoryId, newLog.itemTaken, newLog.topic, newLog.quantityTaken, newLog.date]);

      setState(() {
        _inventory[invIndex].quantity = newStock;
        _borrowers.insert(0, newLog);
        
        // Only clear qty, keep user info for multiple borrow actions!
        _borrowQtyController.text = "1";
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checkout successful!"), backgroundColor: Colors.green));
      }
    }
  }

  void _returnItemDialog(BorrowerLog log) {
    final TextEditingController returnQtyCtrl = TextEditingController(text: log.quantityTaken.toString());
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF203a43),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Return ${log.itemTaken}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Total borrowed: ${log.quantityTaken}", style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text("Quantity to Return:", style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 6),
              _buildQuantityStepper(returnQtyCtrl, min: 1, label: "Return Qty", height: 50),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
              onPressed: () async {
                int returnQty = int.tryParse(returnQtyCtrl.text) ?? 0;
                if (returnQty > 0 && returnQty <= log.quantityTaken) {
                  await _processReturn(log, returnQty);
                  if (mounted) Navigator.pop(context);
                } else if (returnQty > log.quantityTaken) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Cannot return more than borrowed (${log.quantityTaken})!"), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: const Text("Process Return", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      }
    );
  }

  Future<void> _processReturn(BorrowerLog log, int returnQty) async {
    // 1. Add stock back to inventory
    final invIndex = _inventory.indexWhere((m) => m.id == log.inventoryId);
    if (invIndex != -1) {
      int newStock = _inventory[invIndex].quantity + returnQty;
      await dbPool.execute('UPDATE inventory SET quantity = \$1 WHERE id = \$2', parameters: [newStock, log.inventoryId]);
      setState(() => _inventory[invIndex].quantity = newStock);
    }

    // 2. Reduce quantity in borrower log
    int newBorrowQty = log.quantityTaken - returnQty;
    if (newBorrowQty > 0) {
      await dbPool.execute('UPDATE borrowers SET quantity_taken = \$1 WHERE id = \$2', parameters: [newBorrowQty, log.id]);
      setState(() {
        final bIndex = _borrowers.indexWhere((b) => b.id == log.id);
        if (bIndex != -1) _borrowers[bIndex].quantityTaken = newBorrowQty;
      });
    } else {
      await dbPool.execute('DELETE FROM borrowers WHERE id = \$1', parameters: [log.id]);
      setState(() => _borrowers.removeWhere((b) => b.id == log.id));
    }
  }

  Future<void> _adjustBorrowerQuantity(BorrowerLog log, int delta) async {
    if (delta > 0) {
      final invIndex = _inventory.indexWhere((m) => m.id == log.inventoryId);
      if (invIndex == -1 || _inventory[invIndex].quantity < delta) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cannot borrow more: No stock available in inventory!"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      int newStock = _inventory[invIndex].quantity - delta;
      int newBorrowQty = log.quantityTaken + delta;

      await dbPool.execute('UPDATE inventory SET quantity = \$1 WHERE id = \$2', parameters: [newStock, log.inventoryId]);
      await dbPool.execute('UPDATE borrowers SET quantity_taken = \$1 WHERE id = \$2', parameters: [newBorrowQty, log.id]);

      setState(() {
        _inventory[invIndex].quantity = newStock;
        final bIndex = _borrowers.indexWhere((b) => b.id == log.id);
        if (bIndex != -1) _borrowers[bIndex].quantityTaken = newBorrowQty;
      });
    } else if (delta < 0) {
      if (log.quantityTaken <= 1) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF203a43),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Return Final Item?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(
              "Returning this item will complete and remove the checkout record for \"${log.itemTaken}\". Proceed?",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
                onPressed: () async {
                  Navigator.pop(context);
                  await _processReturn(log, 1);
                },
                child: const Text("Return & Close Log", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
        return;
      }

      await _processReturn(log, 1);
    }
  }

  void _confirmDeleteBorrowerDialog(BorrowerLog log) {
    bool restoreStock = true;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF203a43),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                  SizedBox(width: 10),
                  Text("Delete Checkout Log", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Are you sure you want to delete this checkout record for ${log.personName}?",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Item: ${log.itemTaken}  •  Qty: ${log.quantityTaken}  •  Date: ${log.date}",
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setDlgState(() => restoreStock = !restoreStock),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Checkbox(
                            value: restoreStock,
                            activeColor: Colors.amberAccent,
                            checkColor: Colors.black,
                            onChanged: (val) => setDlgState(() => restoreStock = val ?? true),
                          ),
                          Expanded(
                            child: Text(
                              "Return borrowed items (${log.quantityTaken}) back to inventory stock",
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                  label: const Text("Delete Record", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _deleteBorrowerLog(log, restoreStock: restoreStock);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteBorrowerLog(BorrowerLog log, {bool restoreStock = true}) async {
    if (restoreStock) {
      final invIndex = _inventory.indexWhere((m) => m.id == log.inventoryId);
      if (invIndex != -1) {
        int newStock = _inventory[invIndex].quantity + log.quantityTaken;
        await dbPool.execute('UPDATE inventory SET quantity = \$1 WHERE id = \$2', parameters: [newStock, log.inventoryId]);
        setState(() => _inventory[invIndex].quantity = newStock);
      }
    }

    await dbPool.execute('DELETE FROM borrowers WHERE id = \$1', parameters: [log.id]);
    setState(() => _borrowers.removeWhere((b) => b.id == log.id));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restoreStock
              ? "Checkout record deleted & ${log.quantityTaken} items returned to stock."
              : "Checkout record deleted."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Widget _buildPhotoPickerWidget({double size = 56}) {
    return InkWell(
      onTap: () async {
        final img = await _pickAndProcessImage();
        if (img != null) {
          setState(() => _selectedImageBase64 = img);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _selectedImageBase64 != null ? Colors.blueAccent : Colors.white24),
        ),
        child: _selectedImageBase64 != null
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(
                      base64Decode(_selectedImageBase64!),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: InkWell(
                      onTap: () => setState(() => _selectedImageBase64 = null),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: Colors.blueAccent, size: size > 50 ? 22 : 18),
                  const SizedBox(height: 2),
                  const Text("Photo", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
      ),
    );
  }

  Widget _buildCategoryDropdownRow({double height = 56}) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                dropdownColor: const Color(0xFF203a43),
                isExpanded: true,
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.edit_note, color: Colors.amberAccent, size: 26),
          tooltip: "Edit Topic Name",
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _showEditCategoryDialog,
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.add_circle, color: Colors.amberAccent, size: 26),
          tooltip: "Add New Topic",
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _showAddCategoryDialog,
        ),
      ],
    );
  }

  Widget _buildSearchNameField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _searchName.isNotEmpty ? Colors.blueAccent : Colors.white12),
      ),
      child: TextField(
        controller: _searchNameController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
          hintText: "Search material by name...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          suffixIcon: _searchNameController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                  tooltip: "Clear Search",
                  onPressed: () {
                    setState(() {
                      _searchNameController.clear();
                      _searchName = "";
                    });
                  },
                )
              : null,
        ),
        onChanged: (val) => setState(() => _searchName = val.trim()),
      ),
    );
  }

  Widget _buildSearchTopicField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (_searchTopic.isNotEmpty || _filterCategory != "All") ? Colors.amberAccent : Colors.white12),
      ),
      child: TextField(
        controller: _searchTopicController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.category_outlined, color: Colors.amberAccent, size: 20),
          hintText: "Search or choose topic...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchTopicController.text.isNotEmpty || _filterCategory != "All")
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                  tooltip: "Reset Topic Filter",
                  onPressed: () {
                    setState(() {
                      _searchTopicController.clear();
                      _searchTopic = "";
                      _filterCategory = "All";
                    });
                  },
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                tooltip: "Choose Topic from List",
                color: const Color(0xFF203a43),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  setState(() {
                    if (val == "All") {
                      _searchTopicController.clear();
                      _searchTopic = "";
                      _filterCategory = "All";
                    } else {
                      _searchTopicController.text = val;
                      _searchTopic = val;
                      _filterCategory = val;
                    }
                  });
                },
                itemBuilder: (context) {
                  final topics = ["All", ..._categories];
                  final currentActive = _searchTopic.isNotEmpty ? _searchTopic : _filterCategory;
                  return topics.map((t) => PopupMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Icon(
                          t == "All" ? Icons.select_all : Icons.label_outline,
                          size: 18,
                          color: (t == currentActive || (currentActive == "All" && t == "All")) ? Colors.amberAccent : Colors.white54,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          t == "All" ? "Show All Topics" : t,
                          style: TextStyle(
                            color: (t == currentActive || (currentActive == "All" && t == "All")) ? Colors.amberAccent : Colors.white,
                            fontWeight: (t == currentActive || (currentActive == "All" && t == "All")) ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  )).toList();
                },
              ),
            ],
          ),
        ),
        onChanged: (val) {
          setState(() {
            _searchTopic = val.trim();
            _filterCategory = "All";
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final bool isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            "WAMEEDH",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: Colors.amberAccent,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0f2027),
          elevation: 0,
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: Colors.amberAccent.withValues(alpha: 0.25),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12);
              }
              return const TextStyle(color: Colors.white60, fontSize: 12);
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Colors.amberAccent);
              }
              return const IconThemeData(color: Colors.white60);
            }),
          ),
          child: NavigationBar(
            backgroundColor: const Color(0xFF0f2027),
            selectedIndex: _currentViewIndex,
            onDestinationSelected: (idx) => setState(() => _currentViewIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: "Inventory",
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: "Borrowers Log",
              ),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0f2027), Color(0xFF203a43), Color(0xFF2c5364)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              child: _currentViewIndex == 0 ? _buildInventoryView(isMobile: true) : _buildBorrowersView(isMobile: true),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0f2027), Color(0xFF203a43), Color(0xFF2c5364)]),
        ),
        child: Row(
          children: [
            GlassContainer(
              width: 250, borderRadius: BorderRadius.zero,
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const Text("WAMEEDH", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.amberAccent)),
                  const SizedBox(height: 50),
                  _SidebarItem(icon: Icons.inventory_2, title: "Inventory", isActive: _currentViewIndex == 0, onTap: () => setState(() => _currentViewIndex = 0)),
                  _SidebarItem(icon: Icons.people, title: "Borrowers Log", isActive: _currentViewIndex == 1, onTap: () => setState(() => _currentViewIndex = 1)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: _currentViewIndex == 0 ? _buildInventoryView(isMobile: false) : _buildBorrowersView(isMobile: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryView({bool isMobile = false}) {
    final filteredInventory = _inventory.where((item) {
      final matchesSearchName = _searchName.isEmpty ||
          item.name.toLowerCase().contains(_searchName.toLowerCase()) ||
          (item.description != null && item.description!.toLowerCase().contains(_searchName.toLowerCase()));
      final targetTopic = _searchTopic.isNotEmpty ? _searchTopic : _filterCategory;
      final matchesTopic = targetTopic == "All" ||
          targetTopic.isEmpty ||
          item.category.toLowerCase().contains(targetTopic.toLowerCase());
      return matchesSearchName && matchesTopic;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(isMobile ? "📦 Inventory" : "📦 Electronics Inventory", style: TextStyle(fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${filteredInventory.length} ${filteredInventory.length == 1 ? 'item' : 'items'}",
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showExportInventoryDialog(filteredInventory),
                  icon: const Icon(Icons.file_download_outlined, color: Colors.amberAccent, size: 18),
                  label: Text(
                    isMobile ? "Export" : "Export (Excel / PDF)",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF203a43),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.5)),
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
                // Layout switcher (Table vs Card view)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.table_rows_rounded),
                        tooltip: "Table View",
                        color: !_isCardView ? Colors.amberAccent : Colors.white54,
                        onPressed: () {
                          if (_isCardView) setState(() => _isCardView = false);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.grid_view_rounded),
                        tooltip: "Card View",
                        color: _isCardView ? Colors.amberAccent : Colors.white54,
                        onPressed: () {
                          if (!_isCardView) setState(() => _isCardView = true);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search Bars Row / Column
        if (isMobile) ...[
          _buildSearchNameField(),
          const SizedBox(height: 8),
          _buildSearchTopicField(),
        ] else
          Row(
            children: [
              Expanded(flex: 5, child: _buildSearchNameField()),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _buildSearchTopicField()),
            ],
          ),
        SizedBox(height: isMobile ? 12 : 20),
        GlassContainer(
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                Row(
                  children: [
                    _buildPhotoPickerWidget(size: 48),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTextField(_matNameController, "Material Name (e.g. ESP32)")),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildQuantityStepper(_matQtyController, min: 1, label: "Qty", height: 48),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCategoryDropdownRow(height: 48)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildTextField(_matDescController, "Description (Optional)")),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addInventoryItem,
                      icon: const Icon(Icons.add, color: Colors.white, size: 18),
                      label: const Text("Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    _buildPhotoPickerWidget(size: 56),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _buildTextField(_matNameController, "Material Name (e.g. ESP32)")),
                    const SizedBox(width: 12),
                    _buildQuantityStepper(_matQtyController, min: 1, label: "Qty", height: 56),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _buildCategoryDropdownRow(height: 56)),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _addInventoryItem,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text("Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19)),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(_matDescController, "Description (Optional - e.g. Pinout notes, storage bin, specs)"),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: isMobile ? 12 : 24),
        Expanded(
          child: _isCardView
              ? _buildInventoryCardsView(filteredInventory)
              : _buildInventoryTableView(filteredInventory, isMobile: isMobile),
        ),
      ],
    );
  }

  Widget _buildInventoryTableView(List<MaterialItem> items, {bool isMobile = false}) {
    Widget tableContent = Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)))),
          child: Row(
            children: const [
              Expanded(flex: 3, child: Text("Material Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white))),
              Expanded(flex: 2, child: Text("Topic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent))),
              Expanded(flex: 1, child: Text("Qty in Stock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.greenAccent))),
              Expanded(flex: 2, child: Text("Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white))),
              SizedBox(width: 96), 
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text("No items found.", style: TextStyle(color: Colors.white54, fontSize: 18)))
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final hasDesc = item.description != null && item.description!.trim().isNotEmpty;
                    return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showMaterialDetailsDialog(item),
                          hoverColor: Colors.white.withValues(alpha: 0.04),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Tooltip(
                                        message: "Click to view full component card",
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          child: item.imageBytes != null
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(7),
                                                  child: Image.memory(
                                                    item.imageBytes!,
                                                    cacheWidth: 100,
                                                    width: 44,
                                                    height: 44,
                                                    fit: BoxFit.cover,
                                                    filterQuality: FilterQuality.low,
                                                    errorBuilder: (_, __, _) => const Icon(Icons.broken_image, color: Colors.white38, size: 20),
                                                  ),
                                                )
                                              : const Icon(Icons.inventory_2_outlined, color: Colors.white30, size: 22),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              item.name,
                                              style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (hasDesc) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                item.description!.trim(),
                                                style: const TextStyle(fontSize: 12, color: Colors.white60),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)), child: Text(item.category, style: const TextStyle(color: Colors.amberAccent, fontSize: 14))))),
                                Expanded(flex: 1, child: Text("${item.quantity}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent))),
                                Expanded(flex: 2, child: Text(item.date, style: const TextStyle(color: Colors.white70, fontSize: 14))),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: "Edit Material",
                                      icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                                      onPressed: () => _editInventoryItemDialog(item),
                                    ),
                                    IconButton(
                                      tooltip: "Delete Material",
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () => _confirmDeleteDialog(item),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );

    if (isMobile) {
      return GlassContainer(
        padding: const EdgeInsets.all(0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: 720,
            child: tableContent,
          ),
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: tableContent,
    );
  }

  Widget _buildInventoryCardsView(List<MaterialItem> items) {
    if (items.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.all(0),
        child: const Center(child: Text("No items found.", style: TextStyle(color: Colors.white54, fontSize: 18))),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildMaterialCard(items[index]),
    );
  }

  Widget _buildMaterialCard(MaterialItem item) {
    final bytes = item.imageBytes;
    final hasDesc = item.description != null && item.description!.trim().isNotEmpty;
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a2c35).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / Photo header - Made significantly bigger (height: 195)
            Stack(
              children: [
                InkWell(
                  onTap: () => _showMaterialDetailsDialog(item),
                  child: Container(
                    height: 195,
                    width: double.infinity,
                    color: Colors.black26,
                    child: bytes != null
                        ? Image.memory(
                            bytes,
                            cacheWidth: 500,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 36)),
                          )
                        : const Center(child: Icon(Icons.inventory_2_outlined, color: Colors.white30, size: 52)),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f2027).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            // Details body - balanced spacing without giant gap
            Expanded(
              child: InkWell(
                onTap: () => _showMaterialDetailsDialog(item),
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasDesc) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description!.trim(),
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Stock: ${item.quantity}",
                            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Text(
                          item.date,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                          tooltip: "Edit Material",
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => _editInventoryItemDialog(item),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          tooltip: "Delete Material",
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDeleteDialog(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildBorrowHistorySearchContainer() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borrowHistorySearch.isNotEmpty ? Colors.amberAccent : Colors.white12),
      ),
      child: TextField(
        controller: _borrowHistorySearchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, color: Colors.amberAccent, size: 18),
          hintText: "Search records by person, item, topic...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: _borrowHistorySearch.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                  onPressed: () {
                    setState(() {
                      _borrowHistorySearchController.clear();
                      _borrowHistorySearch = "";
                    });
                  },
                )
              : null,
        ),
        onChanged: (val) {
          setState(() {
            _borrowHistorySearch = val.trim();
          });
        },
      ),
    );
  }

  Widget _buildBorrowTopicSelectorWidget({double height = 56}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (_borrowTopicFilter.isNotEmpty && _borrowTopicFilter != "All")
              ? Colors.amberAccent
              : Colors.transparent,
        ),
      ),
      child: TextField(
        controller: _borrowTopicController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.category_outlined, color: Colors.amberAccent, size: 20),
          hintText: "Search topic...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_borrowTopicController.text.isNotEmpty || _borrowTopicFilter != "All")
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                  tooltip: "Reset Topic Filter",
                  onPressed: () {
                    setState(() {
                      _borrowTopicController.clear();
                      _borrowTopicFilter = "All";
                      _syncSelectedMaterialOnTopicChange();
                    });
                  },
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                tooltip: "Choose Topic from List",
                color: const Color(0xFF203a43),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  setState(() {
                    if (val == "All") {
                      _borrowTopicController.clear();
                      _borrowTopicFilter = "All";
                    } else {
                      _borrowTopicController.text = val;
                      _borrowTopicFilter = val;
                    }
                    _syncSelectedMaterialOnTopicChange();
                  });
                },
                itemBuilder: (context) {
                  final topics = ["All", ..._categories];
                  return topics.map((t) => PopupMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Icon(
                          t == "All" ? Icons.apps : Icons.folder_outlined,
                          size: 18,
                          color: t == _borrowTopicFilter ? Colors.amberAccent : Colors.white70,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          t == "All" ? "All Topics" : t,
                          style: TextStyle(
                            color: t == _borrowTopicFilter ? Colors.amberAccent : Colors.white,
                            fontWeight: t == _borrowTopicFilter ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  )).toList();
                },
              ),
            ],
          ),
        ),
        onChanged: (val) {
          setState(() {
            _borrowTopicFilter = val.trim().isEmpty ? "All" : val.trim();
            _syncSelectedMaterialOnTopicChange();
          });
        },
      ),
    );
  }

  Widget _buildBorrowMaterialSelectorWidget(List<MaterialItem> availableMaterials, {double height = 56}) {
    return DropdownMenu<String>(
      key: ValueKey("borrow_mat_${_borrowTopicFilter}_${_inventory.length}_$_selectedInventoryItemId"),
      controller: _borrowMaterialController,
      initialSelection: _selectedInventoryItemId,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      menuHeight: 350,
      hintText: "Search material by name...",
      leadingIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
      trailingIcon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
      selectedTrailingIcon: const Icon(Icons.arrow_drop_up, color: Colors.amberAccent),
      textStyle: const TextStyle(color: Colors.white, fontSize: 14),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black26,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5)),
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF203a43)),
        elevation: const WidgetStatePropertyAll(12),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12))),
      ),
      filterCallback: (List<DropdownMenuEntry<String>> entries, String filter) {
        final q = filter.trim().toLowerCase();
        if (q.isEmpty) return entries;
        return entries.where((e) {
          final item = _inventory.firstWhere((inv) => inv.id == e.value, orElse: () => MaterialItem("", "", 0, "", ""));
          return item.name.toLowerCase().contains(q) || item.category.toLowerCase().contains(q);
        }).toList();
      },
      dropdownMenuEntries: availableMaterials.isEmpty
          ? [
              const DropdownMenuEntry<String>(
                value: "",
                label: "No materials available",
                enabled: false,
              )
            ]
          : availableMaterials.map((m) {
              return DropdownMenuEntry<String>(
                value: m.id,
                label: m.name,
                labelWidget: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (m.imageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            m.imageBytes!,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, _) => Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.hardware, size: 18, color: Colors.white54),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.hardware, size: 18, color: Colors.white54),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m.category,
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: m.quantity > 0 ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: m.quantity > 0 ? Colors.greenAccent : Colors.redAccent,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          m.quantity > 0 ? "Stock: ${m.quantity}" : "Out of stock",
                          style: TextStyle(
                            color: m.quantity > 0 ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      onSelected: (val) {
        setState(() {
          _selectedInventoryItemId = (val != null && val.isNotEmpty) ? val : null;
          if (_selectedInventoryItemId != null) {
            final sel = _inventory.firstWhere((m) => m.id == _selectedInventoryItemId, orElse: () => _inventory.first);
            _borrowMaterialController.text = sel.name;
          }
        });
      },
    );
  }

  Widget _buildStockBadge(MaterialItem item, {double height = 56}) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: item.quantity > 0 ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.quantity > 0 ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.redAccent.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Available", style: TextStyle(color: Colors.white54, fontSize: 10)),
          Text(
            "${item.quantity}",
            style: TextStyle(
              color: item.quantity > 0 ? Colors.greenAccent : Colors.redAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowersView({bool isMobile = false}) {
    final availableMaterials = _getFilteredBorrowMaterials();
    if (_selectedInventoryItemId != null && !availableMaterials.any((m) => m.id == _selectedInventoryItemId)) {
      _selectedInventoryItemId = availableMaterials.isNotEmpty ? availableMaterials.first.id : null;
      _borrowMaterialController.text = availableMaterials.isNotEmpty ? availableMaterials.first.name : "";
    }

    MaterialItem? currentSelectedItem;
    if (_selectedInventoryItemId != null) {
      try {
        currentSelectedItem = _inventory.firstWhere((m) => m.id == _selectedInventoryItemId);
      } catch (_) {
        currentSelectedItem = null;
      }
    }
    
    // Filter borrower records
    final filteredBorrowers = _borrowers.where((log) {
      if (_borrowHistorySearch.isEmpty) return true;
      final q = _borrowHistorySearch.toLowerCase();
      return log.personName.toLowerCase().contains(q) ||
          log.phone.toLowerCase().contains(q) ||
          log.email.toLowerCase().contains(q) ||
          log.itemTaken.toLowerCase().contains(q) ||
          log.topic.toLowerCase().contains(q);
    }).toList();

    // Group borrowers by name + phone
    Map<String, List<BorrowerLog>> groupedLogs = {};
    for (var log in filteredBorrowers) {
      String key = "${log.personName}|${log.phone}|${log.email}";
      if (!groupedLogs.containsKey(key)) groupedLogs[key] = [];
      groupedLogs[key]!.add(log);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("📝 Checkout Log", style: TextStyle(fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold, color: Colors.white)),
        SizedBox(height: isMobile ? 12 : 24),
        GlassContainer(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            children: [
              if (isMobile) ...[
                _buildTextField(_personNameController, "Person's Name"),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildTextField(_phoneController, "Phone Number")),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(_emailController, "Email Address")),
                  ],
                ),
                const SizedBox(height: 8),
                _buildBorrowTopicSelectorWidget(height: 48),
                const SizedBox(height: 8),
                _buildBorrowMaterialSelectorWidget(availableMaterials, height: 48),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (currentSelectedItem != null) ...[
                      _buildStockBadge(currentSelectedItem, height: 48),
                      const SizedBox(width: 8),
                    ],
                    _buildQuantityStepper(_borrowQtyController, min: 1, label: "Qty", height: 48),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _inventory.isEmpty ? null : _addBorrowerLog,
                        icon: const Icon(Icons.assignment_ind, color: Colors.white, size: 18),
                        label: const Text("Checkout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _inventory.isEmpty ? Colors.grey : Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildTextField(_personNameController, "Person's Name")),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildTextField(_phoneController, "Phone Number")),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildTextField(_emailController, "Email Address")),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: _buildBorrowTopicSelectorWidget(height: 56)),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: _buildBorrowMaterialSelectorWidget(availableMaterials, height: 56)),
                    if (currentSelectedItem != null) ...[
                      const SizedBox(width: 10),
                      _buildStockBadge(currentSelectedItem, height: 56),
                    ],
                    const SizedBox(width: 12),
                    _buildQuantityStepper(_borrowQtyController, min: 1, label: "Qty", height: 56),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _inventory.isEmpty ? null : _addBorrowerLog,
                      icon: const Icon(Icons.assignment_ind, color: Colors.white),
                      label: const Text("Checkout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _inventory.isEmpty ? Colors.grey : Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: isMobile ? 12 : 24),
        if (isMobile) ...[
          Row(
            children: [
              const Text("📋 Records", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueAccent)),
                child: Text("${filteredBorrowers.length} checkouts", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildBorrowHistorySearchContainer(),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text("📋 Borrowers Records", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueAccent)),
                    child: Text("${filteredBorrowers.length} checkouts", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              SizedBox(
                width: 360,
                child: _buildBorrowHistorySearchContainer(),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: GlassContainer(
            padding: const EdgeInsets.all(0),
            child: groupedLogs.isEmpty ? const Center(child: Text("No records.", style: TextStyle(color: Colors.white54, fontSize: 18)))
              : ListView.builder(
              padding: EdgeInsets.all(isMobile ? 12 : 24),
              itemCount: groupedLogs.length,
              itemBuilder: (context, index) {
                String key = groupedLogs.keys.elementAt(index);
                List<BorrowerLog> userLogs = groupedLogs[key]!;
                BorrowerLog first = userLogs.first;
                
                return Container(
                  margin: EdgeInsets.only(bottom: isMobile ? 14 : 24),
                  padding: EdgeInsets.all(isMobile ? 14 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMobile) ...[
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.amberAccent, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                first.personName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("${first.phone}  •  ${first.email}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.amberAccent, size: 28),
                            const SizedBox(width: 12),
                            Text(first.personName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            const Spacer(),
                            Text("${first.phone}  •  ${first.email}", style: const TextStyle(color: Colors.white70, fontSize: 16)),
                          ],
                        ),
                      ],
                      Divider(color: Colors.white24, height: isMobile ? 20 : 32),
                      ...userLogs.map((log) {
                        if (isMobile) {
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        log.itemTaken,
                                        style: const TextStyle(fontSize: 15, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                                      child: Text(log.topic, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(log.date, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove, color: Colors.amberAccent, size: 14),
                                            padding: const EdgeInsets.all(2),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _adjustBorrowerQuantity(log, -1),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              "Qty: ${log.quantityTaken}",
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, color: Colors.greenAccent, size: 14),
                                            padding: const EdgeInsets.all(2),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _adjustBorrowerQuantity(log, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _returnItemDialog(log),
                                      icon: const Icon(Icons.keyboard_return, color: Colors.amberAccent, size: 16),
                                      label: const Text("Return", style: TextStyle(color: Colors.amberAccent, fontSize: 13)),
                                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () => _confirmDeleteBorrowerDialog(log),
                                      tooltip: "Delete Checkout Record",
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(log.itemTaken, style: const TextStyle(fontSize: 17, color: Colors.blueAccent, fontWeight: FontWeight.w600))),
                              Expanded(flex: 2, child: Text(log.topic, style: const TextStyle(color: Colors.white70, fontSize: 14))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, color: Colors.amberAccent, size: 16),
                                      tooltip: "Return 1 unit to stock",
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _adjustBorrowerQuantity(log, -1),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        "Qty: ${log.quantityTaken}",
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, color: Colors.greenAccent, size: 16),
                                      tooltip: "Borrow 1 more unit",
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _adjustBorrowerQuantity(log, 1),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: Text(log.date, style: const TextStyle(color: Colors.white54, fontSize: 14))),
                              TextButton.icon(
                                onPressed: () => _returnItemDialog(log),
                                icon: const Icon(Icons.keyboard_return, color: Colors.amberAccent, size: 18),
                                label: const Text("Return", style: TextStyle(color: Colors.amberAccent)),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _confirmDeleteBorrowerDialog(log),
                                tooltip: "Delete Checkout Record",
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return TextField(
      controller: controller, keyboardType: isNumber ? TextInputType.number : TextInputType.text, style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.black26, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon; final String title; final bool isActive; final VoidCallback onTap;
  const _SidebarItem({required this.icon, required this.title, required this.isActive, required this.onTap});
  @override Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Icon(icon, color: isActive ? Colors.blueAccent : Colors.white54), const SizedBox(width: 16), Text(title, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 16, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child; final EdgeInsetsGeometry? padding; final double? width; final BorderRadius? borderRadius;
  const GlassContainer({super.key, required this.child, this.padding, this.width, this.borderRadius});
  @override Widget build(BuildContext context) {
    return SizedBox(width: width, child: ClipRRect(borderRadius: borderRadius ?? BorderRadius.circular(15), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0), child: Container(padding: padding, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: borderRadius ?? BorderRadius.circular(15), border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5)), child: child))));
  }
}
