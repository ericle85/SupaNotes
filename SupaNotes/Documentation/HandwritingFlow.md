# Handwriting Functionality Flow

## Touch Event Processing

1. **Touch Begins**: 
   - StrokeInputSource receives touchesBegan event
   - Converts touch to StrokePoint and notifies StrokeEngine
   - StrokeEngine creates new active stroke with first point

2. **Touch Moves**:
   - StrokeInputSource receives touchesMoved event  
   - Converts touch to StrokePoint and notifies StrokeEngine
   - StrokeEngine extends active stroke with new point

3. **Touch Ends**:
   - StrokeInputSource receives touchesEnded event
   - Converts touch to StrokePoint and notifies StrokeEngine
   - StrokeEngine finalizes stroke and adds to completed strokes
   - StrokeRenderer redraws the canvas with updated strokes

4. **Touch Cancelled**:
   - StrokeInputSource receives touchesCancelled event
   - Notifies StrokeEngine to cancel active stroke
   - StrokeEngine clears active stroke without adding to completed strokes

## Data Flow Through Components

1. **StrokePoint Creation**: 
   - Touch location, force, azimuth, and altitude are extracted
   - Points are normalized to screen coordinates

2. **Stroke Management**:
   - StrokeEngine manages active stroke state during drawing
   - StrokeEngine stores completed strokes
   - StrokeEngine handles clear and cancellation operations

3. **Rendering**:
   - StrokeRenderer draws all strokes using Core Graphics
   - StrokeRenderer handles both active and completed strokes
   - Rendering respects stroke properties (color, width, line caps)

## Canvas Update Process

1. **State Change**:
   - Stroke count updated through PencilCanvasController
   - Touch information reported to UI

2. **UI Rendering**:
   - PencilCanvasView calls setNeedsDisplay() on stroke changes
   - draw() method is invoked by UIKit rendering system
   - StrokeRenderer draws all strokes in the engine

3. **Display Refresh**:
   - Core Graphics context is obtained from current drawing context
   - Stroke points are mapped to drawing operations
   - Line drawing with proper stroke properties (cap, join, width)

## Demo Interface Integration

1. **Stroke Count Updates**: 
   - Displays number of completed strokes
   - Updated through PencilCanvasController's published property

2. **Touch Information**:
   - Shows touch type (pencil, direct, etc.)
   - Reports modifier flags (shift key state)
   - Displays touch type information

3. **Debug Injection**:
   - Allows command-line input of touch points
   - Simulates pencil strokes for testing
   - Supports testing without physical device interaction