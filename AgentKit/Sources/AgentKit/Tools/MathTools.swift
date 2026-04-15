import Foundation

// MARK: - Definitions

func mathTool(_ name: String, _ description: String) -> Tool {
    Tool(type: "function", function: ToolFunction(
        name: name, description: description,
        parameters: ToolParameters(
            type: "object",
            properties: [
                "a": PropertyDefinition(type: "number", description: "First number"),
                "b": PropertyDefinition(type: "number", description: "Second number")
            ],
            required: ["a", "b"]
        )
    ))
}

let mathTools: [Tool] = [
    mathTool("gcd",      "Greatest common divisor of two integers a and b."),
    mathTool("min",      "Minimum of two numbers a and b."),
    mathTool("max",      "Maximum of two numbers a and b."),
    mathTool("add",      "Add two numbers together. Use this for any addition operations."),
    mathTool("subtract", "Subtract b from a. Use this for any subtraction operations."),
    mathTool("multiply", "Multiply two numbers together. Use this for any multiplication operations."),
    mathTool("divide",   "Divide a by b. Use this for any division operations."),
    Tool(type: "function", function: ToolFunction(
        name: "solve_quadratic",
        description: "Solve ax^2 + bx + c = 0. Returns the real roots.",
        parameters: ToolParameters(
            type: "object",
            properties: [
                "a": PropertyDefinition(type: "number", description: "Coefficient of x^2"),
                "b": PropertyDefinition(type: "number", description: "Coefficient of x"),
                "c": PropertyDefinition(type: "number", description: "Constant term")
            ],
            required: ["a", "b", "c"]
        )
    )),
    Tool(type: "function", function: ToolFunction(
        name: "abs",
        description: "Absolute value of a number.",
        parameters: ToolParameters(
            type: "object",
            properties: ["a": PropertyDefinition(type: "number", description: "Input number")],
            required: ["a"]
        )
    )),
    Tool(type: "function", function: ToolFunction(
        name: "floor",
        description: "Floor of a number — largest integer less than or equal to a.",
        parameters: ToolParameters(
            type: "object",
            properties: ["a": PropertyDefinition(type: "number", description: "Input number")],
            required: ["a"]
        )
    )),
]

// MARK: - Executor

func executeMathTool(_ toolCall: ToolCall, log: inout [String]) -> String {
    let name = toolCall.function.name
    guard name != "none", !name.isEmpty else { return "" }

    guard let data = toolCall.function.arguments.data(using: .utf8),
          let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log.append("FAIL invalid arguments for \(name)")
        return "Error: Invalid arguments"
    }

    let aVal = args["a"]; let bVal = args["b"]
    if aVal is String || bVal is String {
        log.append("SKIP symbolic args for \(name)")
        return "Error: Symbolic arguments"
    }

    guard let a = (aVal as? Double) ?? (aVal as? Int).map(Double.init) else {
        log.append("FAIL invalid arguments for \(name)")
        return "Error: Invalid arguments"
    }
    let b = (bVal as? Double) ?? (bVal as? Int).map(Double.init) ?? 0.0

    if name == "solve_quadratic" {
        let c = (args["c"] as? Double) ?? (args["c"] as? Int).map(Double.init) ?? 0
        return solveQuadratic(a: a, b: b, c: c, log: &log)
    }

    let result: Double
    switch name {
    case "add":      result = a + b
    case "subtract": result = a - b
    case "multiply": result = a * b
    case "abs":      result = abs(a)
    case "floor":    result = floor(a)
    case "min":      result = min(a, b)
    case "max":      result = max(a, b)
    case "gcd":      result = Double(euclidGCD(Int(a), Int(b)))
    case "divide":
        guard b != 0 else {
            log.append("FAIL division by zero")
            return "Error: Division by zero"
        }
        result = a / b
    default:
        log.append("FAIL unknown tool: \(name)")
        return "Error: Unknown tool"
    }

    log.append("TOOL \(name)(\(a), \(b)) = \(result)")
    return formatDouble(result)
}

// MARK: - Helpers

private func euclidGCD(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : euclidGCD(b, a % b) }

private func solveQuadratic(a: Double, b: Double, c: Double, log: inout [String]) -> String {
    let discriminant = b * b - 4 * a * c
    log.append("TOOL solve_quadratic(\(a), \(b), \(c)) discriminant=\(discriminant)")
    if discriminant < 0  { return "No real roots" }
    if discriminant == 0 { return "x = \(formatDouble(-b / (2 * a)))" }
    let x1 = (-b + sqrt(discriminant)) / (2 * a)
    let x2 = (-b - sqrt(discriminant)) / (2 * a)
    return "x = \(formatDouble(x1)), x = \(formatDouble(x2))"
}

func formatDouble(_ d: Double) -> String {
    d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.4f", d)
}
