/* Generated entry stub. Zig owns registration; R owns final shared linking. */
#include <R_ext/Visibility.h>

typedef struct _DllInfo DllInfo;
void rzig_init(DllInfo *dll);

void attribute_visible R_init_rzigtest(DllInfo *dll) {
    rzig_init(dll);
}
