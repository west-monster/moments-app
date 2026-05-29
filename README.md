# Moments App

A personal iOS app to preserve and relive your most meaningful memories — photos, messages, and notes — all stored privately on your device.

## Features

- **Memory feed** — A beautiful scroll feed showing all your memories sorted by order, with smooth animations and an editorial design.
- **Add memories** — Pick up to 6 photos per memory, write a message and notes, set a date, and tag the moment.
- **Tags** — Filter memories by category: Travel, Family, Friends, Couple, Celebration, or Adventure.
- **Photo crop** — Drag to reposition the main photo focus point directly in the creation form.
- **Detail view** — Full-screen swipeable detail view for each memory.
- **Edit & delete** — Update any memory at any time.
- **PDF export** — Generate a beautifully formatted PDF album of all your memories to share or archive.
- **Home screen widget** — A widget that displays a random memory photo directly on your home screen, powered by App Groups shared storage.
- **Splash screen** — A custom welcome screen on first launch, and a lighter returning-user version on subsequent opens.
- **Fully local** — All data stays on your device. No accounts, no cloud sync, no tracking.

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Persistence | SwiftData |
| Image storage | Local file system (`Documents/Images/`) |
| Metadata | JSON export/import (`Documents/Metadata/memories.json`) |
| Widget | WidgetKit + App Groups |
| PDF generation | UIGraphicsPDFRenderer |
| Photo picker | PhotosUI |

## Project Structure

```
Moments App/
├── V App/                  # Main app target
│   ├── V_AppApp.swift      # App entry point & SwiftData container
│   ├── ContentView.swift   # Main feed, filtering, and navigation
│   ├── Item.swift          # Memory model & MemoryTag enum
│   ├── LocalStore.swift    # Image & metadata persistence layer
│   ├── AddMemoryView.swift # Add memory form
│   ├── EditMemoryView.swift# Edit memory form
│   ├── MemoryCardView.swift# Feed card component
│   ├── MemoryDetailView.swift # Full-screen detail & swipe view
│   ├── ShareCardView.swift # Shareable card for a memory
│   ├── ExportAlbumView.swift # PDF export UI
│   ├── PDFExporter.swift   # PDF generation engine
│   ├── SplashView.swift    # Animated splash screen
│   ├── Theme.swift         # Design system (colors, fonts, components)
│   ├── WidgetDataProvider.swift # Syncs data to widget via App Groups
│   └── Localizable.xcstrings   # Localized strings
├── Memory Widget/          # Widget extension target
│   └── MemoryWidget.swift  # WidgetKit timeline & view
└── Shared/
    └── WidgetMemoryData.swift  # Shared data model between app & widget
```

## Requirements

- iOS 17+
- Xcode 15+

## Getting Started

1. Clone the repo
2. Open `V App.xcodeproj` in Xcode
3. Select your development team in the project signing settings
4. Build and run on a simulator or device
