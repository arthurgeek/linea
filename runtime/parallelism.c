#define _GNU_SOURCE
#include "parallelism.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__linux__)
#include <sched.h>
#include <unistd.h>
#elif defined(__APPLE__)
#include <sys/sysctl.h>
#endif

#if defined(__linux__) || defined(LINEA_PARALLELISM_TEST)
/* Zero means no usable limit. Avoid adding period - 1 to an untrusted quota. */
static unsigned long quota_bound(const char *text) {
    while (isspace((unsigned char)*text)) ++text;
    if (!isdigit((unsigned char)*text)) return 0;
    errno = 0;
    char *end;
    unsigned long quota = strtoul(text, &end, 10);
    if (errno || !quota || !isspace((unsigned char)*end)) return 0;
    text = end;
    while (isspace((unsigned char)*text)) ++text;
    if (!isdigit((unsigned char)*text)) return 0;
    errno = 0;
    unsigned long period = strtoul(text, &end, 10);
    if (errno || !period) return 0;
    while (isspace((unsigned char)*end)) ++end;
    if (*end) return 0;
    return quota / period + (quota % period != 0);
}

/* Proc paths are absolute and contain no traversal components. */
static int absolute_path(const char *path) {
    if (*path != '/') return 0;
    const char *part = path + 1;
    for (;;) {
        const char *end = (strchr)(part, '/');
        size_t length = end ? (size_t)(end - part) : strlen(part);
        if ((length == 1 && part[0] == '.') ||
            (length == 2 && part[0] == '.' && part[1] == '.')) return 0;
        if (!end) break;
        part = end + 1;
    }
    return 1;
}

/* mountinfo escapes whitespace and backslash as octal sequences. */
static int unescape_mount(char *path) {
    char *out = path;
    for (const char *in = path; *in; ++in) {
        if (*in != '\\') {
            *out++ = *in;
            continue;
        }
        if (!in[1] || !in[2] || !in[3]) return 0;
        int value;
        if (strncmp(in + 1, "040", 3) == 0) value = ' ';
        else if (strncmp(in + 1, "011", 3) == 0) value = '\t';
        else if (strncmp(in + 1, "012", 3) == 0) value = '\n';
        else if (strncmp(in + 1, "134", 3) == 0) value = '\\';
        else return 0;
        *out++ = (char)value;
        in += 3;
    }
    *out = 0;
    return absolute_path(path);
}

static char *mount_field(char **cursor) {
    char *start = *cursor;
    while (*start == ' ' || *start == '\t') ++start;
    if (!*start || *start == '\n') return NULL;
    char *end = start;
    while (*end && *end != ' ' && *end != '\t' && *end != '\n') ++end;
    *cursor = *end ? end + 1 : end;
    if (*end) *end = 0;
    return start;
}

