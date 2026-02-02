# Setup Without Database (Temporary Solution)

ถ้ายังติดตั้ง PostgreSQL ไม่ได้ สามารถใช้ WebSocket Server โดยไม่ต้องใช้ Database ได้ชั่วคราว

## แก้ไข Server Code

แก้ไขไฟล์ `server.js` เพื่อไม่ใช้ database:

```javascript
// Comment out database operations
// await pool.query(...)
```

หรือใช้ใน-memory storage แทน:

```javascript
// Store locations in memory
const locations = new Map();
```

## วิธีที่ 1: Disable Database (Quick Fix)

แก้ไข `server.js` บรรทัดที่ 73-86:

```javascript
socket.on('location-update', async (data) => {
  const { userId, latitude, longitude, timestamp, accuracy, speed, heading } = data;
  
  try {
    // Skip database save for now
    // await pool.query(...);
    
    const locationData = {
      userId,
      latitude,
      longitude,
      timestamp,
      accuracy,
      speed,
      heading,
    };
    
    // Broadcast location update
    io.to(`user-${userId}`).emit('location-updated', locationData);
    socket.broadcast.emit('location-updated', locationData);
    
    console.log(`Location updated for user ${userId}: ${latitude}, ${longitude}`);
  } catch (error) {
    console.error('Error:', error);
    socket.emit('error', { message: 'Failed to process location' });
  }
});
```

## วิธีที่ 2: Install PostgreSQL

### Option A: Homebrew (Recommended)

```bash
# Install PostgreSQL
brew install postgresql@14

# Start PostgreSQL service
brew services start postgresql@14

# Add to PATH (add to ~/.zshrc)
export PATH="/usr/local/opt/postgresql@14/bin:$PATH"

# Reload shell
source ~/.zshrc

# Verify installation
psql --version
```

### Option B: PostgreSQL.app (GUI)

1. Download from: https://postgresapp.com/
2. Install and start the app
3. Add to PATH:
   ```bash
   sudo mkdir -p /etc/paths.d &&
   echo /Applications/Postgres.app/Contents/Versions/latest/bin | sudo tee /etc/paths.d/postgresapp
   ```

### Option C: Official Installer

1. Download from: https://www.postgresql.org/download/macosx/
2. Run installer
3. Follow installation wizard

## After Installing PostgreSQL

1. Run setup script:
   ```bash
   ./setup-database.sh
   ```

2. Or manually:
   ```bash
   createdb sheserved
   psql -U postgres -d sheserved -f database.sql
   ```

3. Update .env file with correct credentials

4. Restart server:
   ```bash
   npm start
   ```
