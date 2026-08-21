#include "ExpressionSimplification.h"

#if !TARGET_OS_SIMULATOR

#include <cstdlib>
#include <numeric>

#include <symengine/add.h>
#include <symengine/complex.h>
#include <symengine/integer.h>
#include <symengine/mul.h>
#include <symengine/number.h>
#include <symengine/pow.h>
#include <symengine/rational.h>
#include <symengine/simplify.h>
#include <symengine/visitor.h>

static long long extractSqrtFactor(long long &inside) {
  long long outside = 1;
  for (long long f = 2; f * f <= inside; ++f) {
    while (inside % (f * f) == 0) {
      inside /= (f * f);
      outside *= f;
    }
  }
  return outside;
}

static long long extractCubeRootFactor(long long &inside) {
  long long outside = 1;
  for (long long f = 2; f * f * f <= inside; ++f) {
    while (inside % (f * f * f) == 0) {
      inside /= (f * f * f);
      outside *= f;
    }
  }
  return outside;
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
    long long inside = n;
    long long outside = extractSqrtFactor(inside);

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
    long long inside = std::abs(n);
    long long outside = extractCubeRootFactor(inside);

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

static long long denominatorOf(const SymEngine::RCP<const SymEngine::Number> &num) {
  if (SymEngine::is_a<SymEngine::Rational>(*num)) {
    return std::abs(
        SymEngine::down_cast<const SymEngine::Rational &>(*num).get_den()->as_int());
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

    auto scaledAdd = SymEngine::expand(
        SymEngine::mul(entry.first, SymEngine::integer(commonDen)));
    auto newCoeff = SymEngine::rcp_static_cast<const SymEngine::Number>(
        SymEngine::div(coeff, SymEngine::integer(commonDen)));
    SymEngine::map_basic_basic newDict(dict);
    newDict.erase(entry.first);
    newDict[scaledAdd] = SymEngine::integer(1);
    return SymEngine::Mul::from_dict(newCoeff, std::move(newDict));
  }

  return expr;
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

#endif
