/* Minimal libcutils replacement for NDK builds: property_get via bionic. */
#pragma once
#include <string.h>
#include <sys/system_properties.h>
#define PROPERTY_KEY_MAX 32
#define PROPERTY_VALUE_MAX PROP_VALUE_MAX
static inline int property_get(const char *key, char *value, const char *default_value)
{
   int len = __system_property_get(key, value);
   if (len <= 0 && default_value) {
      strncpy(value, default_value, PROPERTY_VALUE_MAX - 1);
      value[PROPERTY_VALUE_MAX - 1] = 0;
      len = (int)strlen(value);
   }
   return len;
}
