package main

import (
	"encoding/json"  // JSON encoding/decoding for API responses
	"fmt"            // Formatted I/O
	"log"            // Logging
	"net/http"       // HTTP server and client
	"os"             // Operating system functions
	"path/filepath"  // File path manipulation
	"time"           // Time and duration handling

	"github.com/gorilla/mux"  // HTTP router with URL parameters
)

// Global database instance (nil if using file storage)
var db *Database
var useDatabase bool  // true = PostgreSQL, false = JSON files

// Server configuration constants
const (
	ProjectRoot     = "/home/raafayqureshi/container-project"
	ContainersDir   = ProjectRoot + "/containers"  // JSON storage directory
	RuntimeBinary   = ProjectRoot + "/bin/container_runtime"  // C runtime binary
	DefaultRootFS   = ProjectRoot + "/myroot"  // Default container root filesystem
	ServerPort      = "8080"   // HTTP port
	ServerPortTLS   = "8443"   // HTTPS port
	ServerVersion   = "1.0.0"
	DefaultCertPath = "/etc/minirun/cert.pem"  // TLS certificate location
	DefaultKeyPath  = "/etc/minirun/key.pem"   // TLS private key location
)

// Container represents container configuration (stored in DB or JSON file)
type Container struct {
	Name      string    `json:"name"`       // Unique container name
	RootFS    string    `json:"rootfs"`     // Path to root filesystem
	Command   string    `json:"command"`    // Command to execute
	Status    string    `json:"status"`     // created/running/stopped
	CreatedAt time.Time `json:"created_at"` // Creation timestamp
}

// CreateRequest is the JSON body for POST /containers
type CreateRequest struct {
	Name    string `json:"name"`                    // Required: container name
	RootFS  string `json:"rootfs,omitempty"`        // Optional: defaults to DefaultRootFS
	Command string `json:"command,omitempty"`       // Optional: defaults to /bin/bash
}

// APIResponse is the standard JSON response format
type APIResponse struct {
	Success bool        `json:"success"`              // true if operation succeeded
	Message string      `json:"message"`              // Human-readable message
	Data    interface{} `json:"data,omitempty"`       // Response data (if any)
	Error   string      `json:"error,omitempty"`      // Error message (if failed)
}

// ErrorResponse sends JSON error with HTTP status code
func ErrorResponse(w http.ResponseWriter, message string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(APIResponse{Success: false, Error: message})
}

// SuccessResponse sends JSON success with data payload
func SuccessResponse(w http.ResponseWriter, message string, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(APIResponse{Success: true, Message: message, Data: data})
}

// HealthCheckHandler returns service status and uptime (GET /health)
func HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	health := map[string]interface{}{
		"status":  "healthy",
		"version": ServerVersion,
		"uptime":  time.Since(startTime).String(),
	}
	SuccessResponse(w, "Service is healthy", health)
}

