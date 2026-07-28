# Swift English Handwriting Recognition Plan

## Decision

The iOS app will use **Google ML Kit Digital Ink Recognition** for English handwriting, running on-device.

The Python prototype keeps `ocr_pipeline/google_ink_handwriting_recognizer.py`, which posts strokes to
`inputtools.google.com`. That is a stand-in only: ML Kit has no Python API, and the HTTP endpoint is the
only way to reach Google's handwriting model from the prototype. It is not the shipping path.

## Why ML Kit for Swift

- Free. No GCP project, no billing, no per-request cost.
- On-device. Ink never leaves the device during recognition.
- Offline. No network needed once the language pack is present.
- Same model lineage as the Gboard recognizer, which scores 2.5% CER / 6.5% WER on IAM-OnDB without
  having trained on it (Carbune et al., IJDAR 2020, arXiv:1902.10525).

## Integration notes

- Pod: `GoogleMLKit/DigitalInkRecognition`.
- Language packs download on demand via `ModelManager`. First run for a given language needs network;
  gate recognition on `isModelDownloaded(model)` and download `en` ahead of first use.
- Input is an `Ink`: strokes of `StrokePoint(x:y:t:)`, where `t` is milliseconds. Maps directly from
  `PKStroke.path` — sample the path and carry `timeOffset` through as the timestamp.
- Recognition is sensitive to stroke order, so feed strokes in writing order, matching
  `strokes_in_writing_order` in the prototype.
- Results come back ranked with confidence, unlike the HTTP endpoint, which returns candidates unscored.

## Scope boundary

ML Kit is English text only. It has no math or LaTeX recognizer. Math stays on the CTC model — this
replaces the text branch of `recognize_group`, nothing else.

## Fallback

Apple Vision (`ocr_pipeline/handwriting_text_recognizer.py`, `VNRecognizeTextRequest` on rasterized
strokes) is also free, on-device and offline. It read `warld` for `world` on the `writing` fixture where
ML Kit's lineage read it correctly. Keep it as the fallback if a language pack is missing.
