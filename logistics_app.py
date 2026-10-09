import sys
import sqlite3
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QLineEdit, QSpinBox, 
                             QDateEdit, QComboBox, QPushButton, QTableWidget, 
                             QTableWidgetItem, QHeaderView, QGraphicsDropShadowEffect, QMessageBox)
from PyQt6.QtCore import Qt, QDate
from PyQt6.QtGui import QColor

DB_NAME = "logistics_data.db"

def init_db():
    # Creates a local database file to save your data permanently
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS inventory
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  material TEXT, 
                  quantity INTEGER, 
                  date TEXT, 
                  member TEXT)''')
    conn.commit()
    conn.close()

class LogisticsApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Logistics & Material Hub")
        self.resize(1050, 700)
        self.initUI()
        self.load_data()

    def initUI(self):
        # 1. Main Central Widget with Background Gradient
        self.central_widget = QWidget()
        self.central_widget.setObjectName("CentralWidget")
        self.setCentralWidget(self.central_widget)

        # Main Layout
        self.main_layout = QVBoxLayout(self.central_widget)
        self.main_layout.setContentsMargins(50, 50, 50, 50)

        # 2. Glass Panel Container (The Frosted UI look)
        self.glass_panel = QWidget()
        self.glass_panel.setObjectName("GlassPanel")
        
        # Add shadow to glass panel to make it pop out
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(25)
        shadow.setColor(QColor(0, 0, 0, 150))
        shadow.setOffset(0, 8)
        self.glass_panel.setGraphicsEffect(shadow)

        self.panel_layout = QVBoxLayout(self.glass_panel)
        self.panel_layout.setSpacing(20)
        self.panel_layout.setContentsMargins(30, 30, 30, 30)

        # 3. Title
        self.title_label = QLabel("📦 Logistics Material Organizer")
        self.title_label.setObjectName("TitleLabel")
        self.title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.panel_layout.addWidget(self.title_label)

        # 4. Input Form Layout (for Non-Developers to easily add stuff)
        self.form_layout = QHBoxLayout()
        self.form_layout.setSpacing(15)

        # Material Name Input
        self.material_input = QLineEdit()
        self.material_input.setPlaceholderText("Enter Material Name...")
        self.form_layout.addWidget(self.material_input)

        # Quantity Input
        self.qty_input = QSpinBox()
        self.qty_input.setRange(1, 1000000)
        self.qty_input.setPrefix("Qty: ")
        self.form_layout.addWidget(self.qty_input)

        # Date Input (Defaults to today)
        self.date_input = QDateEdit()
        self.date_input.setCalendarPopup(True)
        self.date_input.setDate(QDate.currentDate())
        self.form_layout.addWidget(self.date_input)

        # Member/Department Input
        self.member_input = QComboBox()
        self.member_input.addItems([
            "Member 1 (Alpha Dept)", 
            "Member 2 (Beta Dept)", 
            "Member 3 (Gamma Dept)", 
            "External/Other"
        ])
        self.form_layout.addWidget(self.member_input)

        # Add Button
        self.add_btn = QPushButton("➕ Add Material")
        self.add_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.add_btn.clicked.connect(self.add_item)
        self.form_layout.addWidget(self.add_btn)

        self.panel_layout.addLayout(self.form_layout)

        # 5. Table for Displaying Data
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["ID", "Material", "Quantity", "Date", "Added By"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers) # Prevent accidental typing in the table
        self.table.verticalHeader().setVisible(False)
        self.table.setShowGrid(False)
        self.panel_layout.addWidget(self.table)

        # 6. Delete Button (at the bottom right)
        self.delete_btn = QPushButton("🗑️ Delete Selected")
        self.delete_btn.setObjectName("DeleteBtn")
        self.delete_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.delete_btn.clicked.connect(self.delete_item)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        btn_layout.addWidget(self.delete_btn)
        self.panel_layout.addLayout(btn_layout)

        self.main_layout.addWidget(self.glass_panel)

        # Apply Modern Glassy Stylesheet
        self.apply_stylesheet()

    def apply_stylesheet(self):
        # QSS (Qt Style Sheets) is similar to CSS and allows us to make it look modern
        self.setStyleSheet("""
            QWidget#CentralWidget {
                /* A modern dark gradient background */
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                                            stop:0 #0f2027, stop:0.5 #203a43, stop:1 #2c5364);
            }
            QWidget#GlassPanel {
                /* Semi-transparent white to create a glass effect */
                background-color: rgba(255, 255, 255, 0.1);
                border-radius: 20px;
                border: 1px solid rgba(255, 255, 255, 0.2);
            }
            QLabel#TitleLabel {
                color: white;
                font-size: 28px;
                font-weight: bold;
                font-family: 'Segoe UI', -apple-system, Roboto, sans-serif;
                margin-bottom: 10px;
            }
            QLineEdit, QSpinBox, QDateEdit, QComboBox {
                background-color: rgba(0, 0, 0, 0.3);
                color: white;
                border: 1px solid rgba(255, 255, 255, 0.2);
                border-radius: 8px;
                padding: 10px;
                font-size: 14px;
                font-family: 'Segoe UI', -apple-system, Roboto, sans-serif;
            }
            QLineEdit:focus, QSpinBox:focus, QDateEdit:focus, QComboBox:focus {
                border: 1px solid rgba(0, 150, 255, 0.8);
                background-color: rgba(0, 0, 0, 0.5);
            }
            QComboBox::drop-down { border: none; }
            QComboBox QAbstractItemView {
                background-color: #203a43;
                color: white;
                selection-background-color: #2c5364;
                border: 1px solid rgba(255,255,255,0.2);
            }
            QPushButton {
                background-color: rgba(0, 150, 255, 0.6);
                color: white;
                border-radius: 8px;
                padding: 10px 20px;
                font-size: 14px;
                font-weight: bold;
                font-family: 'Segoe UI', -apple-system, Roboto, sans-serif;
            }
            QPushButton:hover {
                background-color: rgba(0, 150, 255, 0.9);
            }
            QPushButton#DeleteBtn {
                background-color: rgba(255, 50, 50, 0.5);
            }
            QPushButton#DeleteBtn:hover {
                background-color: rgba(255, 50, 50, 0.9);
            }
            QTableWidget {
                background-color: rgba(0, 0, 0, 0.2);
                color: white;
                border-radius: 10px;
                border: 1px solid rgba(255, 255, 255, 0.1);
                font-size: 14px;
                font-family: 'Segoe UI', -apple-system, Roboto, sans-serif;
                outline: 0; /* Removes dotted border on click */
            }
            QHeaderView::section {
                background-color: rgba(255, 255, 255, 0.05);
                color: white;
                padding: 10px;
                border: none;
                font-weight: bold;
                font-size: 14px;
            }
            QTableWidget::item {
                padding: 5px;
                border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            }
            QTableWidget::item:selected {
                background-color: rgba(0, 150, 255, 0.5);
            }
            
            /* Scrollbar styling for a modern look */
            QScrollBar:vertical {
                border: none;
                background: rgba(0, 0, 0, 0.2);
                width: 12px;
                border-radius: 6px;
            }
            QScrollBar::handle:vertical {
                background: rgba(255, 255, 255, 0.3);
                border-radius: 6px;
                min-height: 20px;
            }
            QScrollBar::handle:vertical:hover {
                background: rgba(255, 255, 255, 0.5);
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                border: none;
                background: none;
            }
        """)

    def load_data(self):
        self.table.setRowCount(0) # Clear existing table
        conn = sqlite3.connect(DB_NAME)
        c = conn.cursor()
        c.execute("SELECT * FROM inventory ORDER BY id DESC")
        rows = c.fetchall()
        conn.close()

        for row_idx, row_data in enumerate(rows):
            self.table.insertRow(row_idx)
            for col_idx, col_data in enumerate(row_data):
                item = QTableWidgetItem(str(col_data))
                item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                self.table.setItem(row_idx, col_idx, item)

    def add_item(self):
        material = self.material_input.text().strip()
        qty = self.qty_input.value()
        date = self.date_input.date().toString("yyyy-MM-dd")
        member = self.member_input.currentText()

        if not material:
            QMessageBox.warning(self, "Input Error", "Material name cannot be empty.")
            return

        # Save to database
        conn = sqlite3.connect(DB_NAME)
        c = conn.cursor()
        c.execute("INSERT INTO inventory (material, quantity, date, member) VALUES (?, ?, ?, ?)",
                  (material, qty, date, member))
        conn.commit()
        conn.close()

        # Reset the input field and reload the table
        self.material_input.clear()
        self.qty_input.setValue(1)
        self.load_data()

    def delete_item(self):
        selected_rows = self.table.selectionModel().selectedRows()
        if not selected_rows:
            QMessageBox.information(self, "Select Item", "Please select an item from the table to delete.")
            return

        reply = QMessageBox.question(self, 'Confirm Delete', 'Are you sure you want to delete the selected item(s)?',
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No, QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.Yes:
            conn = sqlite3.connect(DB_NAME)
            c = conn.cursor()
            for index in selected_rows:
                # Get the ID from the first column
                item_id = self.table.item(index.row(), 0).text()
                c.execute("DELETE FROM inventory WHERE id=?", (item_id,))
            conn.commit()
            conn.close()
            self.load_data() # Refresh UI

if __name__ == '__main__':
    # Initialize Database on startup
    init_db()
    
    app = QApplication(sys.argv)
    
    # Force a modern system font globally
    font = app.font()
    font.setFamily("Segoe UI")
    app.setFont(font)

    # Show Window
    window = LogisticsApp()
    window.show()
    sys.exit(app.exec())
