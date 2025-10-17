# Container Orchestrator - REST API

Go-based HTTP API for programmatic container management. Provides JSON endpoints for all container operations with optional PostgreSQL storage.

## Features

- RESTful JSON API for container CRUD operations
- PostgreSQL database with automatic fallback to file storage
- SSL/TLS support (HTTPS on port 8443)
- CORS enabled for web clients
- Request logging with timing
- Health monitoring endpoint

## Quick Start
```bash
cd orchestrator

# File storage mode (default)
go run *.go

# With PostgreSQL
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=minirun
export DB_PASSWORD=your_password
export DB_NAME=minirun
go run *.go

# Build binary
go build -o minirun-api *.go
./minirun-api
```

Server starts on `http://localhost:8080` (or `https://localhost:8443` if certificates present).

## API Endpoints

### Health Check
```
GET /health
```

Returns service status and uptime.
```json
{
  "success": true,
  "message": "Service is healthy",
  "data": {
    "status": "healthy",
    "version": "1.0.0",
    "uptime": "1h30m45s"
  }
}
```

### Create Container
```
POST /containers
```

**Request:**
```json
{
  "name": "webapp",
  "rootfs": "/path/to/rootfs",  // optional
  "command": "/bin/bash"         // optional
}
```

**Response:**
```json
{
  "success": true,
  "message": "Container created successfully",
  "data": {
    "name": "webapp",
    "rootfs": "/home/user/container-project/myroot",
    "command": "/bin/bash",
    "status": "created",
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

### List Containers
```
GET /containers
```

Returns all containers with their configurations.

### Get Container
```
GET /containers/{name}
```

Returns specific container details.

### Delete Container
```
DELETE /containers/{name}
```

Removes container configuration (must be stopped first).

### Start Container
```
POST /containers/{name}/start
```

Returns instructions for starting the container (requires interactive terminal).
```json
{
  "success": true,
  "message": "Container start information",
  "data": {
    "message": "Container start requires interactive terminal",
    "command": "sudo /path/to/container_runtime webapp /path/to/rootfs /bin/bash",
    "cli": "./minirun start webapp"
  }
}
```

## Usage Examples

### cURL
```bash
# Create
curl -X POST http://localhost:8080/containers \
  -H "Content-Type: application/json" \
  -d '{"name":"webapp","command":"/bin/bash"}'

# List
curl http://localhost:8080/containers | jq

# Get one
curl http://localhost:8080/containers/webapp

# Delete
curl -X DELETE http://localhost:8080/containers/webapp
```

### Python
```python
import requests

# Create container
r = requests.post('http://localhost:8080/containers', json={
    'name': 'webapp',
    'command': '/bin/bash'
})
print(r.json())

# List containers
r = requests.get('http://localhost:8080/containers')
for container in r.json()['data']:
    print(f"Container: {container['name']}")

# Delete
requests.delete('http://localhost:8080/containers/webapp')
```

### JavaScript/Node.js
```javascript
// Create container
const response = await fetch('http://localhost:8080/containers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'webapp',
    command: '/bin/bash'
  })
});
const data = await response.json();
console.log(data);

// List containers
const list = await fetch('http://localhost:8080/containers');
const containers = await list.json();
console.log(containers.data);
```

## Database Configuration

### PostgreSQL Setup
```bash
# Install PostgreSQL
sudo apt-get install postgresql

# Create database and user
sudo -u postgres psql
CREATE DATABASE minirun;
CREATE USER minirun WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE minirun TO minirun;
\q
```

### Configure Environment Variables
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=minirun
export DB_PASSWORD=your_password
export DB_NAME=minirun
```

### Storage Options

**PostgreSQL (when configured):**
- Automatic schema initialization
- Connection pooling (25 max, 5 idle)
- Indexed queries for performance
- Automatic timestamp updates

**File-based (fallback):**
- JSON files in `containers/` directory
- No database required
- Simple and portable
- Automatically used if DB unavailable

The API automatically detects which storage to use and falls back gracefully.

## SSL/TLS Configuration

Server automatically enables HTTPS when certificates are present.

**Default certificate paths:**
- `/etc/minirun/cert.pem`
- `/etc/minirun/key.pem`

**Custom paths via environment variables:**
```bash
export TLS_CERT_PATH=/path/to/cert.pem
export TLS_KEY_PATH=/path/to/key.pem
```

