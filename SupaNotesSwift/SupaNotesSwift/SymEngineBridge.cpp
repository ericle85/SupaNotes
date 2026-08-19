#include "SymEngineBridge.h"

#include <cstdlib>
#include <cstring>
#include <map>
#include <sstream>
#include <string>

#include <symengine/basic.h>
#include <symengine/parser.h>
#include <symengine/printers.h>
#include <symengine/simplify.h>
#include <symengine/solve.h>
#include <symengine/sets.h>
#include <symengine/visitor.h>

namespace {

std::string stripTrailingEquals(const std::string &expression) {
  std::string normalized = expression;
  const std::size_t equalsPosition = normalized.find_last_of('=');

  if (equalsPosition != std::string::npos && equalsPosition == normalized.size() - 1) {
    normalized.erase(equalsPosition);
  }

  return normalized;
}

std::string latexToSymEngine(const std::string &input) {
  std::string result;
  result.reserve(input.size());

  for (std::size_t i = 0; i < input.size(); ++i) {
    if (input[i] == '\\') {
      if (input.compare(i, 5, "\\frac") == 0) {
        i += 5;
        std::string num, den;

        if (i < input.size() && input[i] == '{') {
          int depth = 1;
          ++i;
          while (i < input.size() && depth > 0) {
            if (input[i] == '{') { ++depth; }
            else if (input[i] == '}') { --depth; }
            if (depth > 0) { num += input[i]; }
            ++i;
          }
        }

        if (i < input.size() && input[i] == '{') {
          int depth = 1;
          ++i;
          while (i < input.size() && depth > 0) {
            if (input[i] == '{') { ++depth; }
            else if (input[i] == '}') { --depth; }
            if (depth > 0) { den += input[i]; }
            ++i;
          }
        }

        result += "((" + num + ")/(" + den + "))";
        --i;
        continue;
      }

      if (input.compare(i, 5, "\\sqrt") == 0) {
        i += 5;
        if (i < input.size() && input[i] == '{') {
          int depth = 1;
          ++i;
          std::string inner;
          while (i < input.size() && depth > 0) {
            if (input[i] == '{') { ++depth; }
            else if (input[i] == '}') { --depth; }
            if (depth > 0) { inner += input[i]; }
            ++i;
          }
          result += "sqrt(" + inner + ")";
          --i;
          continue;
        }
      }

      if (input.compare(i, 4, "\\pi") == 0 && (i + 3 >= input.size() || !std::isalpha(input[i + 3]))) {
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

}

extern "C" const char *symengine_simplify_expression(const char *expression) {
  if (expression == nullptr) {
    return nullptr;
  }

  try {
    const std::string normalized = latexToSymEngine(stripTrailingEquals(expression));
    const SymEngine::RCP<const SymEngine::Basic> parsed = SymEngine::parse(normalized);

    if (!SymEngine::free_symbols(*parsed).empty()) {
      return nullptr;
    }

    const SymEngine::RCP<const SymEngine::Basic> simplified = SymEngine::simplify(parsed);
    const std::string result = SymEngine::latex(*simplified);
    return strdup(result.c_str());
  } catch (...) {
    return nullptr;
  }
}

extern "C" const char *symengine_solve_equation(const char *expression) {
  if (expression == nullptr) {
    return nullptr;
  }

  try {
    const std::string input(expression);
    const std::size_t equalsPos = input.find('=');
    if (equalsPos == std::string::npos || equalsPos == input.size() - 1) {
      return nullptr;
    }

    const std::string lhsStr = latexToSymEngine(input.substr(0, equalsPos));
    const std::string rhsStr = latexToSymEngine(input.substr(equalsPos + 1));

    const auto lhs = SymEngine::parse(lhsStr);
    const auto rhs = SymEngine::parse(rhsStr);
    const auto equation = SymEngine::sub(lhs, rhs);

    const auto freeSyms = SymEngine::free_symbols(*equation);
    if (freeSyms.size() != 1) {
      return nullptr;
    }

    const auto sym = SymEngine::rcp_static_cast<const SymEngine::Symbol>(*freeSyms.begin());
    const auto solutionSet = SymEngine::solve(equation, sym);

    if (SymEngine::is_a<SymEngine::FiniteSet>(*solutionSet)) {
      const auto &finite = SymEngine::down_cast<const SymEngine::FiniteSet &>(*solutionSet);
      const auto &elements = finite.get_container();
      if (elements.empty()) {
        return nullptr;
      }

      std::ostringstream oss;
      oss << SymEngine::latex(*sym) << "=";
      bool first = true;
      for (const auto &elem : elements) {
        if (!first) {
          oss << ", ";
        }
        oss << SymEngine::latex(*elem);
        first = false;
      }
      return strdup(oss.str().c_str());
    }

    return nullptr;
  } catch (...) {
    return nullptr;
  }
}

extern "C" void symengine_free_string(const char *value) {
  std::free(const_cast<char *>(value));
}
