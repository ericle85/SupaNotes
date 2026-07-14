# SupaNotes Autocomplete Prototype

Offline, deterministic math autocomplete for handwritten notes, prototyped in Python
before porting to Swift. No images, no cloud. The recognizer is deliberately stubbed
out: input "documents" are plain text, so the classifier and math engine can be built
and tested independently.

## Pipeline

```
document text
  -> document_line_parser      parse each line into an AST (equation or expression)
  -> document_context_model    current line + preceding lines (layer 2)
  -> intent_classifier         pick which operation to run (layer 3, rule-based stub)
  -> math_engine               execute the operation deterministically (layer 4)
  -> suggested next line
```

The recognizer (layer 1) will later produce the same text lines, so nothing downstream
changes when it is added.

## Layout

```
run_autocomplete.py              single entry point
documents/                       stand-in for the handwriting recognizer
autocomplete/
  document_line_parser.py        text -> ParsedEquation / ParsedExpression
  document_context_model.py      DocumentContext (current + preceding lines)
  math_operations.py             MathOperation enum + ClassifiedIntent (shared)
  intent_classifier.py           rule-based operation picker (stub for a real model)
  autocomplete_pipeline.py       wires the layers together
  math_engine/
    engine.py                    dispatch: operation -> result
    equation_solving.py          step-by-step equation solver (one move per call)
    expression_transforms.py     simplify, factor
```

## Design notes

- The engine returns the **next line**, not the final answer. Handwriting autocomplete
  predicts the next written step, so `equation_solving` applies exactly one algebraic
  move per call (move variable terms, move constants, divide by coefficient).
- Each operation family is its own module under `math_engine/`. Adding calculus, linear
  algebra, complex numbers, or transforms means adding a module and a dispatch branch.
- `intent_classifier` is the only piece meant to be swapped for something smarter.

## Run

```
cd prototype
python3 run_autocomplete.py
```

Requires `sympy`.