// CreateContainerHandler creates new container config (POST /containers)
func CreateContainerHandler(w http.ResponseWriter, r *http.Request) {
	var req CreateRequest
	
	// Parse and validate JSON request body
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		ErrorResponse(w, "Invalid request body: "+err.Error(), http.StatusBadRequest)
		return
	}
	
	if req.Name == "" {
		ErrorResponse(w, "Container name is required", http.StatusBadRequest)
		return
	}
	
	// Apply defaults for optional fields
	if req.RootFS == "" {
		req.RootFS = DefaultRootFS
	}
	if req.Command == "" {
		req.Command = "/bin/bash"
	}
	
	// Build container config with current timestamp
	container := Container{
		Name: req.Name, RootFS: req.RootFS, Command: req.Command,
		Status: "created", CreatedAt: time.Now(),
	}
	
	// Save to PostgreSQL or JSON file (depends on useDatabase flag)
	if useDatabase {
		// Database path: check existence then insert
		exists, err := db.ContainerExists(req.Name)
		if err != nil {
			ErrorResponse(w, "Database error: "+err.Error(), http.StatusInternalServerError)
			return
		}
		if exists {
			ErrorResponse(w, "Container '"+req.Name+"' already exists", http.StatusConflict)
			return
		}
		
		if err := db.CreateContainer(&container); err != nil {
			ErrorResponse(w, "Failed to create container: "+err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		// File path: check existence then write JSON
		configPath := filepath.Join(ContainersDir, req.Name+".json")
		if _, err := os.Stat(configPath); err == nil {
			ErrorResponse(w, "Container '"+req.Name+"' already exists", http.StatusConflict)
			return
		}
		
		if err := os.MkdirAll(ContainersDir, 0755); err != nil {
			ErrorResponse(w, "Failed to create containers directory: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		configData, err := json.MarshalIndent(container, "", "  ")
		if err != nil {
			ErrorResponse(w, "Failed to serialize container config: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		if err := os.WriteFile(configPath, configData, 0644); err != nil {
			ErrorResponse(w, "Failed to save container config: "+err.Error(), http.StatusInternalServerError)
			return
		}
	}
	
	log.Printf("Container '%s' created successfully", req.Name)
	SuccessResponse(w, "Container created successfully", container)
}

// ListContainersHandler returns all containers (GET /containers)
func ListContainersHandler(w http.ResponseWriter, r *http.Request) {
	var containers []Container
	var err error
	
	if useDatabase {
		// Database path: query all rows
		containers, err = db.ListContainers()
		if err != nil {
			ErrorResponse(w, "Failed to list containers: "+err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		// File path: read all JSON files from directory
		entries, err := os.ReadDir(ContainersDir)
		if err != nil {
			if os.IsNotExist(err) {
				SuccessResponse(w, "No containers found", []Container{})
				return
			}
			ErrorResponse(w, "Failed to read containers directory: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		containers = []Container{}
		
		// Load each container configuration
		for _, entry := range entries {
			if filepath.Ext(entry.Name()) != ".json" {
				continue
			}
			
			configPath := filepath.Join(ContainersDir, entry.Name())
			data, err := os.ReadFile(configPath)
			if err != nil {
				log.Printf("Warning: Failed to read %s: %v", entry.Name(), err)
				continue
			}
			
			var container Container
			if err := json.Unmarshal(data, &container); err != nil {
				log.Printf("Warning: Failed to parse %s: %v", entry.Name(), err)
				continue
			}
			
			containers = append(containers, container)
		}
	}
	
	SuccessResponse(w, fmt.Sprintf("Found %d container(s)", len(containers)), containers)
}

// GetContainerHandler returns container info (GET /containers/{name})
func GetContainerHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)  // Extract URL parameters
	name := vars["name"]
	
	if name == "" {
		ErrorResponse(w, "Container name is required", http.StatusBadRequest)
		return
	}
	
	var container *Container
	var err error
	
	if useDatabase {
		// Database path: SELECT by name
		container, err = db.GetContainer(name)
		if err != nil {
			if err.Error() == "container not found" {
				ErrorResponse(w, "Container '"+name+"' not found", http.StatusNotFound)
				return
			}
			ErrorResponse(w, "Failed to get container: "+err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		// Load container configuration from file
		configPath := filepath.Join(ContainersDir, name+".json")
		data, err := os.ReadFile(configPath)
		if err != nil {
			if os.IsNotExist(err) {
				ErrorResponse(w, "Container '"+name+"' not found", http.StatusNotFound)
				return
			}
			ErrorResponse(w, "Failed to read container config: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		var c Container
		if err := json.Unmarshal(data, &c); err != nil {
			ErrorResponse(w, "Failed to parse container config: "+err.Error(), http.StatusInternalServerError)
			return
		}
		container = &c
	}
	
	SuccessResponse(w, "Container found", container)
}

// DeleteContainerHandler removes container (DELETE /containers/{name})
func DeleteContainerHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	name := vars["name"]
	
	if name == "" {
		ErrorResponse(w, "Container name is required", http.StatusBadRequest)
		return
	}
	
	if useDatabase {
		// Database path: DELETE query
		if err := db.DeleteContainer(name); err != nil {
			if err.Error() == "container not found" {
				ErrorResponse(w, "Container '"+name+"' not found", http.StatusNotFound)
				return
			}
			ErrorResponse(w, "Failed to delete container: "+err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		// Check if container exists
		configPath := filepath.Join(ContainersDir, name+".json")
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			ErrorResponse(w, "Container '"+name+"' not found", http.StatusNotFound)
			return
		}
		
		// Delete container configuration file
		if err := os.Remove(configPath); err != nil {
			ErrorResponse(w, "Failed to delete container: "+err.Error(), http.StatusInternalServerError)
			return
		}
	}
	
	log.Printf("Container '%s' deleted successfully", name)
	SuccessResponse(w, "Container deleted successfully", map[string]string{"name": name})
}

// StartContainerHandler provides container start instructions (POST /containers/{name}/start)
func StartContainerHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	name := vars["name"]
	
	if name == "" {
		ErrorResponse(w, "Container name is required", http.StatusBadRequest)
		return
	}
	
	// Load container configuration
	configPath := filepath.Join(ContainersDir, name+".json")
	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			ErrorResponse(w, "Container '"+name+"' not found", http.StatusNotFound)
			return
		}
		ErrorResponse(w, "Failed to read container config: "+err.Error(), http.StatusInternalServerError)
		return
	}
	
	var container Container
	if err := json.Unmarshal(data, &container); err != nil {
		ErrorResponse(w, "Failed to parse container config: "+err.Error(), http.StatusInternalServerError)
		return
	}
	
	// Interactive container start requires terminal I/O (not suitable for REST API)
	// Return CLI command instead for user to execute
	startInfo := map[string]string{
		"message": "Container start requires interactive terminal",
		"command": fmt.Sprintf("sudo %s %s %s %s", RuntimeBinary, container.Name, container.RootFS, container.Command),
		"cli":     fmt.Sprintf("./minirun start %s", container.Name),
	}
	
	SuccessResponse(w, "Container start information", startInfo)
}

// LoggingMiddleware logs HTTP method, URI, client IP, and duration
func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("[%s] %s %s", r.Method, r.RequestURI, r.RemoteAddr)
		next.ServeHTTP(w, r)
		log.Printf("[%s] %s completed in %v", r.Method, r.RequestURI, time.Since(start))
	})
}

// CORSMiddleware enables cross-origin requests from web browsers
func CORSMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")  // Allow all origins (restrict in production)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		
		if r.Method == "OPTIONS" {  // Preflight request
			w.WriteHeader(http.StatusOK)
			return
		}
		
		next.ServeHTTP(w, r)
	})
}

var startTime time.Time

func main() {
	startTime = time.Now()
	
	// Try to initialize PostgreSQL (falls back to JSON files if unavailable)
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	
	if dbHost != "" && dbPort != "" && dbUser != "" && dbPassword != "" && dbName != "" {
		log.Println("Initializing PostgreSQL database connection...")
		var err error
		db, err = NewDatabase(dbHost, dbPort, dbUser, dbPassword, dbName)
		if err != nil {
			log.Printf("Warning: Failed to connect to database: %v", err)
			log.Println("Falling back to file-based storage")
			useDatabase = false
		} else {
			if err := db.InitializeSchema(); err != nil {  // Create tables if needed
				log.Printf("Warning: Failed to initialize schema: %v", err)
				log.Println("Falling back to file-based storage")
				useDatabase = false
			} else {
				useDatabase = true
				log.Println("Successfully connected to PostgreSQL database")
				defer db.Close()
			}
		}
	} else {
		log.Println("Database credentials not provided, using file-based storage")
		useDatabase = false
	}
	
	// Setup HTTP router with middleware
	router := mux.NewRouter()
	router.Use(LoggingMiddleware)  // Log all requests
	router.Use(CORSMiddleware)     // Enable CORS for web clients
	
	// Register API endpoints
	router.HandleFunc("/health", HealthCheckHandler).Methods("GET")
	router.HandleFunc("/containers", CreateContainerHandler).Methods("POST")
	router.HandleFunc("/containers", ListContainersHandler).Methods("GET")
	router.HandleFunc("/containers/{name}", GetContainerHandler).Methods("GET")
	router.HandleFunc("/containers/{name}", DeleteContainerHandler).Methods("DELETE")
	router.HandleFunc("/containers/{name}/start", StartContainerHandler).Methods("POST")
	
	// Root endpoint with API documentation
	router.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		info := map[string]interface{}{
			"service": "MiniRun Container Orchestrator",
			"version": ServerVersion,
			"endpoints": []string{
				"GET    /health", "POST   /containers", "GET    /containers",
				"GET    /containers/{name}", "DELETE /containers/{name}",
				"POST   /containers/{name}/start",
			},
		}
		SuccessResponse(w, "MiniRun Orchestrator API", info)
	}).Methods("GET")
	
	// Determine certificate paths (environment variable or default)
	certPath := os.Getenv("TLS_CERT_PATH")
	keyPath := os.Getenv("TLS_KEY_PATH")
	if certPath == "" {
		certPath = DefaultCertPath
	}
	if keyPath == "" {
		keyPath = DefaultKeyPath
	}
	
	// Print startup banner
	log.Printf("╔════════════════════════════════════════════════╗")
	log.Printf("║   MiniRun Container Orchestrator              ║")
	log.Printf("║   Version: %s                               ║", ServerVersion)
	log.Printf("╚════════════════════════════════════════════════╝")
	log.Printf("")
	
	// Start HTTPS if certificates exist, otherwise HTTP
	useTLS := fileExists(certPath) && fileExists(keyPath)
	
	if useTLS {
		addr := ":" + ServerPortTLS
		log.Printf("🔒 TLS enabled")
		log.Printf("Starting HTTPS server on https://localhost%s", addr)
		log.Printf("API Documentation: https://localhost%s/", addr)
		log.Printf("Certificate: %s", certPath)
		log.Printf("Private Key: %s", keyPath)
		log.Printf("")
		
		if err := http.ListenAndServeTLS(addr, certPath, keyPath, router); err != nil {
			log.Fatalf("HTTPS server failed to start: %v", err)
		}
	} else {
		addr := ":" + ServerPort
		log.Printf("⚠️  TLS disabled - Running in HTTP mode")
		log.Printf("Starting HTTP server on http://localhost%s", addr)
		log.Printf("API Documentation: http://localhost%s/", addr)
		log.Printf("")
		log.Printf("To enable HTTPS:")
		log.Printf("  1. Generate certificates: openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes")
		log.Printf("  2. Place them at: %s and %s", certPath, keyPath)
		log.Printf("  3. Restart the server")
		log.Printf("")
		
		if err := http.ListenAndServe(addr, router); err != nil {
			log.Fatalf("HTTP server failed to start: %v", err)
		}
	}
}

// fileExists checks if file exists at given path
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}