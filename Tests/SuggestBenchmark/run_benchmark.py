#!/usr/bin/env python3
"""
Suggest Benchmark Runner
========================
Evaluates local LLMs on the handwriting autosuggestion task.

Two modes:
  --mode vision   : sends image to model (default)
  --mode text     : sends OCR ground truth text only

Usage:
  python run_benchmark.py --model qwen3.5:4b
  python run_benchmark.py --model gemma4:4b --mode text
  python run_benchmark.py --model qwen3.5:4b --host <tailscale-ip>
"""

import argparse
import base64
import json
import re
import time
from pathlib import Path
from urllib.request import Request, urlopen

SCRIPT_DIR = Path(__file__).parent
DEFAULT_HOST = "localhost"
DEFAULT_PORT = 11434

SUGGEST_PROMPT = """\
You autocomplete handwritten notes by providing a suggestion to build off the user. 
Rules:
1. Max 8 words or one short expression
2. Wrap ALL math/symbols/numbers in [latex]...[/latex] tags
3. NEVER use $ signs for math
4. Output ONLY the suggestion, nothing else
5. It is on the next step so what a user would evaluate in their head. Don't skip steps.
6. If you can't suggest anything valid, respond with (none)

Examples:
- "The area of a circle is" → [latex]A = \\pi r^2[/latex]
- "Let x be a" → positive integer
- "If f(x) = 3x + 1, then" → [latex]f(2) = 7[/latex]
- "The Schrödinger equation describes" → the time evolution of [latex]\\psi[/latex]
- "Hello" → (none)


For math, if the user has written some part of the expression which is is your suggestion, your suggestion shuold build on top of it, not repeat wat is alraedy written on the screen.
Example:
- "1 + 1" → [latex]= 2[/latex]
- "1 + 1 = " → [latex]2[/latex]
- "3x + 3 = 5 " → [latex] 3x = 2[/latex] We don't want to solve the problem for the user, rather just give the next step.


Look at the handwritten notes and suggest what comes next."""

TOOLS_INSTRUCTION = """
IMPORTANT: You have math tools available (add, subtract, multiply, divide). When you need to compute ANY arithmetic, you MUST call a tool first. Do NOT calculate in your head. Call the tool, get the result, then write your suggestion using that result."""

TEXT_ONLY_PROMPT_PREFIX = """\
The user has written the following on their notepad:
\"\"\"{ocr_text}\"\"\"

"""


def load_test_cases():
    with open(SCRIPT_DIR / "test_cases.json") as f:
        return json.load(f)


