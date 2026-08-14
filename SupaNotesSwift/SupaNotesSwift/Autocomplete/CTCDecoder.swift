import Foundation

let BLANK_TOKEN = 0

func loadVocab() -> [Int: String] {
    guard let url = Bundle.main.url(forResource: "vocab", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tok2idx = json["tok2idx"] as? [String: Int]
    else {
        print("[CTCDecoder] Failed to load vocab.json")
        return [:]
    }
    var idx2tok = [Int: String]()
    for (tok, idx) in tok2idx {
        idx2tok[idx] = tok
    }
    return idx2tok
}

func ctcGreedyDecode(
    logProbs: [Float],
    seqLen: Int,
    vocabSize: Int,
    vocab: [Int: String]
) -> String {
    var decodedTokens = [Int]()
    var prev = -1

    for t in 0..<seqLen {
        let offset = t * vocabSize
        var maxIdx = 0
        var maxVal: Float = logProbs[offset]

        for v in 1..<vocabSize {
            let val = logProbs[offset + v]
            if val > maxVal {
                maxVal = val
                maxIdx = v
            }
        }

        if maxIdx != prev && maxIdx != BLANK_TOKEN {
            decodedTokens.append(maxIdx)
        }
        prev = maxIdx
    }

    return decodedTokens
        .map { vocab[$0] ?? "?" }
        .joined()
}
