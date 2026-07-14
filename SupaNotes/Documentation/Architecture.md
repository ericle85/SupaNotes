# SupaNotes Architecture Overview

## Core Components

### Canvas Components
- **StrokeInputSource**: UIKit UIView that captures touch events and converts them to StrokePoint objects
- **StrokeEngine**: Manages stroke state, including active strokes and completed strokes
- **StrokeRenderer**: Static utility class that draws strokes using Core Graphics
- **Stroke**: Data model representing a single stroke with points, color, and width

### Integration Layer
- **PencilCanvasView**: UIView that bridges StrokeInputSource with StrokeEngine and StrokeRenderer
- **PencilCanvasController**: ObservableObject that manages the canvas state and integrates with SwiftUI
- **PencilCanvas**: UIViewRepresentable that embeds PencilCanvasView in SwiftUI

### UI Layer
- **ContentView**: SwiftUI view that hosts the main canvas
- **DrawingDemoView**: SwiftUI view that provides a demo interface for handwriting functionality
- **DrawingDemoView**: SwiftUI view that displays stroke count and touch information

## Data Flow

1. **Touch Input**: StrokeInputSource captures touch events from UIKit and converts them to StrokePoints
2. **Stroke Processing**: PencilCanvasView connects input events to StrokeEngine for stroke management
3. **Rendering**: StrokeRenderer draws all strokes using Core Graphics
4. **UI Updates**: PencilCanvasView and PencilCanvasController update the UI through published properties

## SwiftUI/UIKit Integration

The architecture uses a hybrid approach where UIKit components (StrokeInputSource, PencilCanvasView) are embedded within SwiftUI views (ContentView, DrawingDemoView) using UIViewRepresentable protocols. This allows for precise control of touch handling and drawing operations while maintaining the declarative benefits of SwiftUI for layout and state management.

## Handwriting Functionality

The handwriting functionality is implemented through:
- Touch-based input using Apple Pencil and direct touch
- Real-time stroke processing and rendering
- Stroke point data with force, azimuth, and altitude information
- Complete stroke management including begin, extend, end, and cancellation
- Clear and reset capabilities