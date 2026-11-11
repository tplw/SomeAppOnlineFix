#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include "patch/patch.h"

typedef enum {
    OF_ROUTE_AUTO = 0,
    OF_ROUTE_EARLY,
    OF_ROUTE_LATE,
} OFRoute;

typedef struct {
    uint32_t game;
    bool keep_id, networking, late;
    uint64_t generation;
    OFPatches patches;
} OFSession;

bool of_argument(const char *command, const char *argument);
bool of_wine_command(const char *command);
bool of_config_game(uint32_t game, bool *keep_id, OFRoute *route, OFPatches *patches);
void of_start(const char *command, uint64_t *game);
bool of_route_pipe(uint32_t game);
OFSession of_session(void);
uint32_t of_identity(OFSession session, uint32_t reported);
void of_patch_overlay(OFSession session, const uint64_t *game, uint64_t *overlay);
uint32_t of_patch_input(OFSession session, uint32_t reported);
bool of_patch_stats(OFSession session, int kind, const void *payload, int size, unsigned char output[20]);
void of_log(const char *format, ...);
bool of_install(const char *profile);
void of_filter_children(void);
extern _Atomic bool of_ready;
