#pragma once

#include <TargetConditionals.h>
#include <string>

#if !TARGET_OS_SIMULATOR
#include <symengine/basic.h>

std::string rationalToDecimalString(
    const SymEngine::RCP<const SymEngine::Basic> &expr, int precision);
#endif

std::string replaceImaginaryUnit(const std::string &latex);
std::string insertCdot(const std::string &latex);
