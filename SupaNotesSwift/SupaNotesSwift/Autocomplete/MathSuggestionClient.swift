import Foundation

func fetchMathSuggestion(expression: String, serverURL: String = "http://100.90.35.22:5555") -> String? {
    let url = URL(string: "\(serverURL)/suggest")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 5

    let body = ["expression": expression]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    var resultString: String?
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }

        if let error = error {
            print("[MathSuggestionClient] Error: \(error.localizedDescription)")
            return
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[MathSuggestionClient] Invalid response")
            return
        }

        resultString = json["result"] as? String
    }
    task.resume()
    semaphore.wait()

    return resultString
}
