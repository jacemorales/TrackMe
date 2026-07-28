const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const PORT = process.env.PORT || 3000;

// Initialize Express app
const app = express();

// Apply middleware
app.use(cors());
app.use(express.json());

// Basic health check route
app.get('/', (req, res) => {
  res.status(200).json({ status: 'OK', message: 'TrackMe real-time location server is running.' });
});

// Create HTTP server
const server = http.createServer(app);

// Initialize Socket.io with permissive CORS settings
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Manage socket connections
io.on('connection', (socket) => {
  console.log(`[Socket Connected] Socket ID: ${socket.id}`);

  // Listen for incoming location coordinates from a tracking device
  socket.on('locationUpdate', (data) => {
    /*
      Expected telemetry schema:
      {
        latitude: number,
        longitude: number,
        speed: number | null,
        heading: number | null,
        timestamp: number,
        deviceId: string
      }
    */
    console.log(`[Location Update] Device: ${data.deviceId || 'Unknown'}, Lat: ${data.latitude}, Lng: ${data.longitude}`);

    // Broadcast the updated coordinates immediately to all connected clients
    io.emit('locationBroadcast', data);
  });

  // Handle client disconnection
  socket.on('disconnect', () => {
    console.log(`[Socket Disconnected] Socket ID: ${socket.id}`);
  });
});

// Start listening on server port
server.listen(PORT, () => {
  console.log(`[Server Running] Listening on port ${PORT}`);
});
