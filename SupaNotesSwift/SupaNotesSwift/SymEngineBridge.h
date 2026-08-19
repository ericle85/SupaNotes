#import <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *symengine_simplify_expression(const char *expression);
const char *symengine_solve_equation(const char *expression);
void symengine_free_string(const char *value);

#ifdef __cplusplus
}
#endif