static int resolve_cgroup_mount(FILE *groups, FILE *info, char directory[PATH_MAX], char mount[PATH_MAX]) {
    char group[PATH_MAX] = "";
    char line[PATH_MAX * 3];
    while (fgets(line, sizeof line, groups)) {
        if (strncmp(line, "0::", 3) != 0) continue;
        line[strcspn(line, "\r\n")] = 0;
        if (strlen(line + 3) >= sizeof group || !absolute_path(line + 3)) return 0;
        strcpy(group, line + 3);
        break;
    }
    if (!*group) return 0;
    size_t best_root = SIZE_MAX;
    int found = 0;
    while (fgets(line, sizeof line, info)) {
        /* Discard an overlong record, never parse a truncated mount path. */
        if (!(strchr)(line, '\n') && !feof(info)) {
            int next;
            while ((next = fgetc(info)) != '\n' && next != EOF) {}
            continue;
        }
        char *cursor = line;
        char *fields[6];
        int complete = 1;
        for (size_t i = 0; i < 6; ++i) {
            fields[i] = mount_field(&cursor);
            if (!fields[i]) { complete = 0; break; }
        }
        if (!complete) continue;
        char *field;
        while ((field = mount_field(&cursor)) && strcmp(field, "-") != 0) {}
        if (!field) continue;
        char *filesystem = mount_field(&cursor);
        if (!filesystem || strcmp(filesystem, "cgroup2") != 0 ||
            !mount_field(&cursor) || !mount_field(&cursor)) continue;
        char *root = fields[3], *point = fields[4];
        if (!unescape_mount(root) || !unescape_mount(point)) continue;
        size_t root_length = strlen(root), point_length = strlen(point);
        if (root_length > 1 && (strncmp(group, root, root_length) != 0 ||
            (group[root_length] && group[root_length] != '/'))) continue;
        const char *suffix = root_length == 1 ? group : group + root_length;
        if (strcmp(suffix, "/") == 0) suffix = "";
        if (point_length > 1 && point[point_length - 1] == '/') point[--point_length] = 0;
        if (strcmp(point, "/") == 0 && *suffix == '/') ++suffix;
        if (point_length + strlen(suffix) >= PATH_MAX || root_length >= best_root) continue;
        strcpy(directory, point);
        strcat(directory, suffix);
        strcpy(mount, point);
        best_root = root_length;
        found = 1;
    }
    return found;
}

static unsigned long read_quota(const char *directory) {
    char filename[PATH_MAX];
    if (snprintf(filename, sizeof filename, "%s/cpu.max", directory) >= (int)sizeof filename) return 0;
    FILE *file = fopen(filename, "r");
    if (!file) return 0;
    char text[128];
    unsigned long bound = fgets(text, sizeof text, file) ? quota_bound(text) : 0;
    fclose(file);
    return bound;
}


static unsigned long quota_count_from(FILE *groups, FILE *info, unsigned long count) {
    char directory[PATH_MAX], mount[PATH_MAX];
    if (!resolve_cgroup_mount(groups, info, directory, mount)) return count;
    size_t root_length = strlen(mount);
    /* Every visible parent limit constrains a child whose own quota is max. */
    for (;;) {
        unsigned long bound = read_quota(directory);
        if (bound && bound < count) count = bound;
        if (strlen(directory) <= root_length) break;
        char *slash = (strrchr)(directory, '/');
        if (!slash) break;
        if (slash == directory && root_length == 1) directory[1] = 0;
        else if ((size_t)(slash - directory) >= root_length) *slash = 0;
        else break;
    }
    return count;
}

#endif

#if defined(__linux__)
static unsigned long affinity_count(void) {
    /* The kernel's affinity mask may exceed libc's fixed CPU_SETSIZE. */
    for (size_t cpus = 128; cpus <= 1048576; cpus *= 2) {
        size_t bytes = CPU_ALLOC_SIZE(cpus);
        cpu_set_t *mask = CPU_ALLOC(cpus);
        if (!mask) return 1;
        CPU_ZERO_S(bytes, mask);
        int result = sched_getaffinity(0, bytes, mask);
        int failure = errno;
        unsigned long count = result == 0 ? (unsigned long)CPU_COUNT_S(bytes, mask) : 0;
        CPU_FREE(mask);
        if (result == 0) return count ? count : 1;
        if (failure != EINVAL) return 1;
    }
    return 1;
}

static unsigned long quota_count(unsigned long count) {
    FILE *groups = fopen("/proc/self/cgroup", "r");
    FILE *info = fopen("/proc/self/mountinfo", "r");
    if (groups && info) count = quota_count_from(groups, info, count);
    if (groups) fclose(groups);
    if (info) fclose(info);
    return count;
}

#endif

unsigned long linea_available_parallelism(void) {
#if defined(__linux__)
    return quota_count(affinity_count());
#elif defined(__APPLE__)
    int count = 0;
    size_t bytes = sizeof count;
    if (sysctlbyname("hw.activecpu", &count, &bytes, NULL, 0) == 0 && count > 0)
        return (unsigned long)count;
    return 1;
#else
    return 1;
#endif
}