**Generate self-signed certificates:**
```bash
sudo ../scripts/generate_certificates.sh
```

**Ports:**
- HTTP: 8080
- HTTPS: 8443 (when certificates present)

## Configuration

Constants in `main.go`:
```go
const (
    ProjectRoot   = "/home/user/container-project"
    ContainersDir = "containers"
    RuntimeBinary = "bin/container_runtime"
    DefaultRootFS = "myroot"
    ServerPort    = "8080"
    TLSPort       = "8443"
)
```

Update these for your environment or use environment variables for database settings.

## Error Responses

Standard HTTP status codes:

| Code | Meaning | When |
|------|---------|------|
| 200 | OK | Successful operation |
| 400 | Bad Request | Invalid input |
| 404 | Not Found | Container doesn't exist |
| 409 | Conflict | Container already exists |
| 500 | Internal Error | Server-side problem |

**Error format:**
```json
{
  "success": false,
  "error": "Container 'webapp' not found"
}
```

## Request Logging

All requests logged with timing:
```
[POST] /containers 192.168.1.100:52341
[POST] /containers completed in 15.234ms
[GET] /containers 192.168.1.100:52341
[GET] /containers completed in 2.156ms
[DELETE] /containers/webapp 192.168.1.100:52341
[DELETE] /containers/webapp completed in 8.123ms
```

## Project Structure
```
orchestrator/
├── main.go          # API server and routing
├── database.go      # PostgreSQL integration
├── schema.sql       # Database schema
├── go.mod           # Go dependencies
├── go.sum           # Dependency checksums
└── README.md        # This file
```

## Building and Running
```bash
# Development (with auto-reload)
go run *.go

# Build binary
go build -o minirun-api *.go

# Run binary
./minirun-api

# Build for production (optimized)
go build -ldflags="-s -w" -o minirun-api *.go
```

## Testing
```bash
# Run tests
go test ./...

# With race detection
go test -race ./...

# Coverage report
go test -cover ./...
```

## Integration Examples

### Web Frontend
```javascript
// React component example
const [containers, setContainers] = useState([]);

useEffect(() => {
  fetch('http://localhost:8080/containers')
    .then(res => res.json())
    .then(data => setContainers(data.data));
}, []);
```

### CI/CD Pipeline
```yaml
# GitHub Actions example
- name: Deploy Container
  run: |
    curl -X POST $API_URL/containers \
      -H "Content-Type: application/json" \
      -d '{"name":"${{ env.CONTAINER_NAME }}"}'
```

### Monitoring Integration
```bash
# Health check for monitoring
curl -f http://localhost:8080/health || exit 1
```

## Troubleshooting

**Port already in use:**
```bash
# Find process using port
lsof -ti:8080

# Kill it
lsof -ti:8080 | xargs kill -9

# Or change port in main.go
```

**Database connection fails:**
- Check PostgreSQL is running: `sudo systemctl status postgresql`
- Verify credentials with: `psql -U minirun -d minirun`
- API automatically falls back to file storage if DB unavailable

**Permission denied accessing containers:**
- Check file permissions: `ls -la containers/`
- Ensure user has read/write access
- Verify RuntimeBinary path is correct

**Certificate errors with HTTPS:**
- Verify certificates exist: `ls /etc/minirun/*.pem`
- Check permissions: `sudo chmod 644 /etc/minirun/cert.pem`
- See SSL/TLS guide for detailed troubleshooting

## Security Considerations

**Current implementation:**
- No authentication (development only)
- Input validation on all endpoints
- SQL injection prevention (parameterized queries)
- Path traversal protection

**For production, add:**
- JWT or OAuth authentication
- API rate limiting
- Request size limits
- Audit logging
- Role-based access control

## Performance

- Average response time: <5ms (file storage), <10ms (database)
- Concurrent request handling via Go goroutines
- Connection pooling reduces database overhead
- Efficient JSON serialization

## Dependencies
```go
require (
    github.com/gorilla/mux v1.8.1          // HTTP router
    github.com/lib/pq v1.10.9              // PostgreSQL driver
)
```

All dependencies managed via Go modules (`go.mod`).

---

**Part of MiniRun Container Runtime** - Educational container orchestration system