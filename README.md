# ⚡ Wameedh Logistics & Material Manager (وميض)

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows%20%7C%20Linux-brightgreen)](https://github.com/99S7CK1GC/material_managment-/releases)
[![Database](https://img.shields.io/badge/Database-Neon%20PostgreSQL-00E599?logo=postgresql&logoColor=white)](https://neon.tech)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Wameedh (وميض)** is a modern, real-time logistics and electronics inventory management system tailored for maker spaces, robotics clubs, and lab logistics teams. 

Connected to a cloud-hosted **Neon PostgreSQL** database, Wameedh allows team members to manage inventory, log material checkouts, and process returns simultaneously across mobile and desktop devices with real-time sync.

---

## 🌟 Key Features

### 📱 Responsive Multiplatform Experience
- **Android Mobile App**: Clean, touch-optimized mobile layout featuring intuitive bottom navigation tabs, touch-friendly dialogs, and native mobile sharing.
- **Desktop (Windows & Linux)**: High-productivity widescreen interface with side-by-side inventory and checkout views, keyboard accessibility, and native file pickers.

### 🔍 Fast Search & Smart Filtering
- **Inventory Search**: Filter materials instantly by name or category.
- **Borrower Log Material Search**: Search directly for equipment when checking out items to members—no endless scrolling through long component lists.
- **Topic / Category Filters**: Filter inventory items by customizable topics and categories.

### 🖼️ Component Detail Cards & Image Management
- Click or tap on any material card to open the **Component Details Modal**.
- View high-resolution component photos with options to:
  - 💾 **Save / Download** the component image locally.
  - 🔄 **Change / Upload** a new image directly from your device.
  - ➕ / ➖ **Adjust Stock Quantity** directly within the modal.
  - 🏷️ View category, date added, and notes/descriptions.

### 📊 Instant Inventory Export (Excel & PDF)
- Export your entire catalog or filtered search results with a single click via the **"Export (Excel / PDF)"** button.
- **Excel Spreadsheet (`.csv`)**: Generated with UTF-8 BOM encoding for seamless display in Microsoft Excel and Google Sheets without font or character issues.
- **Formatted PDF Report (`.pdf`)**: Beautiful multi-page document complete with KPI summary cards (Total Materials, Total Units, Categories, Export Date) and alternating table rows.
- **Cross-Platform Delivery**:
  - *Android*: Launches the native Share Sheet to save to Files or share via WhatsApp, Telegram, Google Drive, or Gmail.
  - *Desktop*: Opens a native Save File dialog to save directly to any folder on your computer.

### 👥 Smart Borrowers & Checkout Tracking
- **Smart Grouped Receipts**: Checkouts are grouped by borrower. If a member borrows multiple items, they appear cleanly under one borrower card.
- **Partial Returns Support**: Members can return partial quantities (e.g., returning 3 out of 5 borrowed sensors). The system immediately returns 3 to stock while keeping the remaining 2 tracked under their name.
- **Overdue & Active Tracking**: Clear indicators of active loans and member contact information (phone number, email).

---

## 📥 Downloads & Installation

Pre-built binaries are automatically built and published via GitHub Actions for every release:

👉 **[Download Latest Releases](https://github.com/99S7CK1GC/material_managment-/releases)**

| Platform | Package | How to Install & Run |
|---|---|---|
| 📱 **Android** | `Wameedh-Android.apk` | Download `.apk` to your phone, tap to install (enable "Install unknown apps" if prompted). |
| 🪟 **Windows** | `Wameedh-Windows-x64.zip` | Download, extract `.zip`, and run `wameedh_app.exe` (no installation required). |
| 🐧 **Linux** | `Wameedh-Linux-x64.tar.gz` | Download, extract `tar -xzvf Wameedh-Linux-x64.tar.gz`, and run `./run.sh`. |

---

## 📖 Using the Application

### 1. Managing Materials (Inventory View)
- **Add New Category**: Type a category name into the input field and click **"Add Category"**.
- **Add Material**: Enter the material name, initial quantity, category, and optional description or image, then click **"Add Item"**.
- **Inspect / Edit Material**: Tap on any material card to view full details, change the picture, or adjust stock counts.
- **Export**: Click the green **"Export (Excel / PDF)"** button in the inventory toolbar to download a report.

### 2. Checking Out Materials (Borrowers View)
1. Enter the borrower's **Name**, **Phone Number**, and **Email**.
2. Use the **search bar** to quickly locate the component they need.
3. Specify the quantity to borrow and click **"Checkout"**.
4. To check out additional items to the same person, leave their contact information in place, select the next item, and click checkout again.

### 3. Processing Returns
1. Locate the borrower's card in the **Checkout Log**.
2. Find the borrowed item and click **"Return"**.
3. Enter the number of units being returned and click **"Process Return"**. The stock will be updated live in the database.

---

## 💻 For Developers

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x stable)
- [Dart SDK](https://dart.dev/)
- Java 17+ (for Android builds)
- GTK 3 & CMake (for Linux desktop builds)
- Visual Studio 2022 with C++ desktop development (for Windows desktop builds)

### Environment Configuration
Create a `.env` file inside `wameedh_app/` with your Neon PostgreSQL connection credentials:

```env
DB_HOST=ep-divine-tree-b5uupalq-pooler.c-7.us-east-2.aws.neon.tech
DB_NAME=neondb
DB_USER=neondb_owner
DB_PASSWORD=your_neon_password_here
DB_PORT=5432
```

### Running Locally
```bash
cd wameedh_app

# Fetch dependencies
flutter pub get

# Run on your current platform
flutter run -d linux      # For Linux Desktop
flutter run -d windows    # For Windows Desktop
flutter run -d <device>   # For connected Android device
```

### Building Release Packages Locally
```bash
# Android APK
flutter build apk --release

# Linux Desktop Bundle
flutter build linux --release

# Windows Desktop Bundle
flutter build windows --release
```

---

## 🔄 Automated CI/CD (GitHub Actions)

All platform builds and releases are automated via [.github/workflows/build_releases.yml](.github/workflows/build_releases.yml):
- Automatically triggers on pushes to `main` and release tags (`v*`).
- Compiles **Android APK**, **Windows x64**, and **Linux x64** in parallel cloud runners.
- Uploads workflow artifacts and publishes standalone downloads directly to [GitHub Releases](https://github.com/99S7CK1GC/material_managment-/releases).

---

## 📄 License
This project is licensed under the MIT License.
