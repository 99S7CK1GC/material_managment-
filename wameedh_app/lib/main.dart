import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:file_picker/file_picker.dart';

late Pool dbPool;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");
  
  dbPool = Pool.withEndpoints([
    Endpoint(
      host: dotenv.env['DB_HOST']!,
      database: dotenv.env['DB_NAME']!,
      username: dotenv.env['DB_USER']!,
      password: dotenv.env['DB_PASSWORD']!,
      port: int.parse(dotenv.env['DB_PORT'] ?? '5432'),
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

  void _showImagePreviewDialog(MaterialItem item) {
    if (item.imageData == null || item.imageData!.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF203a43),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: item.imageBytes != null
                      ? Image.memory(
                          item.imageBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80, color: Colors.white38),
                        )
                      : const Icon(Icons.broken_image, size: 80, color: Colors.white38),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("Category: ${item.category}", style: const TextStyle(color: Colors.amberAccent)),
                      Text("Stock: ${item.quantity}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
        if (_inventory.isNotEmpty) _selectedInventoryItemId = _inventory.first.id;
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

  void _addBorrowerLog() async {
    if (_personNameController.text.trim().isEmpty || _selectedInventoryItemId == null) return;
    final int qtyTaken = int.tryParse(_borrowQtyController.text) ?? 1;

    final invIndex = _inventory.indexWhere((m) => m.id == _selectedInventoryItemId);
    if (invIndex != -1) {
      final item = _inventory[invIndex];
      if (item.quantity < qtyTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: Cannot checkout ${qtyTaken}. Only ${item.quantity} in stock!"), backgroundColor: Colors.redAccent)
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checkout successful!"), backgroundColor: Colors.green));
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

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
                child: _currentViewIndex == 0 ? _buildInventoryView() : _buildBorrowersView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryView() {
    final filteredInventory = _filterCategory == "All" ? _inventory : _inventory.where((item) => item.category == _filterCategory).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("📦 Electronics Inventory", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            Row(
              children: [
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
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list, color: Colors.white54),
                      const SizedBox(width: 10),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filterCategory,
                          dropdownColor: const Color(0xFF203a43),
                          items: ["All", ..._categories].map((c) => DropdownMenuItem(value: c, child: Text(c == "All" ? "Show All Topics" : "Topic: $c", style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (val) => setState(() => _filterCategory = val!),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () async {
                      final img = await _pickAndProcessImage();
                      if (img != null) {
                        setState(() => _selectedImageBase64 = img);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 56,
                      height: 56,
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
                                    width: 56,
                                    height: 56,
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
                              children: const [
                                Icon(Icons.add_a_photo_outlined, color: Colors.blueAccent, size: 22),
                                SizedBox(height: 2),
                                Text("Photo", style: TextStyle(color: Colors.white54, fontSize: 10)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: _buildTextField(_matNameController, "Material Name (e.g. ESP32)")),
                  const SizedBox(width: 12),
                  _buildQuantityStepper(_matQtyController, min: 1, label: "Qty", height: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategory,
                                dropdownColor: const Color(0xFF203a43),
                                isExpanded: true,
                                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                                onChanged: (val) => setState(() => _selectedCategory = val),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.edit_note, color: Colors.amberAccent, size: 30),
                          tooltip: "Edit Topic Name",
                          onPressed: _showEditCategoryDialog,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.amberAccent, size: 32),
                          tooltip: "Add New Topic",
                          onPressed: _showAddCategoryDialog,
                        ),
                      ],
                    ),
                  ),
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
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: _isCardView
              ? _buildInventoryCardsView(filteredInventory)
              : _buildInventoryTableView(filteredInventory),
        ),
      ],
    );
  }

  Widget _buildInventoryTableView(List<MaterialItem> items) {
    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)))),
            child: Row(
              children: const [
                Expanded(flex: 3, child: Text("Material Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))),
                Expanded(flex: 2, child: Text("Topic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent))),
                Expanded(flex: 1, child: Text("Qty in Stock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.greenAccent))),
                Expanded(flex: 2, child: Text("Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))),
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
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Tooltip(
                                    message: item.imageBytes != null ? "Click to view full photo" : "No photo",
                                    child: InkWell(
                                      onTap: item.imageBytes != null
                                          ? () => _showImagePreviewDialog(item)
                                          : null,
                                      borderRadius: BorderRadius.circular(8),
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
                                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 20),
                                                ),
                                              )
                                            : const Icon(Icons.inventory_2_outlined, color: Colors.white30, size: 22),
                                      ),
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
                      );
                    },
                  ),
          ),
        ],
      ),
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
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
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
            // Image / Photo header
            Stack(
              children: [
                InkWell(
                  onTap: bytes != null ? () => _showImagePreviewDialog(item) : null,
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    color: Colors.black26,
                    child: bytes != null
                        ? Image.memory(
                            bytes,
                            cacheWidth: 350,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 36)),
                          )
                        : const Center(child: Icon(Icons.inventory_2_outlined, color: Colors.white30, size: 44)),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            // Details body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
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
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 4),
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
          ],
        ),
      ),
    );
  }

  Widget _buildBorrowersView() {
    if (_selectedInventoryItemId != null && !_inventory.any((m) => m.id == _selectedInventoryItemId)) {
      _selectedInventoryItemId = _inventory.isNotEmpty ? _inventory.first.id : null;
    }
    
    // Group borrowers by name + phone
    Map<String, List<BorrowerLog>> groupedLogs = {};
    for (var log in _borrowers) {
      String key = "${log.personName}|${log.phone}|${log.email}";
      if (!groupedLogs.containsKey(key)) groupedLogs[key] = [];
      groupedLogs[key]!.add(log);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📝 Checkout Log", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 24),
        GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(flex: 2, child: _buildTextField(_personNameController, "Person's Name")),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _buildTextField(_phoneController, "Phone Number")),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _buildTextField(_emailController, "Email Address")),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          hint: const Text("Select Material...", style: TextStyle(color: Colors.white54)),
                          value: _selectedInventoryItemId,
                          dropdownColor: const Color(0xFF203a43),
                          isExpanded: true,
                          items: _inventory.map((m) => DropdownMenuItem(value: m.id, child: Text("${m.name} (In Stock: ${m.quantity})", style: const TextStyle(color: Colors.white)))).toList(),
                          onChanged: (val) => setState(() => _selectedInventoryItemId = val),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildQuantityStepper(_borrowQtyController, min: 1, label: "Qty", height: 56),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _inventory.isEmpty ? null : _addBorrowerLog, icon: const Icon(Icons.assignment_ind, color: Colors.white), label: const Text("Checkout", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: _inventory.isEmpty ? Colors.grey : Colors.green, padding: const EdgeInsets.all(20)),
                  )
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GlassContainer(
            padding: const EdgeInsets.all(0),
            child: groupedLogs.isEmpty ? const Center(child: Text("No records.", style: TextStyle(color: Colors.white54, fontSize: 18)))
              : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: groupedLogs.length,
              itemBuilder: (context, index) {
                String key = groupedLogs.keys.elementAt(index);
                List<BorrowerLog> userLogs = groupedLogs[key]!;
                BorrowerLog first = userLogs.first;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, color: Colors.amberAccent, size: 28),
                          const SizedBox(width: 12),
                          Text(first.personName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          const Spacer(),
                          Text("${first.phone}  •  ${first.email}", style: const TextStyle(color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 32),
                      ...userLogs.map((log) => Padding(
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
                      )),
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
