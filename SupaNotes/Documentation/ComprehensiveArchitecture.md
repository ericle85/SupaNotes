# SupaNotes Comprehensive Architecture

## 1. SwiftUI/UIKit Integration

### Hybrid Architecture Pattern
The application implements a hybrid architecture where SwiftUI and UIKit components work together seamlessly:

- **SwiftUI Layer**: ContentView serves as the main UI entry point, providing declarative layout and state management
- **UIKit Layer**: StrokeInputSource and DrawingCanvas provide low-level touch handling and drawing operations
- **Bridge Pattern**: UIViewRepresentable (PencilCanvas) bridges UIKit components into SwiftUI views

### Component Integration Flow
1. ContentView (SwiftUI) → PencilCanvas (UIViewRepresentable) → DrawingCanvas (UIView)
2. DrawingCanvas → StrokeInputSource (UIKit UIView) for touch handling
3. DrawingCanvas → StrokeEngine for stroke state management
4. DrawingCanvas → StrokeRenderer for Core Graphics drawing operations

## 2. Data Flow Architecture

### Core Data Flow
1. **Input Layer**: StrokeInputSource captures touch events and converts to StrokePoint
2. **Processing Layer**: StrokeEngine manages stroke states (active, completed)
3. **Rendering Layer**: StrokeRenderer draws strokes using Core Graphics
4. **UI Layer**: PencilCanvasController publishes state changes for SwiftUI updates

### Data Flow Details
- **Touch Events** → StrokeInputSource → StrokeEngine → DrawingCanvas → Core Graphics Context
- **State Changes** → PencilCanvasController → Published Properties → SwiftUI Views
- **Rendering** → StrokeRenderer → Context.draw() → UIKit Drawing System

## 3. Core Components and Responsibilities

### StrokeInputSource
- **Responsibilities**: Touch event handling, StrokePoint conversion
- **Implementation**: UIKit UIView with touch handling overrides
- **Key Features**: Apple Pencil support, shift key detection, multi-touch support

### StrokeEngine
- **Responsibilities**: Stroke state management, active stroke handling
- **Implementation**: Pure Swift class managing stroke collections
- **Key Features**: Begin/Extend/End/Clear operations, stroke validation

### StrokeRenderer
- **Responsibilities**: Core Graphics drawing of strokes
- **Implementation**: Static utility class with drawing methods
- **Key Features**: Line rendering with proper stroke properties, line caps/joins

### DrawingCanvasController
- **Responsibilities**: UI state management, binding to SwiftUI
- **Implementation**: ObservableObject with weak reference to canvas
- **Key Features**: Clear functionality, state publishing for SwiftUI updates

### DrawingCanvas
- **Responsibilities**: UI component hosting drawing operations
- **Implementation**: UIView subclass inheriting StrokeInputSource
- **Key Features**: Core Graphics rendering, touch-to-stroke conversion

### ContentView
- **Responsibilities**: Main UI layout, SwiftUI binding to controller
- **Implementation**: SwiftUI View with ZStack layout
- **Key Features**: Light color scheme, shadow effects, clear button

## 4. Handwriting Functionality Implementation

### Stroke Creation and Management
- **Point Data**: StrokePoint includes location, force, azimuth, and altitude
- **Real-time Processing**: Touch events processed immediately for real-time feedback
- **State Management**: Active vs completed stroke distinction
- **Memory Efficiency**: Real-time stroke point accumulation

### Touch Handling
- **Apple Pencil Support**: Direct touch handling with precision
- **Force Sensitivity**: Force data captured and used in stroke rendering
- **Altitude/Azimuth**: Advanced touch information for stroke quality
- **Shift Key Detection**: Alternative touch handling for non-pencil input

### Rendering System
- **Core Graphics**: Direct use of Core Graphics for precise rendering
- **Line Properties**: Line caps and joins for smooth stroke appearance
- **Performance**: Efficient drawing with minimal redraws
- **Context Management**: Proper context acquisition for drawing operations

## 5. Testing Strategies and QA Approaches

### UITest Framework
- **Test Structure**: XCTestCase subclasses for specific test scenarios
- **Accessibility IDs**: QAID.swift for testable UI elements
- **UI Automation**: Direct interaction with UI components

### Handwriting Test Approach
- **Basic Operations**: Finger drag (no drawing), pencil stroke injection
- **State Verification**: Stroke count validation
- **Functional Testing**: Multiple strokes and clear functionality
- **Custom Injection**: Bridge command injection for complex scenarios

### QA Tools
- **QABase**: Base test class with common setup
- **QAGestures**: Custom gesture injection methods
- **QAID**: Accessibility identifiers for test automation
- **Testing Environment**: UITEST flag for test-specific behavior

### Recording QA Runs
- **Video Recording**: simctl io command for quality video capture
- **Graceful Termination**: SIGINT signal for proper video finalization
- **Simulation Control**: D9281340-20A0-41E0-895A-F24921E112C2 iPad Air 11-inch (M3) simulator

## 6. Swift Formatting and Linting

- **Swift Format**: Version 6.2.3 (used for formatting all files)
- **Swift Lint**: Not available in this environment
- **Code Quality**: Follows functional programming paradigms
- **File Naming**: Explicit, descriptive names for all components

## 7. Build and Testing

- **Build Target**: iPad Air 11-inch (M3)
- **Build Command**: xcodebuild -scheme SupaNotes -destination "platform=iOS Simulator,id=D9281340-20A0-41E0-895A-F24921E112C2"
- **Test Command**: xcodebuild -scheme SupaNotes -destination "platform=iOS Simulator,id=D9281340-20A0-41E0-895A-F24921E112C2" -only-testing:UITests -parallel-testing-enabled NO test-without-building
- **Video Recording**: simctl io command for quality video capture
- **Recording Command**: xcrun simctl io $SIM recordVideo --codec=h264 --force qa-run.mp4 &
- **Graceful Termination**: SIGINT signal for proper video finalization