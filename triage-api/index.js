import express from 'express';
import cors from 'cors';
import { createClient } from 'redis';
import { v4 as uuidv4 } from 'uuid';

const app = express();
const PORT = process.env.PORT || 4000;
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const QUEUE_NAME = 'waiting_room';

// Middleware
app.use(cors());
app.use(express.json());

// Redis client
let redisClient;

async function connectRedis() {
  redisClient = createClient({ url: REDIS_URL });

  redisClient.on('error', (err) => {
    console.error('Redis Client Error:', err);
  });

  redisClient.on('connect', () => {
    console.log('Connected to Redis');
  });

  await redisClient.connect();
}

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    const redisStatus = redisClient?.isReady ? 'connected' : 'disconnected';
    const queueLength = redisClient?.isReady
      ? await redisClient.lLen(QUEUE_NAME)
      : 0;

    res.json({
      status: 'healthy',
      service: 'triage-api',
      redis: redisStatus,
      queueLength,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

// Admit patient endpoint
app.post('/admit', async (req, res) => {
  try {
    const { name, condition } = req.body;

    // Validate input
    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return res.status(400).json({
        error: 'Patient name is required'
      });
    }

    if (!condition || typeof condition !== 'string' || condition.trim().length === 0) {
      return res.status(400).json({
        error: 'Patient condition is required'
      });
    }

    // Create patient record
    const patient = {
      id: uuidv4(),
      name: name.trim(),
      condition: condition.trim(),
      admittedAt: new Date().toISOString()
    };

    // Push to Redis queue
    await redisClient.lPush(QUEUE_NAME, JSON.stringify(patient));

    console.log(`Patient admitted: ${patient.name} (ID: ${patient.id})`);

    res.status(201).json({
      message: 'Patient admitted successfully',
      patientId: patient.id,
      position: await redisClient.lLen(QUEUE_NAME)
    });

  } catch (error) {
    console.error('Error admitting patient:', error);
    res.status(500).json({
      error: 'Failed to admit patient'
    });
  }
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down...');
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

// Start server
async function start() {
  try {
    await connectRedis();

    app.listen(PORT, '0.0.0.0', () => {
      console.log(`Triage API running on port ${PORT}`);
      console.log(`Health check: http://localhost:${PORT}/health`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

start();
