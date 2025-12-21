# Fastlane Setup & Usage Guide

This project uses [fastlane](https://fastlane.tools) to automate iOS app deployment to TestFlight and the App Store.

## 📋 Table of Contents
- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)
- [Available Commands](#available-commands)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **Ruby & Bundler** (already installed ✅)
   - Ruby 3.3.5
   - Bundler 2.5.16

2. **Xcode**
   - Xcode 15+ with command line tools
   - Valid Apple Developer account

3. **App Store Connect Access**
   - Access to your app in App Store Connect
   - Team ID and App Store Connect Team ID

---

## First-Time Setup

### Step 1: Install Dependencies

```bash
cd /Users/biubiu/projects/dogetionary/ios/dogetionary
bundle install
```

### Step 2: Configure App Store Connect API Key (Recommended)

This is the **modern, recommended way** to authenticate with App Store Connect (no 2FA prompts!).

1. **Generate API Key**:
   - Go to https://appstoreconnect.apple.com/access/api
   - Click **"+"** to create a new key
   - Name: `fastlane-ci` (or any name you prefer)
   - Access: Select **"App Manager"** role
   - Click **"Generate"**

2. **Download the Key**:
   - Download the `.p8` file (**IMPORTANT**: You can only download it once!)
   - Note the **Issuer ID** (e.g., `69a6de12-b123-47e3-e053-5b8c7c11a4d1`)
   - Note the **Key ID** (e.g., `2X9R4HXF34`)

3. **Store the Key Securely**:
   ```bash
   # Create a secure directory (NOT in the project repo!)
   mkdir -p ~/.private_keys

   # Move the downloaded key there
   mv ~/Downloads/AuthKey_2X9R4HXF34.p8 ~/.private_keys/

   # Set restrictive permissions
   chmod 600 ~/.private_keys/AuthKey_*.p8
   ```

4. **Configure Fastlane**:

   Edit `fastlane/Appfile` and add:
   ```ruby
   app_identifier("com.tianzhistudio.dogetionary.dogetionary")

   # Replace with your Team ID from https://developer.apple.com/account
   team_id("YOUR_TEAM_ID")
   itc_team_id("YOUR_ITC_TEAM_ID") # Usually same as team_id

   # App Store Connect API Key (recommended)
   api_key_path("~/.private_keys/AuthKey_2X9R4HXF34.p8")
   ```

   **Or** use environment variables (better for CI/CD):
   ```bash
   # Add to ~/.zshrc or ~/.bash_profile
   export APP_STORE_CONNECT_API_KEY_PATH=~/.private_keys/AuthKey_2X9R4HXF34.p8
   export APP_STORE_CONNECT_API_KEY_KEY_ID=2X9R4HXF34
   export APP_STORE_CONNECT_API_KEY_ISSUER_ID=69a6de12-b123-47e3-e053-5b8c7c11a4d1
   ```

### Step 3: Find Your Team IDs

```bash
# Run this to see your Team IDs
bundle exec fastlane run spaceship_stats
```

Or manually:
- **Team ID**: https://developer.apple.com/account → Membership → Team ID
- **ITC Team ID**: https://appstoreconnect.apple.com/access/users → usually same as Team ID

---

## Available Commands

### 🔨 Build Only (No Upload)

```bash
bundle exec fastlane build
```
Builds the app without uploading anywhere. Useful for testing build process.

---

### 🚀 Deploy to TestFlight (Beta)

```bash
bundle exec fastlane beta
```

**What it does:**
1. Automatically increments build number
2. Builds the app in Release mode
3. Uploads to TestFlight
4. Waits for processing to complete

**After running:**
- Check TestFlight in App Store Connect
- Add testers and submit for beta testing

---

### 📱 Deploy to App Store (Production)

```bash
bundle exec fastlane release
```

**What it does:**
1. Increments build number
2. Builds the app in Release mode
3. Uploads to App Store Connect
4. **Does NOT auto-submit for review** (you must do this manually in App Store Connect)

**To auto-submit for review:**
Edit `fastlane/Fastfile` and change:
```ruby
submit_for_review: true  # Change from false to true
```

---

### 📊 Check Version

```bash
bundle exec fastlane version
```
Shows current version and build number.

---

### 🔢 Bump Build Number

```bash
bundle exec fastlane bump
```
Increments build number without building the app.

---

## Code Signing

Fastlane will use Xcode's automatic code signing by default.

**For manual code signing**, consider using [fastlane match](https://docs.fastlane.tools/actions/match/):
```bash
bundle exec fastlane match init
```

---

## Troubleshooting

### Error: "Could not find Xcode project"

Make sure you're in the correct directory:
```bash
cd /Users/biubiu/projects/dogetionary/ios/dogetionary
```

### Error: "Authentication failed"

1. Make sure your API key is correctly configured in `Appfile`
2. Check that the `.p8` file path is correct
3. Verify your Team ID is correct

### Error: "No code signing identity found"

1. Open Xcode
2. Go to **Preferences → Accounts**
3. Add your Apple ID if not already added
4. Download certificates: Click your team → **Download Manual Profiles**

### Build number conflicts

If TestFlight already has a higher build number:
```bash
# Manually set build number
agvtool new-version -all 123
```

---

## 📚 Additional Resources

- [Fastlane Documentation](https://docs.fastlane.tools)
- [Fastlane Actions](https://docs.fastlane.tools/actions)
- [App Store Connect API](https://developer.apple.com/app-store-connect/api/)

---

## 🔒 Security Reminders

- ⚠️ **NEVER** commit `.p8` files to git
- ⚠️ **NEVER** commit passwords or API keys
- ✅ Store API keys in `~/.private_keys/` (outside the repo)
- ✅ Use environment variables for CI/CD
- ✅ Add `*.p8` to `.gitignore` (already done ✅)

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `bundle exec fastlane build` | Build only (no upload) |
| `bundle exec fastlane beta` | Upload to TestFlight |
| `bundle exec fastlane release` | Upload to App Store |
| `bundle exec fastlane version` | Show version/build |
| `bundle exec fastlane bump` | Increment build number |

---

**Need help?** Check the [Fastlane documentation](https://docs.fastlane.tools) or run:
```bash
bundle exec fastlane --help
```
