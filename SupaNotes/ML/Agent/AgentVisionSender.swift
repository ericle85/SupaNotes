import UIKit

@Observable
final class AgentVisionSender {
    enum Status {
        case idle, sending, sent, failed(String)
    }

    var status: Status = .idle

    private let host = "100.90.35.22"
    private let port = 8765

    func send(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            status = .failed("JPEG encode failed")
            return
        }

        status = .sending

        var request = URLRequest(url: URL(string: "http://\(host):\(port)/vision")!)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let error {
                    self?.status = .failed(error.localizedDescription)
                } else {
                    self?.status = .sent
                }
                // Auto-reset after 2s
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.status = .idle
                }
            }
        }.resume()
    }
}
