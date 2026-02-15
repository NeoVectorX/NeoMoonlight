# Mic Button Implementation - Setup Instructions

## ✅ Completed Automatically
- ✅ Created `RemoteMicManager.swift` - Network bridge to Mic Streamer on port 5006
- ✅ Created `FloatingMicButton.swift` - Draggable UI with NeoMoonlight theme  
- ✅ Updated `TemporarySettings.swift` - Added `showMicButton` property
- ✅ Updated `SettingsView.swift` - Added toggle in "Controller & Audio" section  
- ✅ Updated `DataManager.h` and `DataManager.m` - Added `showMicButton` parameter
- ✅ Info.plist already has `NSLocalNetworkUsageDescription`

## 🔧 Manual Steps Required

### Step 1: Add Files to Xcode Project

1. Open `Moonlight.xcodeproj` in Xcode
2. In Project Navigator, right-click on **"Moonlight Vision"** folder
3. Select **File → Add Files to "NeoMoonlight"...**
4. Navigate to and select these files:
   - `Moonlight Vision/RemoteMicManager.swift`
   - `Moonlight Vision/FloatingMicButton.swift`
5. Make sure **"Copy items if needed"** is **UNCHECKED**
6. Make sure **"Add to targets"** includes: **Moonlight Vision** (checked)
7. Click **Add**

### Step 2: Update Core Data Model

1. In Project Navigator, open `Limelight.xcdatamodeld`
2. Select the **current model version** (likely "Moonlight v1.10")
3. In the left sidebar, select the **Settings** entity
4. In the Attributes section, click the **+** button to add a new attribute:
   - **Attribute**: `showMicButton`
   - **Type**: `Boolean`
   - **Optional**: ✓ (checked)
   - **Default Value**: `NO`
5. Save (⌘+S)

### Step 3: Add Mic Button to CurvedDisplayStreamView.swift

Open `Moonlight Vision/CurvedDisplayStreamView.swift` and make these changes:

#### A. Add State Variables (around line 317, after `tutorialCardWidthMeters`)