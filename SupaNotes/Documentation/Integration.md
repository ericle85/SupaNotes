# SwiftUI/UIKit Integration Details

## UIViewRepresentable Implementation

### PencilCanvas (UIViewRepresentable)
- Implements `makeUIView` to create PencilCanvasView and establish connections
- Implements `updateUIView` for state synchronization
- Bridges UIKit view to SwiftUI environment

### PencilCanvasView (UIView)
- Inherits from StrokeInputSource for touch handling
- Implements drawing using Core Graphics
- Manages stroke state through StrokeEngine integration
- Provides callbacks for stroke changes and touch reports

## ObservableObject Integration

### PencilCanvasController (ObservableObject)
- Manages state for stroke count and touch information
- Provides clear and injection capabilities
- Connects to PencilCanvasView via weak reference to avoid retain cycles
- Exposes published properties for SwiftUI binding

## State Management Flow

1. **Touch Events Flow**:
   - UIKit touch events → StrokeInputSource → PencilCanvasView → StrokeEngine
   - StrokeEngine updates state → PencilCanvasController receives updates
   - PencilCanvasController updates published properties → SwiftUI views

2. **Rendering Flow**:
   - State changes trigger setNeedsDisplay() calls
   - UIKit rendering system invokes draw() method
   - StrokeRenderer draws all strokes in current context

3. **UI Updates Flow**:
   - Published properties in PencilCanvasController trigger SwiftUI view updates
   - Stroke count, touch information, and other UI elements refresh automatically

## Bridging Components

### Key Connections:
- PencilCanvasController → PencilCanvasView (weak reference to prevent retain cycles)
- PencilCanvasView → StrokeInputSource (inheritance for touch handling)
- PencilCanvasView → StrokeEngine (state management for strokes)
- PencilCanvasView → StrokeRenderer (rendering of strokes)
- StrokeEngine → StrokeRenderer (data flow for rendering)
- PencilCanvasController → SwiftUI Views (published property binding)

## Memory Management

### Safe References:
- Weak references in PencilCanvasController to avoid retain cycles
- Proper cleanup in view lifecycle methods
- No direct strong references between components that could cause circular dependencies

## Performance Considerations

### Rendering:
- Core Graphics drawing is efficient
- Only redraws when necessary through setNeedsDisplay()
- Single-threaded rendering context (main thread)
- Optimized stroke rendering with batch drawing operations

### UI Responsiveness:
- SwiftUI bindings handle automatic updates
- Touch processing happens on main thread
- No blocking operations that would impact UI responsiveness