#include "SymEngineBridge.h"

#include <cstdlib>
#include <cstring>
#include <map>
#include <string>

#include <symengine/basic.h>
#include <symengine/parser.h>
#include <symengine/printers.h>
#include <symengine/simplify.h>
#include <symengine/visitor.h>

namespace {

std::string normalizeExpression(const std::string &expression) {
  std::string normalized = expression;
  const std::size_t equalsPosition = normalized.find_last_of('=');

  if (equalsPosition != std::string::npos && equalsPosition == normalized.size() - 1) {
    normalized.erase(equalsPosition);
  }

  return normalized;
}

}

extern "C" const char *symengine_simplify_expression(const char *expression) {
  if (expression == nullptr) {
    return nullptr;
  }

  try {
    const std::string normalized = normalizeExpression(expression);
    const SymEngine::RCP<const SymEngine::Basic> parsed = SymEngine::parse(normalized);

    if (!SymEngine::free_symbols(*parsed).empty()) {
      return nullptr;
    }

    const SymEngine::RCP<const SymEngine::Basic> simplified = SymEngine::simplify(parsed);
    const std::string result = SymEngine::str(*simplified);
    return strdup(result.c_str());
  } catch (...) {
    return nullptr;
  }
}

extern "C" void symengine_free_string(const char *value) {
  std::free(const_cast<char *>(value));
}
