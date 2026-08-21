#include "LatexFormatting.h"

#include <cctype>

#if !TARGET_OS_SIMULATOR
#include <iomanip>
#include <sstream>
#include <symengine/eval_double.h>

std::string rationalToDecimalString(
    const SymEngine::RCP<const SymEngine::Basic> &expr, int precision) {
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
#endif

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
