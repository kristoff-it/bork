#include <stdlib.h>

struct MemoryStruct {
  char *memory;
  size_t size;
};

int getEmotes(char *url, struct MemoryStruct *chunk);
