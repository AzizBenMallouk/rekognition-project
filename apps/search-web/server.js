require('dotenv').config();

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const AWS = require('aws-sdk');
const crypto = require('crypto');
const multer = require('multer');
const bodyParser = require('body-parser');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const upload = multer({ storage: multer.memoryStorage() });

const region = process.env.AWS_REGION || 'us-east-1';
AWS.config.update({ region });

const s3 = new AWS.S3();

const SEARCH_BUCKET = process.env.SEARCH_BUCKET; // <-- plus de valeur hardcodée

if (!SEARCH_BUCKET) {
  console.warn('WARNING: SEARCH_BUCKET is not set in env');
}

app.use(express.static('public'));
app.use(bodyParser.json());

// Socket.IO
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  socket.emit('socketId', socket.id);
});

/**
 * POST /search (multipart/form-data: photo + socketId)
 */
app.post('/search', upload.single('photo'), async (req, res) => {
  try {
    const socketId = req.body.socketId;
    if (!socketId) {
      return res.status(400).json({ error: 'Missing socketId' });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'Missing image file' });
    }
    if (!SEARCH_BUCKET) {
      return res.status(500).json({ error: 'SEARCH_BUCKET not configured' });
    }

    const originalName = req.file.originalname || 'photo.jpg';
    const ext = originalName.includes('.') ? originalName.substring(originalName.lastIndexOf('.')) : '.jpg';
    const rand = crypto.randomBytes(8).toString('hex');
    const key = `search/${socketId}/${Date.now()}-${rand}${ext}`;

    await s3.putObject({
      Bucket: SEARCH_BUCKET,
      Key: key,
      Body: req.file.buffer,
      ContentType: req.file.mimetype || 'image/jpeg',
    }).promise();

    console.log(`Uploaded to s3://${SEARCH_BUCKET}/${key}`);

    return res.json({ status: 'uploaded', key });
  } catch (err) {
    console.error('Error in /search:', err);
    return res.status(500).json({
      error: String(err.message || err),
      name: err.name || undefined,
      code: err.code || undefined,
    });
  }
});

/**
 * Lambda -> POST /lambda-result
 */
app.post('/lambda-result', (req, res) => {
  const { socketId, people } = req.body || {};

  console.log('Lambda result received:', req.body);

  if (!socketId) {
    return res.status(400).json({ error: 'Missing socketId' });
  }

  io.to(socketId).emit('searchResult', {
    people: Array.isArray(people) ? people : [],
  });

  return res.json({ status: 'ok' });
});

const port = process.env.PORT || 3000;
server.listen(port, () => {
  console.log(`Face search Socket.IO server running on port ${port}`);
});
