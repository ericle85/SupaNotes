#ifndef SYMENGINE_CONFIG_CLING_HPP
#define SYMENGINE_CONFIG_CLING_HPP

#ifdef __CLING__

#pragma cling add_library_path("/tmp/symengine-ios-device/install/lib")
#pragma cling load("libsymengine")

#elif defined(__EMSCRIPTEN__) && defined(__CLANG_REPL__)

#include <clang/Interpreter/CppInterOp.h>
static bool _symengine_loaded = []() {
    Cpp::LoadLibrary("/lib/libsymengine.dylib", false);
    return true;
}();

#endif

#endif // SYMENGINE_CONFIG_CLING_HPP
