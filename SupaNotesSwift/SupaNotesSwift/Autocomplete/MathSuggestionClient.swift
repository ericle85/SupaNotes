func fetchMathSuggestion(expression: String) -> String? {
    let result = expression.withCString { expressionPointer in
        symengine_simplify_expression(expressionPointer)
    }

    guard let result else {
        return nil
    }

    defer {
        symengine_free_string(result)
    }

    return String(cString: result)
}
