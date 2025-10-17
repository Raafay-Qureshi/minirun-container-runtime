package main

import (
	"database/sql"  // SQL database interface
	"fmt"           // Formatted I/O
	"time"          // Time and duration handling

	_ "github.com/lib/pq"  // PostgreSQL driver (imported for side effects)
)

// Database handles PostgreSQL operations with connection pooling
type Database struct {
	conn *sql.DB
}

// NewDatabase creates database connection with pooling (25 max, 5 idle, 5min lifetime)
func NewDatabase(host, port, user, password, dbname string) (*Database, error) {
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)
	
	conn, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}
	
	// Test connection health
	if err := conn.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}
	
	// Configure connection pool for optimal performance
	conn.SetMaxOpenConns(25)               // Max 25 concurrent connections
	conn.SetMaxIdleConns(5)                // Keep 5 idle connections ready
	conn.SetConnMaxLifetime(5 * time.Minute)  // Recycle connections after 5 minutes
	
	return &Database{conn: conn}, nil
}

// Close shuts down database connection pool
func (db *Database) Close() error {
	if db.conn != nil {
		return db.conn.Close()
	}
	return nil
}

// CreateContainer inserts new container with parameterized query (SQL injection safe)
func (db *Database) CreateContainer(c *Container) error {
	query := `INSERT INTO containers (name, rootfs, command, status, created_at, updated_at)
	          VALUES ($1, $2, $3, $4, $5, $6)`
	
	_, err := db.conn.Exec(query,
		c.Name, c.RootFS, c.Command, c.Status, c.CreatedAt, time.Now())
	
	if err != nil {
		return fmt.Errorf("failed to create container: %w", err)
	}
	
	return nil
}

// GetContainer retrieves container by name, returns error if not found
func (db *Database) GetContainer(name string) (*Container, error) {
	query := `SELECT name, rootfs, command, status, created_at
	          FROM containers WHERE name = $1`
	
	var container Container
	err := db.conn.QueryRow(query, name).Scan(
		&container.Name, &container.RootFS, &container.Command,
		&container.Status, &container.CreatedAt)
	
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("container not found")
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get container: %w", err)
	}
	
	return &container, nil
}

// ListContainers retrieves all containers ordered by creation time (newest first)
func (db *Database) ListContainers() ([]Container, error) {
	query := `SELECT name, rootfs, command, status, created_at
	          FROM containers ORDER BY created_at DESC`
	
	rows, err := db.conn.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to list containers: %w", err)
	}
	defer rows.Close()
	
	containers := []Container{}
	for rows.Next() {
		var container Container
		err := rows.Scan(&container.Name, &container.RootFS, &container.Command,
			&container.Status, &container.CreatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan container: %w", err)
		}
		containers = append(containers, container)
	}
	
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating containers: %w", err)
	}
	
	return containers, nil
}

// UpdateContainerStatus changes container status with automatic timestamp update
func (db *Database) UpdateContainerStatus(name, status string) error {
	query := `UPDATE containers SET status = $1, updated_at = $2 WHERE name = $3`
	
	result, err := db.conn.Exec(query, status, time.Now(), name)
	if err != nil {
		return fmt.Errorf("failed to update container status: %w", err)
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}
	
	if rows == 0 {
		return fmt.Errorf("container not found")
	}
	
	return nil
}

// DeleteContainer removes container from database, returns error if not found
func (db *Database) DeleteContainer(name string) error {
	query := `DELETE FROM containers WHERE name = $1`
	
	result, err := db.conn.Exec(query, name)
	if err != nil {
		return fmt.Errorf("failed to delete container: %w", err)
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}
	
	if rows == 0 {
		return fmt.Errorf("container not found")
	}
	
	return nil
}

// ContainerExists quickly checks if container name is already taken
func (db *Database) ContainerExists(name string) (bool, error) {
	query := `SELECT EXISTS(SELECT 1 FROM containers WHERE name = $1)`
	
	var exists bool
	err := db.conn.QueryRow(query, name).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check container existence: %w", err)
	}
	
	return exists, nil
}

// InitializeSchema creates tables and indexes if they don't exist (idempotent)
func (db *Database) InitializeSchema() error {
	schema := `
		CREATE TABLE IF NOT EXISTS containers (
			id SERIAL PRIMARY KEY,
			name VARCHAR(255) UNIQUE NOT NULL,
			rootfs VARCHAR(512) NOT NULL,
			command VARCHAR(255) NOT NULL,
			status VARCHAR(50) NOT NULL,
			created_at TIMESTAMP NOT NULL,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);
		CREATE INDEX IF NOT EXISTS idx_containers_status ON containers(status);
		CREATE INDEX IF NOT EXISTS idx_containers_created ON containers(created_at);
	`
	
	_, err := db.conn.Exec(schema)
	if err != nil {
		return fmt.Errorf("failed to initialize schema: %w", err)
	}
	
	return nil
}