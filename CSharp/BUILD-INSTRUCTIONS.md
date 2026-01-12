# How to Build the C# POC Without Installing Anything

This document explains how to get a ready-to-run EXE without installing Visual Studio or .NET SDK.

---

## ✅ Method 1: Download Pre-Built from GitHub Actions (RECOMMENDED)

**This is the easiest way - no local tools required!**

### Steps:

1. **Push your code to GitHub** (already done if you're reading this on GitHub)

2. **Go to the Actions tab:**
   - Navigate to: https://github.com/anthonyscry/GA-WsusManager/actions
   - Look for "Build C# POC" workflow

3. **Download the artifact:**
   - Click on the most recent successful build (green checkmark ✅)
   - Scroll down to "Artifacts" section
   - Download **"WsusManager-CSharp-POC"** zip file

4. **Extract and run:**
   - Extract the zip file
   - Right-click `WsusManager-v4.0-POC.exe`
   - Select "Run as administrator"
   - Done! No installation needed.

### What You Get:

```
WsusManager-CSharp-POC.zip
├── WsusManager-v4.0-POC.exe      # Single-file EXE (~15-20 MB)
├── README.md                      # POC overview
├── EXECUTIVE-SUMMARY.md           # Migration decision guide
├── POWERSHELL-VS-CSHARP.md        # Comparison document
└── BUILD-INFO.txt                 # Build metadata
```

---

## 🔧 Method 2: Trigger a Manual Build

If the workflow hasn't run yet (or you want to rebuild):

1. Go to: https://github.com/anthonyscry/GA-WsusManager/actions/workflows/build-csharp-poc.yml

2. Click "Run workflow" button (top right)

3. Select branch: `claude/evaluate-csharp-port-RxyW2`

4. Click green "Run workflow" button

5. Wait 2-3 minutes for build to complete

6. Download artifact as described in Method 1

---

## 🚀 Method 3: Automatic Builds on Push

The workflow automatically runs whenever you push changes to:
- Branch: `claude/evaluate-csharp-port-RxyW2`
- Path: `CSharp/**`

So if you modify any C# code and push, a new build will be created automatically!

---

## 📦 What Gets Built

The GitHub Actions workflow:
1. ✅ Restores NuGet packages
2. ✅ Builds the solution (Release configuration)
3. ✅ Runs all unit tests (xUnit)
4. ✅ Publishes as **single-file EXE** with:
   - Self-contained (no .NET runtime required)
   - Compressed (EnableCompressionInSingleFile)
   - Native libraries embedded
   - No debug symbols (smaller size)
5. ✅ Creates distribution package with docs
6. ✅ Uploads as downloadable artifact

---

## 🎯 Benefits of This Approach

| Feature | GitHub Actions | Local Build |
|---------|----------------|-------------|
| **Installation required** | ❌ None | ✅ .NET SDK (500+ MB) |
| **Build time** | 2-3 minutes | 30-60 seconds |
| **Consistent builds** | ✅ Yes (same environment) | ⚠️ Depends on local setup |
| **Artifact retention** | ✅ 30 days | ❌ Manual management |
| **Multiple branches** | ✅ Parallel builds | ❌ One at a time |
| **CI/CD ready** | ✅ Yes | ❌ No |

---

## 📊 Expected EXE Size

- **PowerShell PS2EXE:** 280 KB (requires Scripts/ and Modules/ folders)
- **C# Single-file:** ~15-20 MB (everything embedded, no dependencies)

**Why larger?** The C# EXE includes:
- Full .NET runtime (~12 MB)
- WPF framework (~2 MB)
- Application code (~1 MB)

**Trade-off:** Larger file size, but:
- ✅ True single-file (no folder dependencies)
- ✅ No .NET installation required
- ✅ More reliable deployment
- ✅ Faster startup (no PS parsing)

---

## 🔍 Troubleshooting

### "No artifacts found"
- Check if the workflow completed successfully (green checkmark)
- Artifacts are only kept for 30 days
- Trigger a new build using Method 2

### "Build failed"
- Check the workflow logs in Actions tab
- Look for red X next to the run
- Click on the run to see detailed error logs

### "EXE won't run"
- Make sure you're running as Administrator
- Check Windows version (requires Windows 10/11, 64-bit)
- If Windows Defender blocks it, add an exception

---

## 📝 Quick Reference

**GitHub Actions Workflow:** `.github/workflows/build-csharp-poc.yml`

**Trigger conditions:**
- Push to `claude/evaluate-csharp-port-RxyW2` with changes in `CSharp/**`
- Manual trigger via Actions tab
- Workflow dispatch event

**Artifact name:** `WsusManager-CSharp-POC`

**Retention:** 30 days

**Download URL:** https://github.com/anthonyscry/GA-WsusManager/actions

---

## ✅ You're Done!

**No local installation needed. Just download and run!** 🚀

The GitHub Actions workflow handles everything:
- Building
- Testing
- Packaging
- Distribution

Your only task: Download the artifact and run the EXE.

---

**For more information:**
- See `EXECUTIVE-SUMMARY.md` - Should you migrate to C#?
- See `POWERSHELL-VS-CSHARP.md` - Comparison of both implementations
- See `MIGRATION-PLAN.md` - How to do the full migration
