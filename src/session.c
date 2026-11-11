#include "onlinefix.h"
#include <ctype.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
// shortcut: one active game per Steam process; use per-pipe sessions before supporting concurrent games.
static OFSession current;

bool of_argument(const char *command, const char *argument) {
    if (!command || !argument || !*argument) return false;
    const size_t length = strlen(argument);
    while (*command) {
        size_t position = 0;
        bool same = true;
        char delimiter = 0;
        while (isspace((unsigned char)*command)) ++command;
        if (!*command) break;
        do {
            char c = *command++;
            if (c == delimiter) { delimiter = 0; continue; }
            if (!delimiter && (c == '"' || c == '\'')) { delimiter = c; continue; }
            if (c == '\\' && delimiter != '\'' && *command) c = *command++;
            if (position >= length || c != argument[position]) same = false;
            ++position;
        } while (*command && (delimiter || !isspace((unsigned char)*command)));
        if (!delimiter && same && position == length) return true;
    }
    return false;
}

// A compat-tool launch can be routed late when the game opts in. The automatic
// mode keeps the proven early SpawnProcess rewrite; direct launches without a
// SpawnProcess session are always routed late by of_route_pipe().
bool of_wine_command(const char *command) {
    if (!command) return false;
    static const char *const markers[] = {
        "/CrossOver/", "CrossOver.app/", "/notproton/", "NotProton.app/",
        "wine64", "wine-preloader", "wineserver", ".exe",
    };
    for (size_t i = 0; i < sizeof(markers) / sizeof(markers[0]); ++i)
        if (strstr(command, markers[i])) return true;
    return false;
}

OFSession of_session(void) {
    pthread_mutex_lock(&lock);
    OFSession result = current;
    pthread_mutex_unlock(&lock);
    return result;
}

static void publish(OFSession next) {
    pthread_mutex_lock(&lock);
    next.generation = current.generation + 1;
    current = next;
    pthread_mutex_unlock(&lock);
}

void of_start(const char *command, uint64_t *game) {
    OFSession next = {.patches = OF_DEFAULT_PATCHES};
    if (game && *game > 0 && *game <= 0xffffff && *game != 480) {
        bool keep = false;
        OFRoute route = OF_ROUTE_AUTO;
        bool configured = of_config_game((uint32_t)*game, &keep, &route, &next.patches);
        if (configured || of_argument(command, "-onlinefix")) {
            next.game = (uint32_t)*game;
            next.keep_id = keep || of_argument(command, "-realappid");
            next.late = route == OF_ROUTE_LATE;
            if (!next.late) *game = 480;
            of_log("launch game=%u mode=%s keep-id=%d compat=%d command=%.180s", next.game,
                   next.late ? "late" : "early", next.keep_id, of_wine_command(command),
                   command ? command : "");
        }
    }
    publish(next);
    if (next.game) {
        of_log("session active game=%u pipe=480 keep-id=%d", next.game, next.keep_id);
        of_log("patches game=%u: startup-id=%d overlay-id=%d input-id=%d stats-id=%d", next.game,
               next.patches.startup_id, next.patches.overlay_id, next.patches.input_id, next.patches.stats_id);
    }
}

// A configured game can connect without a SpawnProcess session: launched from
// Finder, a third-party launcher, or a wrapper. Route it when its pipe appears.
// A later direct launch replaces the previous session, so game A does not block
// game B after A exits.
bool of_route_pipe(uint32_t game) {
    if (!game || game == 480) return false;
    OFSession active = of_session();
    if (active.game == game) return false;
    bool keep = false;
    OFRoute route = OF_ROUTE_AUTO;
    OFPatches patches = OF_DEFAULT_PATCHES;
    if (!of_config_game(game, &keep, &route, &patches)) return false;
    OFSession next = {.game = game, .keep_id = keep, .late = true, .patches = patches};
    publish(next);
    of_log("pipe launch game=%u mode=late keep-id=%d%s", game, keep,
           active.game ? " (replacing previous session)" : " (no SpawnProcess session)");
    return true;
}

void of_networking(void) {
    pthread_mutex_lock(&lock);
    bool changed = current.game && !current.networking;
    if (current.game) current.networking = true;
    pthread_mutex_unlock(&lock);
    if (changed) of_log("networking active: matchmaking uses 480");
}
