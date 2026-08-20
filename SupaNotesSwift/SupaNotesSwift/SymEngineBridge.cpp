#include "SymEngineBridge.h"

#include <cstdlib>
#include <cstring>
#include <map>
#include <numeric>
#include <sstream>
#include <string>

#include <iomanip>

#include <symengine/basic.h>
#include <symengine/parser.h>
#include <symengine/printers.h>
#include <symengine/eval_double.h>
#include <symengine/rational.h>
#include <symengine/simplify.h>
#include <symengine/solve.h>
#include <symengine/sets.h>
#include <symengine/visitor.h>
#include <symengine/pow.h>
#include <symengine/mul.h>
#include <symengine/integer.h>
#include <symengine/add.h>
#include <symengine/number.h>
#include <symengine/complex.h>

namespace {

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

bool inputHasUnsimplifiedFraction(const std::string &raw) {
  std::size_t pos = raw.find("\\frac{");
  if (pos == std::string::npos) {
    return false;
  }

  pos += 6;
  std::string numStr;
  int depth = 1;
  while (pos < raw.size() && depth > 0) {
    if (raw[pos] == '{') { ++depth; }
    else if (raw[pos] == '}') { --depth; }
    if (depth > 0) { numStr += raw[pos]; }
    ++pos;
  }

  if (pos >= raw.size() || raw[pos] != '{') {
    return false;
  }
  ++pos;
  std::string denStr;
  depth = 1;
  while (pos < raw.size() && depth > 0) {
    if (raw[pos] == '{') { ++depth; }
    else if (raw[pos] == '}') { --depth; }
    if (depth > 0) { denStr += raw[pos]; }
    ++pos;
  }

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

std::string rationalToDecimalString(const SymEngine::RCP<const SymEngine::Basic> &expr, int precision) {
  double value = SymEngine::eval_double(*expr);
  std::ostringstream oss;
  oss << std::fixed << std::setprecision(precision) << value;
  std::string s = oss.str();
  std::size_t dot = s.find('.');
  if (dot != std::string::npos) {
    std::size_t lastNonZero = s.find_last_not_of('0');
    if (lastNonZero == dot) {
      s.erase(dot);
    } else {
      s.erase(lastNonZero + 1);
    }
  }
  return s;
}

SymEngine::RCP<const SymEngine::Basic> simplifySqrtCoefficient(
    const SymEngine::RCP<const SymEngine::Basic> &expr) {
  if (!SymEngine::is_a<SymEngine::Mul>(*expr)) {
    return expr;
  }

  auto &m = SymEngine::down_cast<const SymEngine::Mul &>(*expr);
  auto coeff = m.get_coef();
  auto dict = m.get_dict();

  for (auto &p : dict) {
    if (!SymEngine::is_a<SymEngine::Integer>(*p.first)) {
      continue;
    }
    if (!SymEngine::eq(*p.second, *SymEngine::rational(1, 2))) {
      continue;
    }

    long long n = SymEngine::down_cast<const SymEngine::Integer &>(*p.first).as_int();
    long long outside = 1;
    long long inside = n;
    for (long long f = 2; f * f <= inside; ++f) {
      while (inside % (f * f) == 0) {
        inside /= (f * f);
        outside *= f;
      }
    }

    if (outside > 1) {
      auto newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(
          SymEngine::mul(coeff, SymEngine::integer(outside)));
      SymEngine::map_basic_basic newDict(dict);
      newDict.erase(p.first);
      if (inside > 1) {
        newDict[SymEngine::integer(inside)] = SymEngine::rational(1, 2);
      }
      return SymEngine::Mul::from_dict(newCoeff, std::move(newDict));
    }
    break;
  }

  return expr;
}

SymEngine::RCP<const SymEngine::Basic> simplifyCubeRootCoefficient(
    const SymEngine::RCP<const SymEngine::Basic> &expr) {
  if (!SymEngine::is_a<SymEngine::Mul>(*expr)) {
    return expr;
  }

  auto &m = SymEngine::down_cast<const SymEngine::Mul &>(*expr);
  auto coeff = m.get_coef();
  auto dict = m.get_dict();

  for (auto &p : dict) {
    if (!SymEngine::is_a<SymEngine::Integer>(*p.first)) {
      continue;
    }
    if (!SymEngine::eq(*p.second, *SymEngine::rational(1, 3))) {
      continue;
    }

    long long n = SymEngine::down_cast<const SymEngine::Integer &>(*p.first).as_int();
    bool negative = (n < 0);
    long long absN = std::abs(n);

    long long outside = 1;
    long long inside = absN;
    for (long long f = 2; f * f * f <= inside; ++f) {
      while (inside % (f * f * f) == 0) {
        inside /= (f * f * f);
        outside *= f;
      }
    }

    if (outside > 1 || negative) {
      long long outsideFactor = negative ? -outside : outside;
      auto newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(
          SymEngine::mul(coeff, SymEngine::integer(outsideFactor)));
      SymEngine::map_basic_basic newDict(dict);
      newDict.erase(p.first);
      if (inside > 1) {
        newDict[SymEngine::integer(inside)] = SymEngine::rational(1, 3);
      }
      return SymEngine::Mul::from_dict(newCoeff, std::move(newDict));
    }
    break;
  }

  return expr;
}

long long denominatorOf(const SymEngine::RCP<const SymEngine::Number> &num) {
  if (SymEngine::is_a<SymEngine::Rational>(*num)) {
    return std::abs(SymEngine::down_cast<const SymEngine::Rational &>(*num).get_den()->as_int());
  }
  if (SymEngine::is_a<SymEngine::Complex>(*num)) {
    auto &c = SymEngine::down_cast<const SymEngine::Complex &>(*num);
    long long rd = denominatorOf(c.real_part());
    long long id = denominatorOf(c.imaginary_part());
    return std::lcm(rd, id);
  }
  return 1;
}

SymEngine::RCP<const SymEngine::Basic> factorDenominatorFromAdd(
    const SymEngine::RCP<const SymEngine::Basic> &expr) {
  if (!SymEngine::is_a<SymEngine::Mul>(*expr)) {
    return expr;
  }

  auto &m = SymEngine::down_cast<const SymEngine::Mul &>(*expr);
  auto coeff = m.get_coef();
  auto dict = m.get_dict();

  for (auto &entry : dict) {
    if (!SymEngine::is_a<SymEngine::Add>(*entry.first)) {
      continue;
    }
    if (!SymEngine::eq(*entry.second, *SymEngine::integer(1))) {
      continue;
    }

    auto &add = SymEngine::down_cast<const SymEngine::Add &>(*entry.first);
    long long commonDen = denominatorOf(add.get_coef());

    for (auto &term : add.get_dict()) {
      auto termCoeff = term.second;
      if (!SymEngine::is_a<SymEngine::Rational>(*termCoeff) &&
          !SymEngine::is_a<SymEngine::Integer>(*termCoeff) &&
          !SymEngine::is_a<SymEngine::Complex>(*termCoeff)) {
        commonDen = 1;
        break;
      }
      commonDen = std::lcm(commonDen, denominatorOf(
          SymEngine::rcp_static_cast<const SymEngine::Number>(termCoeff)));
    }

    if (commonDen <= 1) {
      continue;
    }

    auto scaledAdd = SymEngine::expand(SymEngine::mul(entry.first, SymEngine::integer(commonDen)));
    auto newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(
        SymEngine::div(coeff, SymEngine::integer(commonDen)));
    SymEngine::map_basic_basic newDict(dict);
    newDict.erase(entry.first);
    newDict[scaledAdd] = SymEngine::integer(1);
    return SymEngine::Mul::from_dict(newCoeff, std::move(newDict));
  }

  return expr;
}

SymEngine::RCP<const SymEngine::Basic> simplifySqrtInSums(
    const SymEngine::RCP<const SymEngine::Basic> &expr) {
  if (SymEngine::is_a<SymEngine::Add>(*expr)) {
    SymEngine::RCP<const SymEngine::Basic> result = SymEngine::integer(0);
    for (const auto &arg : expr->get_args()) {
      result = SymEngine::add(result, simplifySqrtInSums(arg));
    }
    return result;
  }
  return simplifyCubeRootCoefficient(simplifySqrtCoefficient(expr));
}

std::string replaceImaginaryUnit(const std::string &latex) {
  std::string result;
  result.reserve(latex.size());

  for (std::size_t i = 0; i < latex.size(); ++i) {
    if (latex[i] != 'j') {
      result += latex[i];
      continue;
    }

    if (i + 1 < latex.size() && latex[i + 1] == ' ' &&
        i + 2 < latex.size() && latex[i + 2] == '\\') {
      std::size_t cmdEnd = i + 2;
      while (cmdEnd < latex.size() && latex[cmdEnd] != '{') {
        ++cmdEnd;
      }
      if (cmdEnd < latex.size()) {
        int depth = 1;
        std::size_t braceEnd = cmdEnd + 1;
        while (braceEnd < latex.size() && depth > 0) {
          if (latex[braceEnd] == '{') { ++depth; }
          if (latex[braceEnd] == '}') { --depth; }
          ++braceEnd;
        }
        result += latex.substr(i + 2, braceEnd - (i + 2));
        result += " i";
        i = braceEnd - 1;
        continue;
      }
    }

    result += "i";
  }

  return result;
}

SymEngine::RCP<const SymEngine::Basic> distributeCoeffIntoAdd(
    const SymEngine::RCP<const SymEngine::Basic> &expr) {
  if (!SymEngine::is_a<SymEngine::Mul>(*expr)) {
    return expr;
  }

  auto &m = SymEngine::down_cast<const SymEngine::Mul &>(*expr);
  auto coeff = m.get_coef();
  auto dict = m.get_dict();

  SymEngine::RCP<const SymEngine::Basic> numerator;
  SymEngine::RCP<const SymEngine::Number> newCoeff;

  if (SymEngine::is_a<SymEngine::Rational>(*coeff)) {
    auto &rat = SymEngine::down_cast<const SymEngine::Rational &>(*coeff);
    numerator = rat.get_num();
    newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(
        SymEngine::div(SymEngine::integer(1), rat.get_den()));
  } else if (SymEngine::is_a<SymEngine::Integer>(*coeff)) {
    numerator = coeff;
    newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(SymEngine::integer(1));
  } else {
    return expr;
  }

  if (SymEngine::eq(*numerator, *SymEngine::integer(1)) ||
      SymEngine::eq(*numerator, *SymEngine::integer(-1))) {
    return expr;
  }

  for (auto &entry : dict) {
    if (!SymEngine::is_a<SymEngine::Add>(*entry.first)) {
      continue;
    }
    if (!SymEngine::eq(*entry.second, *SymEngine::integer(1))) {
      continue;
    }

    auto distributed = SymEngine::expand(SymEngine::mul(numerator, entry.first));
    SymEngine::map_basic_basic newDict(dict);
    newDict.erase(entry.first);
    newDict[distributed] = SymEngine::integer(1);
    return SymEngine::Mul::from_dict(newCoeff, std::move(newDict));
  }

  return expr;
}

std::string insertCdot(const std::string &latex) {
  std::string result;
  result.reserve(latex.size() + 16);
  for (std::size_t i = 0; i < latex.size(); ++i) {
    result += latex[i];
    if (std::isdigit(latex[i]) && i + 2 < latex.size() &&
        latex[i + 1] == ' ' && std::isdigit(latex[i + 2])) {
      result += " \\cdot";
    }
  }
  return result;
}

}

extern "C" const char *symengine_simplify_expression(const char *expression) {
  if (expression == nullptr) {
    return nullptr;
  }

  try {
    const std::string input(expression);
    if (input.empty() || input.back() != '=') {
      return nullptr;
    }

    const std::string normalized = latexToSymEngine(input.substr(0, input.size() - 1));
    const SymEngine::RCP<const SymEngine::Basic> parsed = SymEngine::parse(normalized);

    if (!SymEngine::free_symbols(*parsed).empty()) {
      return nullptr;
    }

    const SymEngine::RCP<const SymEngine::Basic> simplified = SymEngine::simplify(parsed);

    if (SymEngine::is_a<SymEngine::Rational>(*simplified)) {
      if (inputHasUnsimplifiedFraction(expression)) {
        const std::string result = SymEngine::latex(*simplified);
        return strdup(result.c_str());
      }
      const std::string result = rationalToDecimalString(simplified, 3);
      return strdup(result.c_str());
    }

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

    const bool lhsIsSym = SymEngine::eq(*lhs, *sym);
    const bool rhsIsSym = SymEngine::eq(*rhs, *sym);
    if (lhsIsSym && SymEngine::free_symbols(*rhs).empty()) {
      return nullptr;
    }
    if (rhsIsSym && SymEngine::free_symbols(*lhs).empty()) {
      return nullptr;
    }

    const auto solutionSet = SymEngine::solve(equation, sym);

    if (SymEngine::is_a<SymEngine::FiniteSet>(*solutionSet)) {
      const auto &finite = SymEngine::down_cast<const SymEngine::FiniteSet &>(*solutionSet);
      const auto &elements = finite.get_container();
      if (elements.empty()) {
        return nullptr;
      }

      SymEngine::map_basic_basic oddRootSubs;
      oddRootSubs[SymEngine::pow(SymEngine::integer(-1), SymEngine::rational(1, 3))] =
          SymEngine::integer(-1);

      std::ostringstream oss;
      oss << SymEngine::latex(*sym) << "=";
      bool first = true;
      for (const auto &elem : elements) {
        if (!first) {
          oss << ", ";
        }
        auto simplified = SymEngine::simplify(SymEngine::simplify(elem)->subs(oddRootSubs));
        simplified = simplifyCubeRootCoefficient(simplified);
        simplified = distributeCoeffIntoAdd(simplified);
        simplified = factorDenominatorFromAdd(simplified);
        simplified = simplifySqrtInSums(simplified);
        oss << SymEngine::latex(*simplified);
        first = false;
      }
      const std::string result = insertCdot(replaceImaginaryUnit(oss.str()));
      return strdup(result.c_str());
    }

    return nullptr;
  } catch (...) {
    return nullptr;
  }
}

extern "C" void symengine_free_string(const char *value) {
  std::free(const_cast<char *>(value));
}
