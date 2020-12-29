#include <stdlib.h>

struct slice {
  char *memory;
  size_t size;
};

int getEmotes(char *url, struct slice *chunk);
