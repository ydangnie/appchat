const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const multer = require('multer');
const path = require('path');
const cors = require('cors');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

app.use(cors());
app.use(express.json());

app.get('^/$', (req, res) => {
  res.send(`
    <html>
      <body style="font-family: sans-serif; text-align: center; margin-top: 50px;">
        <h2>🚀 Backend Server is Running!</h2>
        <p>This is a Node.js API server for the Flutter Chat App.</p>
        <p>Please use the Flutter application to interact with it.</p>
      </body>
    </html>
  `);
});

const UPLOADS_DIR = path.join(__dirname, 'uploads');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR);
}
app.use('/uploads', express.static(UPLOADS_DIR));

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOADS_DIR),
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});
const upload = multer({ storage });

// In-memory data store
let users = []; 
// each user: { id: string, username: string, isOnline: boolean, socketId: string|null }
let messages = [];
// each message: { id: string, fromId: string, toId: string, type: 'text'|'image'|'video', content: string, timestamp: number }

app.post('/api/login', (req, res) => {
  const { username } = req.body;
  if (!username) return res.status(400).json({ error: 'Username required' });
  
  let user = users.find(u => u.username === username);
  if (!user) {
    user = { id: Date.now().toString(), username, isOnline: false, socketId: null };
    users.push(user);
    console.log(`Registered new user: ${username} (ID: ${user.id})`);
  }
  res.json(user);
});

app.get('/api/search', (req, res) => {
  const { q, currentUserId } = req.query;
  if (!q) return res.json([]);
  
  const results = users.filter(u => 
    u.username.toLowerCase().includes(q.toLowerCase()) && 
    u.id !== currentUserId
  );
  res.json(results);
});

// Lấy danh sách lịch sử nhắn tin để test mượt hơn
app.get('/api/messages/:otherUserId', (req, res) => {
  const currentUserId = req.headers['user-id'];
  const otherUserId = req.params.otherUserId;
  
  const thread = messages.filter(m => 
    (m.fromId === currentUserId && m.toId === otherUserId) ||
    (m.fromId === otherUserId && m.toId === currentUserId)
  );
  res.json(thread);
});

// Upload endpoint
app.post('/api/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  
  // Endpoint trả về URL của file để sử dụng trong Chat app
  const fileUrl = `/uploads/${req.file.filename}`;
  console.log(`File uploaded: ${fileUrl}`);
  res.json({ url: fileUrl });
});

// Socket.IO event handling
io.on('connection', (socket) => {
  console.log('🔗 Client connected: ', socket.id);
  let currentUserId = null;

  socket.on('register', (userId) => {
    currentUserId = userId;
    const user = users.find(u => u.id === userId);
    if (user) {
      user.socketId = socket.id;
      user.isOnline = true;
      console.log(`✅ User ${user.username} registered realtime with socket ${socket.id}`);
      io.emit('user_status', { userId: user.id, isOnline: true });
    }
  });

  socket.on('send_message', (data) => {
    // data format: { toId, type: 'text'|'image'|'video', content }
    if (!currentUserId) return;
    
    const currentUser = users.find(u => u.id === currentUserId);
    
    const msg = {
      id: Date.now().toString() + Math.random().toString(36).substring(7),
      fromId: currentUserId,
      fromName: currentUser ? currentUser.username : 'Unknown',
      toId: data.toId,
      type: data.type,
      content: data.content,
      timestamp: Date.now()
    };
    messages.push(msg);

    // Phát tin nhắn ngay cho người nhận nếu họ đang online
    const recipient = users.find(u => u.id === data.toId);
    if (recipient && recipient.socketId) {
      io.to(recipient.socketId).emit('receive_message', msg);
    }
    
    // Gửi xác nhận lại cho người gửi
    socket.emit('message_sent', msg);
  });

  socket.on('delete_message', (data) => {
    // data: { msgId, toId }
    messages = messages.filter(m => m.id !== data.msgId);
    
    // Báo cho người nhận
    const recipient = users.find(u => u.id === data.toId);
    if (recipient && recipient.socketId) {
      io.to(recipient.socketId).emit('message_deleted', { msgId: data.msgId });
    }
  });

  socket.on('edit_message', (data) => {
    // data: { msgId, newContent, toId }
    const msg = messages.find(m => m.id === data.msgId);
    if (msg && msg.fromId === currentUserId && msg.type === 'text') {
      msg.content = data.newContent;
      
      const recipient = users.find(u => u.id === data.toId);
      if (recipient && recipient.socketId) {
        io.to(recipient.socketId).emit('message_edited', { msgId: data.msgId, newContent: data.newContent });
      }
      // Ack to sender
      socket.emit('message_edited', { msgId: data.msgId, newContent: data.newContent });
    }
  });

  // Typing indicators
  socket.on('typing', (data) => {
    // data: { toId }
    const recipient = users.find(u => u.id === data.toId);
    if (recipient && recipient.socketId) {
      io.to(recipient.socketId).emit('user_typing', { fromId: currentUserId });
    }
  });

  socket.on('stop_typing', (data) => {
    const recipient = users.find(u => u.id === data.toId);
    if (recipient && recipient.socketId) {
      io.to(recipient.socketId).emit('user_stop_typing', { fromId: currentUserId });
    }
  });

  socket.on('disconnect', () => {
    if (currentUserId) {
      const user = users.find(u => u.id === currentUserId);
      if (user) {
        user.isOnline = false;
        user.socketId = null;
        console.log(`❌ User ${user.username} disconnected`);
        io.emit('user_status', { userId: user.id, isOnline: false });
      }
    }
  });
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`🚀 Node Chat Server is running on http://localhost:${PORT}`);
});
