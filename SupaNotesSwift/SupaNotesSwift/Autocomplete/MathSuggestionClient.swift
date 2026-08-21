struct MathSuggestion {
    let text: String
    let placement: String
}

func fetchMathSuggestion(expression: String) -> MathSuggestion? {
    if let solved = solveEquation(expression: expression) {
        return solved
    }

    if let simplified = simplifyExpression(expression: expression) {
        return simplified
    }

    return nil
}

private func solveEquation(expression: String) -> MathSuggestion? {
    let result = expression.withCString { ptr in
        symengine_solve_equation(ptr)
    }

    guard let result else {
        return nil
    }

    defer {
        symengine_free_string(result)
    }

    return MathSuggestion(
        text: String(cString: result),
        placement: "alignWithEqualSignAbove"
    )
}

private func simplifyExpression(expression: String) -> MathSuggestion? {
    let result = expression.withCString { ptr in
        symengine_simplify_expression(ptr)
    }

    guard let result else {
        return nil
    }

    defer {
        symengine_free_string(result)
    }

    return MathSuggestion(
        text: String(cString: result),
        placement: "append"
    )
}