MATH_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "add",
            "description": "Add two numbers",
            "parameters": {
                "type": "object",
                "properties": {
                    "a": {"type": "number", "description": "First number"},
                    "b": {"type": "number", "description": "Second number"},
                },
                "required": ["a", "b"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "subtract",
            "description": "Subtract b from a (a - b)",
            "parameters": {
                "type": "object",
                "properties": {
                    "a": {"type": "number", "description": "Number to subtract from"},
                    "b": {"type": "number", "description": "Number to subtract"},
                },
                "required": ["a", "b"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "multiply",
            "description": "Multiply two numbers",
            "parameters": {
                "type": "object",
                "properties": {
                    "a": {"type": "number", "description": "First number"},
                    "b": {"type": "number", "description": "Second number"},
                },
                "required": ["a", "b"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "divide",
            "description": "Divide a by b (a / b)",
            "parameters": {
                "type": "object",
                "properties": {
                    "a": {"type": "number", "description": "Numerator"},
                    "b": {"type": "number", "description": "Denominator"},
                },
                "required": ["a", "b"],
            },
        },
    },
]


def execute_tool(name, args):
    """Execute a math tool and return the result as a string."""
    try:
        a, b = float(args.get("a", 0)), float(args.get("b", 0))
    except (TypeError, ValueError) as e:
        return f"Error: invalid arguments ({e})"
    if name == "add":
        result = a + b
    elif name == "subtract":
        result = a - b
    elif name == "multiply":
        result = a * b
    elif name == "divide":
        if b == 0:
            return "Error: division by zero"
        result = a / b
    else:
        return f"Unknown tool: {name}"
    # Return int when possible for cleaner output
    print(" TOOL CALLED:", name, args, "RESULT:", result)
    return str(int(result)) if result == int(result) else str(result)


def _ollama_request(host, port, body):
    """Send a request to Ollama and return parsed JSON."""
    data = json.dumps(body).encode()
    req = Request(
        f"http://{host}:{port}/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())


def call_ollama(host, port, model, prompt, image_b64=None, think=False, use_tools=False):
    """Call Ollama chat API with optional tool use. Returns (response_text, elapsed_ms)."""
    message = {"role": "user", "content": prompt}
    if image_b64:
        message["images"] = [image_b64]

    messages = [message]
    body = {
        "model": model,
        "messages": messages,
        "stream": False,
        "think": think,
        "options": {"temperature": 0, "top_p": 0.9, "top_k": 20, "num_ctx": 8192},
    }
    if use_tools:
        body["tools"] = MATH_TOOLS

    start = time.perf_counter()
    result = _ollama_request(host, port, body)

    # Tool call loop (max 5 rounds to prevent infinite loops)
    for _ in range(5):
        msg = result.get("message", {})
        tool_calls = msg.get("tool_calls")
        if not tool_calls:
            break

        # Add assistant message with tool calls to history
        messages.append(msg)

        # Execute each tool call and add results
        for tc in tool_calls:
            fn = tc.get("function", {})
            tool_result = execute_tool(fn.get("name", ""), fn.get("arguments", {}))
            messages.append({"role": "tool", "content": tool_result})

        # Call model again with tool results
        body["messages"] = messages
        result = _ollama_request(host, port, body)

    elapsed = (time.perf_counter() - start) * 1000

    text = result.get("message", {}).get("content", "")
    # Strip <think> tags if present
    text = re.sub(r"<think>[\s\S]*?</think>", "", text).strip()
    return text, elapsed


def score_format(output):
    """Programmatic format checks. Returns dict of pass/fail."""
    scores = {}
    # No $ signs for math
    scores["no_dollar_signs"] = "$" not in output
    # If contains backslash or math-like content, should be in [latex] tags
    has_math_chars = bool(re.search(r"[\\^_{}]", output))
    has_latex_tags = bool(re.search(r"\[latex\].*?\[/latex\]", output))
    scores["latex_tags_used"] = (not has_math_chars) or has_latex_tags
    # No thinking tokens leaked
    scores["no_think_leak"] = "<think>" not in output and "</think>" not in output
    # Length check: roughly ≤8 words (strip latex tags for counting)
    stripped = re.sub(r"\[/?latex\]", "", output)
    word_count = len(stripped.split())
    scores["length_ok"] = word_count <= 12  # generous, latex tokens inflate count
    # Not empty
    scores["non_empty"] = len(output.strip()) > 0
    return scores


def run_benchmark(host, port, model, mode, think, use_tools=False):
    cases = load_test_cases()
    results = []
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    model_slug = model.replace(":", "_").replace("/", "_")
    tools_suffix = "_tools" if use_tools else ""
    out_file = SCRIPT_DIR / "results" / f"{model_slug}_{mode}{tools_suffix}_{timestamp}.txt"

    tools_label = "+tools" if use_tools else ""
    print(f"Running benchmark: model={model} mode={mode}{tools_label} think={think}")
    print(f"Output: {out_file}")
    print(f"Test cases: {len(cases)}")
    print("-" * 60)

    for case in cases:
        case_id = case["id"]
        ocr_text = case["ocr_text"]

        # Build prompt
        base_prompt = SUGGEST_PROMPT + (TOOLS_INSTRUCTION if use_tools else "")
        if mode == "text":
            prompt = TEXT_ONLY_PROMPT_PREFIX.format(ocr_text=ocr_text) + base_prompt
            image_b64 = None
        else:
            img_path = SCRIPT_DIR / case["image"]
            if not img_path.exists():
                print(f"  SKIP {case_id}: image not found at {img_path}")
                results.append({
                    "id": case_id,
                    "ocr_text": ocr_text,
                    "output": "[SKIPPED - no image]",
                    "elapsed_ms": 0,
                    "format_scores": {},
                    "category": case["category"],
                    "acceptable": case["acceptable_suggestions"],
                })
                continue
            with open(img_path, "rb") as f:
                image_b64 = base64.b64encode(f.read()).decode()
            prompt = base_prompt

        # Call model
        try:
            output, elapsed = call_ollama(host, port, model, prompt, image_b64, think, use_tools)
        except Exception as e:
            output = f"[ERROR: {e}]"
            elapsed = 0

        fmt_scores = score_format(output)
        fmt_pass = sum(fmt_scores.values())
        fmt_total = len(fmt_scores)

        results.append({
            "id": case_id,
            "ocr_text": ocr_text,
            "output": output,
            "elapsed_ms": round(elapsed, 1),
            "format_scores": fmt_scores,
            "category": case["category"],
            "acceptable": case["acceptable_suggestions"],
        })

        print(f"  {case_id}: {elapsed:.0f}ms | fmt={fmt_pass}/{fmt_total} | {output[:80]}")

    # Write results file
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with open(out_file, "w") as f:
        f.write(f"# Suggest Benchmark Results\n")
        f.write(f"# Model: {model}\n")
        f.write(f"# Mode: {mode}\n")
        f.write(f"# Tools: {use_tools}\n")
        f.write(f"# Think: {think}\n")
        f.write(f"# Date: {timestamp}\n")
        f.write(f"# Cases: {len(cases)}\n")
        f.write("=" * 60 + "\n\n")

        total_fmt_pass = 0
        total_fmt_checks = 0
        total_elapsed = 0

        for r in results:
            f.write(f"## {r['id']} ({r['category']})\n")
            f.write(f"OCR Input: {r['ocr_text']}\n")
            f.write(f"Model Output: {r['output']}\n")
            f.write(f"Acceptable: {' | '.join(r['acceptable'])}\n")
            f.write(f"Latency: {r['elapsed_ms']}ms\n")
            if r["format_scores"]:
                for k, v in r["format_scores"].items():
                    f.write(f"  {k}: {'PASS' if v else 'FAIL'}\n")
                total_fmt_pass += sum(r["format_scores"].values())
                total_fmt_checks += len(r["format_scores"])
            total_elapsed += r["elapsed_ms"]
            f.write("\n")

        # Summary
        n = len([r for r in results if r["elapsed_ms"] > 0])
        f.write("=" * 60 + "\n")
        f.write("# SUMMARY\n")
        f.write(f"Format compliance: {total_fmt_pass}/{total_fmt_checks}")
        if total_fmt_checks:
            f.write(f" ({100*total_fmt_pass/total_fmt_checks:.0f}%)")
        f.write("\n")
        if n:
            f.write(f"Avg latency: {total_elapsed/n:.0f}ms\n")
        f.write(f"Total time: {total_elapsed:.0f}ms\n")

    print("-" * 60)
    print(f"Results saved to {out_file}")
    return out_file


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Suggest Benchmark Runner")
    parser.add_argument("--model", required=True, help="Ollama model name (e.g. qwen3.5:4b)")
    parser.add_argument("--mode", choices=["vision", "text"], default="vision")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--think", action="store_true", help="Enable thinking mode")
    parser.add_argument("--tools", action="store_true", help="Enable math tools (add/subtract/multiply/divide)")
    args = parser.parse_args()
    run_benchmark(args.host, args.port, args.model, args.mode, args.think, args.tools)
