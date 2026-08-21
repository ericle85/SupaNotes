#pragma once

#include <string>

std::string extractBracedGroup(const std::string &input, std::size_t &pos);
std::string latexToSymEngine(const std::string &input);
bool inputHasUnsimplifiedFraction(const std::string &raw);
