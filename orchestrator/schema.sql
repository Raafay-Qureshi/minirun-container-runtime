-- PostgreSQL Schema for MiniRun Container Orchestrator
-- Run this to manually create the schema (or let database.go auto-create it)

DROP TABLE IF EXISTS containers CASCADE;  -- Clean slate for fresh install

CREATE TABLE containers (
    id SERIAL PRIMARY KEY,                -- Auto-incrementing ID
    name VARCHAR(255) UNIQUE NOT NULL,    -- Unique container name
    rootfs VARCHAR(512) NOT NULL,         -- Path to root filesystem
    command VARCHAR(255) NOT NULL,        -- Command to execute
    status VARCHAR(50) NOT NULL CHECK (status IN ('created', 'running', 'stopped', 'failed')),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- Creation time
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP            -- Last modification time
);

CREATE INDEX idx_containers_status ON containers(status);      -- Fast status queries
CREATE INDEX idx_containers_created ON containers(created_at); -- Fast time-based queries
CREATE INDEX idx_containers_name ON containers(name);          -- Fast name lookups

-- Auto-update updated_at timestamp on any row change
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;  -- Set to current time on UPDATE
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_containers_updated_at
    BEFORE UPDATE ON containers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();