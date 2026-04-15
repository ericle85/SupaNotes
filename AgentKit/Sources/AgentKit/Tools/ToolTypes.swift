import Foundation

public struct Tool: Codable {
    let type: String
    let function: ToolFunction
}

public struct ToolFunction: Codable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

public struct ToolParameters: Codable {
    let type: String
    let properties: [String: PropertyDefinition]
    let required: [String]
}

public struct PropertyDefinition: Codable {
    let type: String
    let description: String
}

struct ToolCall: Codable {
    let id: String?
    let type: String?
    let function: FunctionCall
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        if let str = try? c.decode(String.self, forKey: .arguments) {
            arguments = str
        } else {
            let dict = try c.decode([String: AnyCodable].self, forKey: .arguments)
            arguments = String(data: try JSONEncoder().encode(dict), encoding: .utf8) ?? "{}"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(arguments, forKey: .arguments)
    }

    private enum CodingKeys: String, CodingKey { case name, arguments }
}

struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let b = try? c.decode(Bool.self) { value = b }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let b as Bool:   try c.encode(b)
        default: try c.encode("")
        }
    }
}
