#include "LatexParsing.h"
#include <cctype>
#include <cstdlib>

std::string extractBracedGroup(const std::string &input, std::size_t &pos) {
  if (pos >= input.size() || input[pos] != '{') {
    return "";
  }

  int depth = 1;
  ++pos;
  std::string result;
  while (pos < input.size() && depth > 0) {
    if (input[pos] == '{') { ++depth; }
    else if (input[pos] == '}') { --depth; }
    if (depth > 0) { result += input[pos]; }
    ++pos;
  }
  return result;
}

std::string latexToSymEngine(const std::string &input) {
  std::string result;
  result.reserve(input.size());

  for (std::size_t i = 0; i < input.size(); ++i) {
    if (input[i] == '\\') {
      if (input.compare(i, 5, "\\frac") == 0) {
        i += 5;
        std::string num = extractBracedGroup(input, i);
        std::string den = extractBracedGroup(input, i);
        result += "((" + num + ")/(" + den + "))";
        --i;
        continue;
      }

      if (input.compare(i, 5, "\\sqrt") == 0) {
        i += 5;
        if (i < input.size() && input[i] == '{') {
          std::string inner = extractBracedGroup(input, i);
          result += "sqrt(" + inner + ")";
          --i;
          continue;
        }
      }

      if (input.compare(i, 4, "\\pi") == 0 &&
          (i + 3 >= input.size() || !std::isalpha(input[i + 3]))) {
        result += "pi";
        i += 2;
        continue;
      }

      continue;
    }

    if (input[i] == '{' || input[i] == '}') {
      continue;
    }

    if (input[i] == '^') {
      result += "**";
      continue;
    }

    if (input[i] == '(' && !result.empty()) {
      char last = result.back();
      if (std::isdigit(last) || last == ')') {
        result += '*';
      }
    }

    if (std::isdigit(input[i]) && !result.empty() && result.back() == ')') {
      result += '*';
    }

    result += input[i];
  }

  return result;
}

bool inputHasUnsimplifiedFraction(const std::string &raw) {
  std::size_t pos = raw.find("\\frac{");
  if (pos == std::string::npos) {
    return false;
  }

  pos += 5;
  std::string numStr = extractBracedGroup(raw, pos);
  std::string denStr = extractBracedGroup(raw, pos);

  try {
    long long num = std::stoll(numStr);
    long long den = std::stoll(denStr);
    if (den == 0) { return false; }
    num = std::abs(num);
    den = std::abs(den);
    while (den != 0) {
      long long t = den;
      den = num % den;
      num = t;
    }
    return num > 1;
  } catch (...) {
    return false;
  }
}
