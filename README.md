# Tree Law Zoo

Smart Restaurant Super App - Flutter Application

## Overview

Tree Law Zoo is a Flutter-based mobile application for restaurant and medical services, featuring real-time location tracking and social authentication.

## Features

- 🏠 Home Dashboard with map background
- 🔐 Social Login (Google, Facebook, Apple, Line, TikTok)
- 📍 Real-time Location Tracking via WebSocket
- 🗺️ Interactive Maps (OpenStreetMap)
- 🎨 Modern UI with custom design system
- 🎥 Video Upload and Streaming (Bunny.net + FFmpeg)

## Getting Started

### Quick Setup

For **Client Machines** (เครื่องที่ 2):

```bash
# Clone repository
git clone <repository-url>
cd tree_law_zoo

# Run setup script
chmod +x setup-new-machine.sh
./setup-new-machine.sh
```

For **Database Server** (เครื่องหลัก):

See [SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md) for detailed instructions.

### Manual Setup

See detailed setup guides:

- **[SETUP_NEW_MACHINE.md](SETUP_NEW_MACHINE.md)** - คู่มือสำหรับ Client Machine (เครื่องที่ 2)
- **[SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md)** - คู่มือสำหรับ Database Server (เครื่องหลัก)

## Architecture

### Remote Database Setup

```
┌─────────────────────┐         ┌──────────────────────┐
│  Client Machine     │         │  Database Server     │
│  (เครื่องที่ 2)      │         │  (เครื่องหลัก)        │
│                     │         │                      │
│  Flutter App        │         │  PostgreSQL          │
│  WebSocket Server   │────────▶│  Port: 5432          │
│                     │ Network │  Database: tree_law_ │
│  .env:              │         │  User: tree_law_zoo_ │
│  DB_HOST=192.168... │         │  zoo_user            │
└─────────────────────┘         └──────────────────────┘
              │                            │
              │                            │
              └────────────────────────────┘
              Shared Database
```

## Prerequisites

### For Client Machine

- Flutter SDK (v3.10.0+)
- Node.js (v14+)
- Java 17 (for Android build)
- PostgreSQL Client (optional)

### For Database Server

- PostgreSQL (v14+)
- macOS (recommended)
- External Drive (optional)

## Project Structure

```
tree_law_zoo/
├── lib/
│   ├── core/              # Core utilities (colors, themes, constants)
│   ├── features/          # Feature modules
│   │   ├── auth/          # Authentication
│   │   └── home/          # Home page
│   ├── services/          # Services (WebSocket, Location, etc.)
│   └── shared/            # Shared widgets
├── websocket-server/      # Node.js WebSocket server
│   ├── server.js          # Main server file
│   ├── database.sql       # Database schema
│   └── .env.example       # Environment template
├── android/               # Android configuration
├── ios/                   # iOS configuration
├── macos/                 # macOS configuration
└── web/                   # Web configuration
```

## Development

### Run Flutter App

```bash
# Web
flutter run -d chrome

# Android
flutter run -d android

# iOS
flutter run -d ios

# macOS
flutter run -d macos
```

### Start WebSocket Server

```bash
cd websocket-server
npm start
```

### Test Database Connection

```bash
cd websocket-server
./test-remote-db.sh
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```env
DB_HOST=<Database_Server_IP>
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=<password>
DB_PORT=5432
PORT=3000
```

## Documentation

- [SETUP_NEW_MACHINE.md](SETUP_NEW_MACHINE.md) - Client Machine setup guide
- [SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md) - Database Server setup guide
- [VIDEO_SYSTEM_PLAN.md](VIDEO_SYSTEM_PLAN.md) - Video upload and streaming system plan
- [websocket-server/README.md](websocket-server/README.md) - WebSocket Server documentation
- [websocket-server/SETUP_GUIDE.md](websocket-server/SETUP_GUIDE.md) - WebSocket Server setup

## Technologies

- **Flutter** - Mobile framework
- **Node.js** - WebSocket server
- **PostgreSQL** - Database
- **Socket.io** - Real-time communication
- **OpenStreetMap** - Maps
- **Bunny.net** - CDN and video storage
- **FFmpeg** - Video transcoding

## Contributing

1. Clone the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[Add your license here]

## Support

For setup issues, refer to:
- [SETUP_NEW_MACHINE.md](SETUP_NEW_MACHINE.md) - Client Machine troubleshooting
- [SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md) - Database Server troubleshooting
