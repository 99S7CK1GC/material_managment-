# Wameedh Logistics & Inventory Manager

Welcome to **Wameedh**, a comprehensive tool designed for the logistics team to efficiently manage electronics inventory, track checkouts, and handle returns.

This software is connected to a secure, real-time remote database (Neon PostgreSQL), meaning that **all logistics staff can use the app simultaneously** and the inventory will always stay perfectly in sync across everyone's computers!

---

## 🌟 Key Features

1. **Real-time Inventory Management**: Track quantities of available items across different categories.
2. **Checkout Logging**: Seamlessly record items borrowed by individuals, along with their contact information.
3. **Smart Grouped Receipts**: Checkouts are intelligently grouped by the borrower. If one person borrows 5 different items, they will all appear cleanly under a single borrower card.
4. **Partial Returns**: Staff can process returns for partial quantities. (e.g., If someone borrows 10 Arduinos but returns 8, the system will restock the 8 and keep the remaining 2 under their name).

---

## 📖 How to Use the App

The application interface is divided into two main sections: **Inventory** (left side) and **Checkout Log** (right side).

### 1. Managing Inventory (Left Panel)

* **Adding Categories**: Before you can add an item, make sure its category exists. Type a category name in the input box and click **"Add Category"**.
* **Adding New Items**: Fill out the item's details (Name, Total Quantity, and select its Category from the dropdown). Click **"Add Item"** to register it in the system.
* **Editing Stock/Deleting**: You can manage existing stock by clicking on the items listed under the inventory panel.
  * Click the **pencil icon** to adjust the total available quantity.
  * Click the **trash can icon** to permanently delete the item from the system.

### 2. Checking Out Items (Right Panel)

When a member or student wants to borrow equipment, you can log it out under their name.

1. **Fill out their info**: Enter the person's Name, Phone Number, and Email Address.
2. **Select the Material**: Pick the requested item from the "Select Material..." dropdown. You will see the current available stock next to the item name.
3. **Set the Quantity**: Enter how many of that item they are taking.
4. **Checkout**: Click the **"Checkout"** button.
5. **Multiple Items**: If the person needs more items, simply leave their contact information in the boxes, select the next item, and click checkout again! All their borrowed items will group together beautifully under one receipt card in the log below.

### 3. Processing Returns

When a borrower brings back equipment:
1. Locate their card in the **Checkout Log** view on the bottom right.
2. Find the specific item they are returning and click the **"Return"** button next to it.
3. A popup will ask you for the **Quantity to Return**.
4. Enter the number they brought back and click **"Process Return"**.
   * *Example*: If they borrowed 5 motors and return 3, type `3`. The system will automatically add 3 motors back to your available inventory stock, and their log will update to show they still owe 2 motors.

---

## ⚙️ For Developers / IT Setup

If you need to build or run the source code:

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
* Ensure you are running it on a desktop platform (Linux/Windows/macOS).

### Running the App
1. Open a terminal and navigate to the application folder:
   ```bash
   cd wameedh_app
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application (example for Linux):
   ```bash
   flutter run -d linux
   ```

*Note: The database connection string is securely connected to the Neon PostgreSQL server. Ensure your network allows outbound connections to standard PostgreSQL ports (5432).*
