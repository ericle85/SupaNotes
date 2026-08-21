#include "../SymEngineBridge.h"
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

#include <cstdlib>

extern "C" const char *symengine_simplify_expression(const char *expression) {
  return nullptr;
}

extern "C" const char *symengine_solve_equation(const char *expression) {
  return nullptr;
}

extern "C" void symengine_free_string(const char *value) {
  std::free(const_cast<char *>(value));
}

#else

#include "ExpressionSimplification.h"
#include "LatexFormatting.h"
#include "LatexParsing.h"

#include <cstring>
#include <sstream>
#include <string>

#include <symengine/parser.h>
#include <symengine/printers.h>
#include <symengine/rational.h>
#include <symengine/sets.h>
#include <symengine/simplify.h>
#include <symengine/solve.h>
#include <symengine/visitor.h>
#include <symengine/pow.h>
#include <symengine/integer.h>

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
    const auto parsed = SymEngine::parse(normalized);

    if (!SymEngine::free_symbols(*parsed).empty()) {
      return nullptr;
    }

    const auto simplified = SymEngine::simplify(parsed);

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

    if (!SymEngine::is_a<SymEngine::FiniteSet>(*solutionSet)) {
      return nullptr;
    }

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
  } catch (...) {
    return nullptr;
  }
}

extern "C" void symengine_free_string(const char *value) {
  std::free(const_cast<char *>(value));
}

#endif
