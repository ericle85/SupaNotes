import Foundation

func fetchMathSuggestion(expression: String, serverURL: String = "http://100.90.35.22:5555") async
  -> String?
{
  let url = URL(string: "\(serverURL)/suggest")!
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.timeoutInterval = 5

  let body = ["expression": expression]
  request.httpBody = try? JSONSerialization.data(withJSONObject: body)

  guard let (data, _) = try? await URLSession.shared.data(for: request),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return nil
  }

  return json["result"] as? String
}
