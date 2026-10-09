package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var db *sql.DB

// --- Models ---
type Category struct {
	Name string `json:"name"`
}

type MaterialItem struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Quantity int    `json:"quantity"`
	Category string `json:"category"`
	Date     string `json:"date"`
}

type BorrowerLog struct {
	ID            string `json:"id"`
	PersonName    string `json:"personName"`
	Email         string `json:"email"`
	Phone         string `json:"phone"`
	ItemTaken     string `json:"itemTaken"`
	Topic         string `json:"topic"`
	QuantityTaken int    `json:"quantityTaken"`
	Date          string `json:"date"`
}

// --- DB Setup ---
func initDB() {
	var err error
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	// Create tables if they don't exist
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS categories (
			name TEXT PRIMARY KEY
		);
		CREATE TABLE IF NOT EXISTS inventory (
			id TEXT PRIMARY KEY,
			name TEXT,
			quantity INT,
			category TEXT,
			date TEXT
		);
		CREATE TABLE IF NOT EXISTS borrowers (
			id TEXT PRIMARY KEY,
			person_name TEXT,
			email TEXT,
			phone TEXT,
			item_taken TEXT,
			topic TEXT,
			quantity_taken INT,
			date TEXT
		);
	`)
	if err != nil {
		log.Fatal("Failed to create tables:", err)
	}
	
	// Insert default categories if empty
	var count int
	db.QueryRow("SELECT COUNT(*) FROM categories").Scan(&count)
	if count == 0 {
		db.Exec("INSERT INTO categories (name) VALUES ('Sensors'), ('Microcontrollers'), ('Resistors & Capacitors')")
	}
}

// --- Middleware ---
func enableCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// --- Handlers ---
func getCategories(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT name FROM categories")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var cats []string
	for rows.Next() {
		var name string
		rows.Scan(&name)
		cats = append(cats, name)
	}
	json.NewEncoder(w).Encode(cats)
}

func addCategory(w http.ResponseWriter, r *http.Request) {
	var cat Category
	json.NewDecoder(r.Body).Decode(&cat)
	_, err := db.Exec("INSERT INTO categories (name) VALUES ($1) ON CONFLICT DO NOTHING", cat.Name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func getInventory(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT id, name, quantity, category, date FROM inventory ORDER BY date DESC")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	items := []MaterialItem{}
	for rows.Next() {
		var i MaterialItem
		rows.Scan(&i.ID, &i.Name, &i.Quantity, &i.Category, &i.Date)
		items = append(items, i)
	}
	json.NewEncoder(w).Encode(items)
}

func addInventory(w http.ResponseWriter, r *http.Request) {
	var i MaterialItem
	json.NewDecoder(r.Body).Decode(&i)
	_, err := db.Exec("INSERT INTO inventory (id, name, quantity, category, date) VALUES ($1, $2, $3, $4, $5)",
		i.ID, i.Name, i.Quantity, i.Category, i.Date)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func deleteInventory(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	_, err := db.Exec("DELETE FROM inventory WHERE id = $1", vars["id"])
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func updateInventoryStock(w http.ResponseWriter, r *http.Request) {
    var payload struct {
        ID       string `json:"id"`
        Quantity int    `json:"quantity"`
    }
    json.NewDecoder(r.Body).Decode(&payload)
    _, err := db.Exec("UPDATE inventory SET quantity = $1 WHERE id = $2", payload.Quantity, payload.ID)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    w.WriteHeader(http.StatusOK)
}

func getBorrowers(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT id, person_name, email, phone, item_taken, topic, quantity_taken, date FROM borrowers ORDER BY date DESC")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	logs := []BorrowerLog{}
	for rows.Next() {
		var b BorrowerLog
		rows.Scan(&b.ID, &b.PersonName, &b.Email, &b.Phone, &b.ItemTaken, &b.Topic, &b.QuantityTaken, &b.Date)
		logs = append(logs, b)
	}
	json.NewEncoder(w).Encode(logs)
}

func addBorrower(w http.ResponseWriter, r *http.Request) {
	var b BorrowerLog
	json.NewDecoder(r.Body).Decode(&b)
	_, err := db.Exec("INSERT INTO borrowers (id, person_name, email, phone, item_taken, topic, quantity_taken, date) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
		b.ID, b.PersonName, b.Email, b.Phone, b.ItemTaken, b.Topic, b.QuantityTaken, b.Date)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func deleteBorrower(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	_, err := db.Exec("DELETE FROM borrowers WHERE id = $1", vars["id"])
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func main() {
	godotenv.Load() // load .env if it exists
	initDB()

	r := mux.NewRouter()
	r.HandleFunc("/api/categories", getCategories).Methods("GET")
	r.HandleFunc("/api/categories", addCategory).Methods("POST")
	
	r.HandleFunc("/api/inventory", getInventory).Methods("GET")
	r.HandleFunc("/api/inventory", addInventory).Methods("POST")
	r.HandleFunc("/api/inventory/{id}", deleteInventory).Methods("DELETE")
	r.HandleFunc("/api/inventory/stock", updateInventoryStock).Methods("PUT")
	
	r.HandleFunc("/api/borrowers", getBorrowers).Methods("GET")
	r.HandleFunc("/api/borrowers", addBorrower).Methods("POST")
	r.HandleFunc("/api/borrowers/{id}", deleteBorrower).Methods("DELETE")

	handler := enableCORS(r)

	log.Println("🚀 Wameedh Go Backend connected to Neon Postgres! Running on http://127.0.0.1:8080")
	srv := &http.Server{
		Handler:      handler,
		Addr:         ":8080",
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
	}
	log.Fatal(srv.ListenAndServe())
}
