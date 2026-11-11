#include "onlinefix.h"
#include "../vendor/cJSON.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool read_route(const cJSON *entry, OFRoute *route) {
    const cJSON *value = cJSON_GetObjectItemCaseSensitive(entry, "route");
    if (!value) { *route = OF_ROUTE_AUTO; return true; }
    if (!cJSON_IsString(value)) return false;
    if (!strcmp(value->valuestring, "auto")) *route = OF_ROUTE_AUTO;
    else if (!strcmp(value->valuestring, "early")) *route = OF_ROUTE_EARLY;
    else if (!strcmp(value->valuestring, "late")) *route = OF_ROUTE_LATE;
    else return false;
    return true;
}

// Read at launch time so Manager changes don't require restarting Steam.
bool of_config_game(uint32_t game, bool *keep_id, OFRoute *route, OFPatches *patches) {
    const char *path = getenv("ONLINEFIX_CONFIG");
    if (!path || !*path) return false;
    FILE *file = fopen(path, "rb");
    if (!file) { of_log("cannot read game config: %s", path); return false; }
    char *raw = malloc(1024 * 1024 + 1);
    if (!raw) { fclose(file); return false; }
    size_t size = fread(raw, 1, 1024 * 1024 + 1, file);
    bool valid = !ferror(file) && size > 0 && size <= 1024 * 1024;
    fclose(file);
    if (valid) raw[size] = '\0';
    cJSON *root = valid ? cJSON_ParseWithLengthOpts(raw, size + 1, NULL, true) : NULL;
    free(raw);
    cJSON *games = cJSON_GetObjectItemCaseSensitive(root, "games");
    valid = cJSON_IsArray(games);
    bool found = false, keep = false;
    OFRoute selected_route = OF_ROUTE_AUTO;
    OFPatches selected = OF_DEFAULT_PATCHES;
    cJSON *entry;
    cJSON_ArrayForEach(entry, games) {
        cJSON *id = cJSON_GetObjectItemCaseSensitive(entry, "id");
        cJSON *real = cJSON_GetObjectItemCaseSensitive(entry, "keepRealAppID");
        OFPatches parsed;
        OFRoute parsed_route;
        if (!cJSON_IsNumber(id) || id->valuedouble < 1 || id->valuedouble > 0xffffff ||
            id->valuedouble != (double)id->valueint || id->valueint == 480 ||
            !cJSON_IsBool(real) || !of_patches_read(cJSON_GetObjectItemCaseSensitive(entry, "patches"), &parsed) ||
            !read_route(entry, &parsed_route)) {
            valid = false; break;
        }
        if (parsed.terraria_server && id->valueint != 105600) { valid = false; break; }
        if ((uint32_t)id->valueint == game) {
            if (found) { valid = false; break; }
            found = true;
            keep = cJSON_IsTrue(real);
            selected_route = parsed_route;
            selected = parsed;
        }
    }
    cJSON_Delete(root);
    if (!valid) of_log("invalid game config; automatic routing skipped: %s", path);
    if (valid && found) {
        *keep_id = keep;
        if (route) *route = selected_route;
        *patches = selected;
    }
    return valid && found;
}
