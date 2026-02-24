![banner](https://github.com/NeoVectorX/NeoMoonlight/blob/main/NeoMoonlight-Banner3.png)

# Neo Moonlight (Vision Pro XrOS Fork)

[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://github.com/NeoVectorX/NeoMoonlight/blob/vision-testflight/LICENSE.txt) [![TestFlight](https://img.shields.io/badge/TestFlight-Join%20Beta-orange.svg)](https://testflight.apple.com/join/maak7yCK)

**Neo Moonlight** is a community‑fork of [RikuKunMS2's moonlight-ios-vision](https://github.com/RikuKunMS2/moonlight-ios-vision) and the original [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) project, enhanced specifically for the Apple Vision Pro.

---

## 🚀 Neo Moonlight v12.0 - Plato Edition
**Release Date:** February 2026

### 🌟 New Feature: SharePlay Co-op
* **Couch Co-op:** Added support for playing couch co-op games with a friend via SharePlay.
    * *Note: Please read the co-op instructions in the User Guide first. Hiccups or bugs may occur as this is highly experimental.*


### 🕹️ Controls & Input
* **Gaze & Touch:**
    * Added Gaze/Touch Control to both **Curved** and **Flat** Display modes.
    * Added **Gaze Control Cursor Adjustment** in settings (for minor offset corrections).
    * Added option to choose preferred cursor control method (Gaze vs. Touch).
* **Keyboard Support:**
    * **Flat Mode:** Added full keyboard support.
    * **Curved Mode:** Added keyboard support via an input bar located below the screen (required due to immersive mode limitations).
* **Controller Features:**
    * Added PS5 controller vibration support.
    * **New Toggle:** Added a "Gaze Control / Screen Move / Controller Mode" toggle for curved display.
        * *Why?* To avoid conflicts between screen interaction and gaze control. **Note:** Controller mode must be enabled for Bluetooth gamepads to function.

### 🖥️ Display & Immersion
* **Lighting & Environments:**
    * Added **5 new 360° environments**.
    * Added ability to **hide hands** in 360° environments.
    * Added a Lighting Selection Menu.
    * Added **'Reactive' Lighting Presets** (V1, V2, and Starfield) that dynamically adjust lighting based on screen content.
* **Flat Display Mode:**
    * Added **3D SBS (Side-by-Side)** support.
* **Visual Tweaks:**
    * Renamed "Renderer" to **Display Mode** in settings.
    * Reorganized screen resolutions and categorized them by aspect ratio.

### 🛠️ Quality of Life & Fixes
* **Main Menu:** Reorganized layout for improved accessibility and workflow.
* **Quick Resets:** Added long press (pinch hold) to Dimming, Tilt, and Environment icons to instantly reset to default.
* **Performance:**
    * Fixed cursor jitter in curved display mode.
    * Fixed a memory leak issue.
    * Mic Streamer compatibility mode in settings.
    * Various bug fixes.
   

---

## 📥 Getting Started

### Install via TestFlight
Ready to test the latest features? Click the link below to install the build on your Vision Pro.

[![Join Beta](https://img.shields.io/badge/TestFlight-Download_Now-black?style=for-the-badge&logo=apple)](https://testflight.apple.com/join/maak7yCK)

---

## 🏆 Credits & Contributors

Neo Moonlight builds upon the excellent work of the Moonlight streaming community. This project is a modified fork with enhanced visionOS gaming features and UI improvements.

### Based On
* [Moonlight Game Streaming Project](https://moonlight-stream.org/) - The original open-source game streaming solution.
* [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) - iOS/tvOS implementation.
* [Moonlight visionOS Port](https://github.com/RikuKunMS2/moonlight-ios-vision/tree/vision-testflight) - Initial visionOS adaptation.

### Core Contributors

#### Original Moonlight Team
* **cgutman** - Lead developer of Moonlight iOS
* **dwaxemberg**, **ascagnel**, and [many others](https://github.com/moonlight-stream/moonlight-ios/graphs/contributors)

#### VisionOS Port & Foundation
* **RikuKunMS2** - Initial visionOS port and foundation work
* **tht7** - Curved screen feature implementation
* **shinyquagsire23** - Performance optimizations and bandwidth improvements
* **JFuellem** - Controller crash fixes
* **linggan-ua** - Various fixes, black screen resume fix

### Special Thanks
* **skynet01** - Beta testing, suggestions, and valuable feedback.
* **Delt31** - Beta testing and feature suggestions.

*And many others in the community who contributed through issues, testing, and feedback.*

---

## 📄 License

This project is licensed under the **GPL-3.0 License**, the same license as the original Moonlight project. This means the source code is freely available and can be modified and redistributed under the same terms.

[View License](https://github.com/NeoVectorX/NeoMoonlight/blob/v12.0-clean-history/LICENSE.txt)
