/* Minimal liblog/log.h replacement for NDK builds. */
#pragma once
#include <android/log.h>
#ifndef LOG_PRI
#define LOG_PRI(prio, tag, ...) __android_log_print(prio, tag, __VA_ARGS__)
#endif
