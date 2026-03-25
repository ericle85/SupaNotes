import Foundation

let BLANK_TOKEN = 0

/// Load vocab from vocab.json. Returns idx->token mapping.
func loadVocab() -> [Int: String] {
    guard let url = Bundle.main.url(forResource: "vocab", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tok2idx = json["tok2idx"] as? [String: Int]
    else {
        print("Failed to load vocab.json")
        return [:]
    }
    var idx2tok = [Int: String]()
    for (tok, idx) in tok2idx {
        idx2tok[idx] = tok
    }
    return idx2tok
}

struct TokenDetail {
    let token: String
    let confidence: Float
    let replaced: Bool
}

struct DecodeResult {
    let raw: String
    let thresholded: String
    let tokens: [TokenDetail]
}

/// CTC greedy decode with per-token confidence.
func ctcGreedyDecode(
    logProbs: [Float],
    seqLen: Int,
    vocabSize: Int,
    vocab: [Int: String],
    threshold: Float = 0.7
) -> DecodeResult {
    var decodedTokens = [(Int, Float)]()
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

        let confidence = exp(maxVal)

        if maxIdx != prev && maxIdx != BLANK_TOKEN {
            decodedTokens.append((maxIdx, confidence))
        } else if maxIdx == prev && maxIdx != BLANK_TOKEN {
            if let last = decodedTokens.last {
                decodedTokens[decodedTokens.count - 1] = (last.0, max(last.1, confidence))
            }
        }
        prev = maxIdx
    }

    var rawParts = [String]()
    var threshParts = [String]()
    var details = [TokenDetail]()

    for (tokIdx, conf) in decodedTokens {
        let tokStr = vocab[tokIdx] ?? "?"
        rawParts.append(tokStr)
        let replaced = conf < threshold
        threshParts.append(replaced ? "?" : tokStr)
        details.append(TokenDetail(token: tokStr, confidence: conf, replaced: replaced))
    }

    return DecodeResult(
        raw: rawParts.joined(),
        thresholded: threshParts.joined(),
        tokens: details
    )
}
