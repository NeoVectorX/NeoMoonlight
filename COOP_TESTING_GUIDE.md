# SharePlay Co-op Testing Guide

## 🎮 What Was Implemented

Remote co-op multiplayer via SharePlay - two Vision Pro users can play local co-op games together by both streaming from the same gaming PC.

---

## ✅ Pre-Testing Checklist

### On Your Gaming PC:
1. **Sunshine is running** and accessible on your network
2. **Multiple connections enabled** in Sunshine settings (if there's a limit setting)
3. **Local co-op game installed** (recommended: It Takes Two, Overcooked 2, Cuphead)

### On Both Vision Pros:
1. **Both devices on same WiFi** (for initial testing)
2. **Latest build installed** on both devices
3. **FaceTime enabled** and signed in with Apple ID
4. **Both devices paired** with your gaming PC (normal Moonlight pairing)

---

## 🚀 How to Test

### Step 1: Start FaceTime Call
- Start a FaceTime call between the two Vision Pros
- Keep the call active throughout testing

### Step 2: Start Co-op Session (Vision Pro #1 - Host)
1. Open Moonlight app
2. You'll see your gaming PC with **two buttons**: "Connect" and "Co-op"
3. Tap the **"Co-op"** button (violet/purple color)
4. Select the co-op game you want to play
5. Tap **"Start Co-op Session"**
6. SharePlay invitation should appear
7. Send invitation to Vision Pro #2

### Step 3: Join Session (Vision Pro #2 - Guest)
1. Accept the SharePlay invitation
2. Moonlight app should open automatically
3. You'll see "Joining co-op session" screen
4. App will auto-pair with the gaming PC (using shared certificates)
5. Game should auto-launch

### Step 4: Play Together!
- Vision Pro #1: Controller slot 0 (Player 1)
- Vision Pro #2: Controller slot 1 (Player 2)
- Both should see the same game
- Both controllers should work independently
- **Look for the "2P" badge** in the top controls (fades with other icons)

---

## 🔍 What to Watch For

### Expected Behavior:
✅ Both devices stream video from the same PC
✅ Controllers work independently (not mirrored)
✅ Audio plays on both devices (game audio + FaceTime voice)
✅ Display modes can be different (one curved, one flat)
✅ Resolution/HDR can be independent

### Potential Issues to Test:

1. **Frame Rate Mismatch**
   - If guest has different frame rate setting, should show error
   - Both must have matching frame rate (60fps, 90fps, or 120fps)

2. **Connection Failures**
   - If Sunshine blocks second connection, will show connection error
   - Check Sunshine logs for "maximum connections reached"

3. **Controller Assignment**
   - Verify Player 1's controller controls Player 1 in-game
   - Verify Player 2's controller controls Player 2 in-game
   - In-game, check controller indicators/player slots

4. **Disconnect Handling**
   - Tap "Disconnect" button on one device
   - Other device should continue streaming (solo)
   - Or both disconnect if co-op session ends

5. **Reconnection**
   - After disconnecting, try starting another co-op session
   - Guest should auto-connect without re-pairing
   - Check if guest's device has the PC saved as "🎮 Co-op: [Your Name]'s PC"

---

## 🐛 Known Limitations (MVP)

- **2 players max** (can expand to 4 later)
- **Frame rate must match** between players
- **No in-game voice chat** (use FaceTime audio)
- **Controller disconnect notification** not yet implemented
- **Sunshine connection limit detection** shows generic error

---

## 📝 Testing Scenarios

### Scenario 1: Basic Co-op
1. Start FaceTime
2. Host starts co-op
3. Guest joins
4. Both play together
5. Host disconnects
6. Verify guest can continue solo

### Scenario 2: Second Session
1. Complete Scenario 1
2. Start new FaceTime call
3. Host starts co-op again (same or different game)
4. Guest should auto-join faster (PC already paired)

### Scenario 3: Display Mode Mix
1. Host uses Curved Display
2. Guest uses Flat Display
3. Verify both work correctly

### Scenario 4: Quality Settings
1. Host at 4K HDR 120fps
2. Guest at 1080p SDR 120fps (same frame rate)
3. Verify both stream correctly at different qualities

---

## 🎬 How to Record Issues

If something breaks:
1. Check console logs on both devices
2. Look for `[CoopCoordinator]`, `[CoopSetup]` log messages
3. Note the exact step where it failed
4. Check Sunshine logs on gaming PC

---

## 🏷️ Rollback

If this feature causes issues:
```bash
git checkout Before-SharePlay-Coop
```

This will revert all co-op changes and restore the app to the previous working state.
