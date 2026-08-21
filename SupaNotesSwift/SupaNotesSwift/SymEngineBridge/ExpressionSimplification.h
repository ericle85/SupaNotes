#pragma once

#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR
#include <symengine/basic.h>

SymEngine::RCP<const SymEngine::Basic> simplifySqrtCoefficient(
    const SymEngine::RCP<const SymEngine::Basic> &expr);

SymEngine::RCP<const SymEngine::Basic> simplifyCubeRootCoefficient(
    const SymEngine::RCP<const SymEngine::Basic> &expr);

SymEngine::RCP<const SymEngine::Basic> simplifySqrtInSums(
    const SymEngine::RCP<const SymEngine::Basic> &expr);

SymEngine::RCP<const SymEngine::Basic> distributeCoeffIntoAdd(
    const SymEngine::RCP<const SymEngine::Basic> &expr);

SymEngine::RCP<const SymEngine::Basic> factorDenominatorFromAdd(
    const SymEngine::RCP<const SymEngine::Basic> &expr);

#endif
