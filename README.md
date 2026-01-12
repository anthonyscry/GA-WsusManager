
# GA-WsusManager Pro (v3.8.6)

Standalone Portable WSUS Management Suite designed for GA-ASI Lab Environments.

## 🚀 Quick Start (Local Development)

1. **Install Node.js** (v20+ recommended)
2. **Install Dependencies**:
   ```bash
   npm install
   ```
3. **Run in Development Mode**:
   ```bash
   npm start
   ```

## 🛠 Building the Portable EXE

The project is configured with GitHub Actions. Simply push to `main` and download the artifact from the **Actions** tab.

To build manually on your machine:
```bash
npm run build:exe
```
The result will be in the `dist/` folder.

## ⚠️ Troubleshooting Git Push Errors

If you see "Something went wrong" when pushing:
1. Ensure you have a `.gitignore` (added in v3.8.6).
2. If you are behind the GA proxy, configure git:
   ```bash
   git config --global http.proxy http://proxy.ga.com:8080
   ```
3. If you accidentally tracked `node_modules`, clear the cache:
   ```bash
   git rm -r --cached .
   git add .
   git commit -m "fix: apply gitignore"
   git push
   ```

## 🔐 Security Note
Database operations require SQL SA credentials. These are stored in a non-persistent session vault (browser localStorage) and are never sent to external services.
