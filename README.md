# 💬 Kryin-Talks (ConnectHub)

Website: [kryintalks.vercel.app](https://kryintalks.vercel.app) (deployment pending).

The current Flutter web client uses Supabase directly. Import this repository in Vercel with the repository root and the **Other** preset; `vercel.json` builds the client. See [deployment instructions](docs/DEPLOYMENT.md).

> **Enterprise Communication Platform — Simplified. Secured. Unlimited.**

![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge&logo=github)
![FastAPI](https://img.shields.io/badge/Backend-FastAPI_0.110.0-009688?style=for-the-badge&logo=fastapi)
![Flutter](https://img.shields.io/badge/Frontend-Flutter_3.x-02569B?style=for-the-badge&logo=flutter)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python)
![Security](https://img.shields.io/badge/Security-JWT_RBAC_ABAC-ff69b4?style=for-the-badge)

**Kryin-Talks** is a self-hosted, enterprise-grade, real-time collaboration and messaging platform designed with a futuristic dark-glass aesthetic, granular permission controls, shareable organization invites, and Discord-inspired communication features.

---

## 🚀 Key Features

### 💬 Real-Time Messaging & Discord-Style Experience
- **Rich Message Cards**: Displays sender name, `@username`, color-coded role badges (`Super Admin`, `Admin`, `Member`), and humanized timestamps (*"Today at 10:45 PM"*, *"Yesterday at 4:12 PM"*).
- **Emoji Reactions**: Interactive reaction pills (👍, ❤️, 🔥, 🎉, 🚀) with live counter updates.
- **Message Pinning 📌**: Pin critical operational messages to the conversation header banner.
- **File Attachments 📎**: Upload and attach documents, code files, and summaries directly in chat.
- **Direct Messages & Group Chats**: Seamless 1-on-1 messaging and group channel support.

---

### 🌐 Channel Access & Visibility Control
Customize channel privacy and visibility based on organization needs:
- 🌐 **Global Channels**: Publicly accessible and searchable by **all** organization members.
- 🔒 **Private Channels**: Restricted visibility accessible **only to invited/added members** and administrators.
- 👁️‍🗨️ **Unlisted Channels**: Hidden from global lists; accessible strictly via direct shareable link.

---

### 👥 Shareable Invites & Organization Directory
- **Shareable Invite Links 🔗**: Generate copyable invite links (`http://localhost:8080/#/invite/...`) for Channels, Groups, Teams, and Departments.
- **User Directory Picker**: Direct search and invite modal powered by `GET /auth/directory`, allowing any member to invite colleagues.
- **Hierarchical Structure**: Organize your enterprise into **Departments** (with parent/child relations), **Teams**, and **Groups**.

---

### 🔔 Interactive Notification System
- **Unread Visual Glow**: Unread notifications feature vibrant pulse badges and highlighted card states.
- **Direct Navigation Button 💬**: Click **"Open Chat"**, **"View Department"**, or **"View Team"** directly inside notifications to jump to the conversation.
- **Bulk Actions**: One-click **"Mark All Read"** and individual notification dismissals.

---

### 🛡️ Admin Security & Management Portal
- **User Administration**: Create admin accounts, modify profiles, and toggle **Suspend / Reactivate** states.
- **Audit Logging**: Comprehensive log of user actions, authentication events, and administrative edits.
- **Instant JSON Backup & Restore**: One-click database backups saved as standalone JSON snapshot files with instant restoration capabilities.

---

## 📊 Pre-Seeded Demo Credentials

### Primary Local Accounts (`.local`):
| Role | Email Address | Username | Password |
| :--- | :--- | :--- | :--- |
| 👑 **Super Admin** | `superadmin@connecthub.local` | `@superadmin` | `SuperAdmin@123` |
| 🛡️ **Admin (Local)** | `admin@connecthub.local` | `@admin` | `Admin@123` |
| 👔 **Manager** | `manager@connecthub.local` | `@manager` | `Manager@123` |
| 👤 **Standard User** | `user@connecthub.local` | `@regularuser` | `User@123` |
| 🚪 **Guest User** | `guestuser@connecthub.local` | `@guestuser` | `Guest@123` |

### Organization Accounts (`.com`):
| Role | Email Address | Username | Password |
| :--- | :--- | :--- | :--- |
| 👑 **Global Admin** | `admin@connecthub.com` | `@admin` | `Admin@123` |
| 👩‍💼 **Engineering Manager** | `alice@connecthub.com` | `@alice` | `Alice@123` |
| 👨‍💻 **Frontend Dev** | `bob@connecthub.com` | `@bob` | `Bob@123` |
| 🎨 **Product Designer** | `charlie@connecthub.com` | `@charlie` | `Charlie@123` |
| 🚀 **Software Engineer** | `diana@connecthub.com` | `@diana` | `Diana@123` |

---

## 🛠️ Technology Stack

```
           ┌──────────────────────────────────────────────┐
           │        Flutter Web App (Port 8080)           │
           │  Riverpod | GoRouter | Dark Glassmorphism    │
           └──────────────────────┬───────────────────────┘
                                  │ REST / WebSockets
                                  ▼
           ┌──────────────────────────────────────────────┐
           │         FastAPI Backend (Port 8000)          │
           │    Python 3.12 | SQLAlchemy | Pydantic v2   │
           └──────────────────────┬───────────────────────┘
                                  │ Async Engine
                                  ▼
           ┌──────────────────────────────────────────────┐
           │   SQLite (Dev) / PostgreSQL 16 (Prod) DB     │
           └──────────────────────────────────────────────┘
```

---

## ⚡ Quick Start Guide

### Prerequisites
- **Python 3.12+**
- **Flutter SDK 3.x+** (for building client)

---

### 1. Launch FastAPI Backend Server

```powershell
# Set database override for local SQLite development
$env:DATABASE_URL_OVERRIDE="sqlite+aiosqlite:///d:/conhub/connecthub.db"

# Start uvicorn server
.venv\Scripts\python.exe -m uvicorn connecthub.main:app --host 0.0.0.0 --port 8000
```
- **API Server:** [http://localhost:8000](http://localhost:8000)
- **Interactive Swagger Docs:** [http://localhost:8000/docs](http://localhost:8000/docs)

---

### 2. Launch Web Client Application

```powershell
# Serve compiled Flutter Web application
python -m http.server 8080 --directory "clients/web/build/web"
```
- **Web App UI:** [http://localhost:8080](http://localhost:8080)

---

## 🔒 Security & Privacy

- **RBAC / ABAC Security**: Granular domain-based permission checks (`channel_management`, `user_management`, `audit_logging`).
- **CORS Protection**: Robust preflight handling for secure cross-origin requests.
- **Data Retention**: Soft-deletion policy across all entities with instant rollback support.

---

## 📄 License

Proprietary — All rights reserved by **Kryin-Talks**.
