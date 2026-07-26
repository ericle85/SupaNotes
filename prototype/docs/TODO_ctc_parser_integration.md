# TODO: Fix CTC Model Output → Autocomplete Pipeline Integration

## Problem

The CTC model (CER 6.97%) produces LaTeX output from handwriting recognition.
The autocomplete parser (`math_engine/latex_parser.py`) only handles a handful of
LaTeX commands, so many valid CTC outputs fail to parse.

**Current status**: `parse_latex()` works for `\frac`, `\sqrt`, Greek letters,
`\pi`, `\infty` — but fails for `\sin`, `\cos`, `\int`, `\sum`, `\partial`,
`\text`, nested braces like `e^{i\pi}`, and many more.

## Tasks

### 1. Expand LaTeX command parser (HIGH)
- [ ] Add support for trig functions: `\sin`, `\cos`, `\tan`, `\asin`, `\acos`, `\atan`
- [ ] Add support for calculus: `\int`, `\sum`, `\prod`, `\lim`, `\partial`
- [ ] Add support for `\text{...}` and `\mathrm{...}`
- [ ] Add support for `\log`, `\ln`, `\exp`
- [ ] Add support for `\in`, `\subset`, `\subseteq`, `\subseteq`, `\infty`, `\pm`, `\mp`
- [ ] Handle `\left...\right` properly (currently leaves trailing `\right`)

### 2. Fix nested brace parsing (HIGH)
- [ ] `e^{i\pi}` currently produces `e**{i\pi}` — fix brace nesting in `parse_latex()`
- [ ] `\frac{\alpha}{\beta}` inside `\left(...\right)` currently produces `\left( (\alpha)/(\beta) \right)` — the `\left` and `\right` remain
- [ ] Handle cases like `\sum_{n=0}^{\infty}` which produces `\sum_n=0**oo` — the subscript needs proper handling

### 3. Ensure output format consistency (MEDIUM)
- [ ] CTC model outputs in LaTeX format — parser should output in LaTeX format too (not Python/sympy notation)
- [ ] The suggestion should be a LaTeX string, not `alpha*x + beta = 0`
- [ ] Consider making `parse_latex()` output LaTeX-compatible text that the rest of the pipeline can handle

### 4. Add comprehensive tests (MEDIUM)
- [ ] Test every LaTeX command the CTC model might produce
- [ ] Include edge cases: nested fractions, multi-line equations, Greek letters with subscripts/superscripts
- [ ] Test the full pipeline: `CTC output → parse_latex → parse_single_line → classify_intent → generate_next_line`

### 5. Integration with CTC model (LOW)
- [ ] Verify the parser handles the actual CTC vocabulary (259 tokens)
- [ ] Test with real model output on the test set (7,644 samples)
- [ ] Measure what percentage of CTC outputs currently fail parsing

## Files to modify

- `prototype/autocomplete/math_engine/latex_parser.py` — main parser
- `prototype/autocomplete/document_line_parser.py` — line parsing
- `prototype/autocomplete/intent_classifier.py` — intent classification
- `prototype/autocomplete/math_engine/engine.py` — suggestion generation

## Test data

Real CTC outputs that currently fail:
- `e^{i\pi} + 1 = 0` → `UnparsableLine`
- `\sin(\theta) = \frac{1}{2}` → `UnparsableLine`
- `\int_0^{\infty} e^{-x} dx` → `UnparsableLine`
- `\sum_{n=0}^{\infty} \frac{x^n}{n!}` → `UnparsableLine`
- `\partial f / \partial x` → `UnparsableLine`
- `\left( \frac{x}{y} \right)` → `UnparsableLine`
