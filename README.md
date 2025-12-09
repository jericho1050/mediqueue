# MediQueue

A hospital patient admission system demonstrating the **Queue/Worker pattern** with three services communicating via Redis.

## Architecture

```
[Reception Portal] --POST /admit--> [Triage API] --LPUSH--> [Redis: waiting_room]
                                                                    |
                                                              BRPOP |
                                                                    v
                                                          [Doctor Worker]
                                                                    |
                                                             INSERT |
                                                                    v
                                                            [Postgres: medical_records]
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| reception-portal | 3000 | React frontend for patient admission |
| triage-api | 4000 | Express API that queues patients |
| doctor-worker | - | Python worker that processes patients |
| redis | 6379 | Message queue |
| postgres | 5432 | Database for medical records |

## Quick Start

### Prerequisites

- Docker and Docker Compose installed

### Run the Application

```bash
# Start all services
docker-compose up --build

# Or run in detached mode
docker-compose up --build -d
```

### Access the Application

- **Frontend**: http://localhost:3000
- **API Health Check**: http://localhost:4000/health

### Stop the Application

```bash
docker-compose down

# To also remove volumes (database data)
docker-compose down -v
```

## Usage

1. Open http://localhost:3000 in your browser
2. Enter a patient name and condition
3. Click "Admit Patient"
4. Watch the docker-worker logs to see patient processing:
   ```bash
   docker-compose logs -f doctor-worker
   ```

## Project Structure

```
medi-queue/
├── reception-portal/       # React frontend (Vite)
│   ├── src/
│   │   ├── App.jsx        # Main form component
│   │   ├── index.css      # Styling
│   │   └── main.jsx       # React entry
│   ├── index.html
│   ├── package.json
│   ├── vite.config.js
│   └── Dockerfile
├── triage-api/             # Node.js Express API
│   ├── index.js           # Express server with /admit endpoint
│   ├── package.json
│   └── Dockerfile
├── doctor-worker/          # Python worker
│   ├── worker.py          # Worker script with BRPOP loop
│   ├── requirements.txt
│   └── Dockerfile
├── docker-compose.yml      # Service orchestration
└── README.md
```

## API Endpoints

### POST /admit

Admit a new patient to the waiting queue.

**Request:**
```json
{
  "name": "John Doe",
  "condition": "Headache and fever"
}
```

**Response:**
```json
{
  "message": "Patient admitted successfully",
  "patientId": "550e8400-e29b-41d4-a716-446655440000",
  "position": 1
}
```

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "service": "triage-api",
  "redis": "connected",
  "queueLength": 0,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

## Database Schema

```sql
CREATE TABLE medical_records (
    id SERIAL PRIMARY KEY,
    patient_id VARCHAR(36) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    condition TEXT NOT NULL,
    admitted_at TIMESTAMP NOT NULL,
    treated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Query Medical Records

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres -d mediqueue

# View all records
SELECT * FROM medical_records;

# Exit
\q
```

## Environment Variables

### triage-api
- `PORT` - Server port (default: 4000)
- `REDIS_URL` - Redis connection URL

### doctor-worker
- `REDIS_URL` - Redis connection URL
- `DATABASE_URL` - PostgreSQL connection URL
- `TREATMENT_TIME` - Simulated treatment time in seconds (default: 5)

## Development

### Run Services Individually

```bash
# Redis
docker run -p 6379:6379 redis:7-alpine

# PostgreSQL
docker run -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=mediqueue postgres:15-alpine

# Triage API
cd triage-api
npm install
REDIS_URL=redis://localhost:6379 npm start

# Doctor Worker
cd doctor-worker
pip install -r requirements.txt
REDIS_URL=redis://localhost:6379 DATABASE_URL=postgresql://postgres:postgres@localhost:5432/mediqueue python worker.py

# Reception Portal
cd reception-portal
npm install
npm run dev
```

## How It Works

1. **Patient Admission**: User submits patient info via the React frontend
2. **Queue Entry**: Triage API receives the request, generates a UUID, and pushes patient data to Redis `waiting_room` list using `LPUSH`
3. **Worker Processing**: Doctor Worker uses `BRPOP` (blocking pop) to wait for and consume patients from the queue
4. **Treatment Simulation**: Worker simulates treatment with a configurable delay
5. **Record Storage**: Completed treatment is recorded in PostgreSQL `medical_records` table

This pattern enables:
- **Decoupling**: Frontend and worker don't communicate directly
- **Reliability**: Patients wait in Redis if worker is busy/down
- **Scalability**: Multiple workers can process the same queue
- **Persistence**: Completed records stored permanently in PostgreSQL
