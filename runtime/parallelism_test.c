#define _GNU_SOURCE
#undef NDEBUG
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <sys/sysctl.h>
#include <string.h>
static int simulated_cpu_count = -1;
static int parallelism_sysctl(const char *name, void *out, size_t *bytes, void *input, size_t input_bytes) {
    if (simulated_cpu_count < 0) return sysctlbyname(name, out, bytes, input, input_bytes);
    assert(strcmp(name, "hw.activecpu") == 0);
    assert(*bytes == sizeof(int));
    *(int *)out = simulated_cpu_count;
    return 0;
}
#define sysctlbyname parallelism_sysctl
#endif
#define LINEA_PARALLELISM_TEST
#include "parallelism.c"

static FILE *fixture(const char *text) {
    FILE *file = tmpfile();
    assert(file);
    assert(fputs(text, file) >= 0);
    rewind(file);
    return file;
}

static void mount_fixture(const char *group, const char *mounts, const char *expected, const char *root) {
    FILE *groups = fixture(group);
    FILE *info = fixture(mounts);
    char directory[PATH_MAX], mount[PATH_MAX];
    int found = resolve_cgroup_mount(groups, info, directory, mount);
    assert(found == (expected != NULL));
    if (found) {
        assert(strcmp(directory, expected) == 0);
        assert(strcmp(mount, root) == 0);
    }
    fclose(groups);
    fclose(info);
}

static void cgroup_fixtures(void) {
    mount_fixture("0::/team/job\n", "21 20 0:27 / /custom/cpus rw - cgroup2 cgroup rw\n", "/custom/cpus/team/job", "/custom/cpus");
    mount_fixture("0::/tenant\n", "21 20 0:27 /tenant /container/cpus rw - cgroup2 cgroup rw\n", "/container/cpus", "/container/cpus");
    mount_fixture("0::/tenant/job\n", "21 20 0:27 /tenant /container/cpus rw - cgroup2 cgroup rw\n", "/container/cpus/job", "/container/cpus");
    mount_fixture("0::/\n", "21 20 0:27 / /container/cpus rw - cgroup2 cgroup rw\n", "/container/cpus", "/container/cpus");
    mount_fixture("0::/team space/job\n", "21 20 0:27 /team\\040space /cpu\\040space\\134root rw - cgroup2 cgroup rw\n", "/cpu space\\root/job", "/cpu space\\root");
    mount_fixture("0::/tenant-other/job\n", "21 20 0:27 /tenant /cpus rw - cgroup2 cgroup rw\n", NULL, NULL);
    mount_fixture("0::/team/../job\n", "21 20 0:27 / /cpus rw - cgroup2 cgroup rw\n", NULL, NULL);
    mount_fixture("0::relative\n", "21 20 0:27 / /cpus rw - cgroup2 cgroup rw\n", NULL, NULL);
    mount_fixture("0::/team\n", "21 20 0:27 / /bad\\999path rw - cgroup2 cgroup rw\n", NULL, NULL);
    mount_fixture("0::/team\n", "21 20 0:27 / /cpus rw - ext4 disk rw\n", NULL, NULL);
    mount_fixture("0::/team\n", "broken mountinfo\n", NULL, NULL);
    mount_fixture("1:cpu:/team\n", "21 20 0:27 / /cpus rw - cgroup2 cgroup rw\n", NULL, NULL);

    char temporary[] = "/tmp/linea-cpus-XXXXXX";
    char *root = mkdtemp(temporary);
    assert(root);
    char child[PATH_MAX], quota[PATH_MAX], mounts[PATH_MAX + 100];
    assert(snprintf(child, sizeof child, "%s/job", root) > 0);
    assert(mkdir(child, 0700) == 0);
    assert(snprintf(quota, sizeof quota, "%s/cpu.max", root) > 0);
    FILE *limit = fopen(quota, "w");
    assert(limit);
    assert(fputs("150000 100000\n", limit) >= 0);
    assert(fclose(limit) == 0);
    char child_quota[PATH_MAX];
    assert(snprintf(child_quota, sizeof child_quota, "%s/cpu.max", child) > 0);
    limit = fopen(child_quota, "w");
    assert(limit);
    assert(fputs("max 100000\n", limit) >= 0);
    assert(fclose(limit) == 0);
    assert(snprintf(mounts, sizeof mounts, "21 20 0:27 /tenant %s rw - cgroup2 cgroup rw\n", root) > 0);
    FILE *groups = fixture("0::/tenant/job\n"), *info = fixture(mounts);
    assert(quota_count_from(groups, info, 8) == 2);
    fclose(groups);
    fclose(info);
    assert(unlink(child_quota) == 0);
    assert(unlink(quota) == 0);
    assert(rmdir(child) == 0);
    assert(rmdir(root) == 0);
}

int main(void) {
    cgroup_fixtures();
    assert(quota_bound("max 100000\n") == 0);
    assert(quota_bound("1 100000\n") == 1);
    assert(quota_bound("200001 100000\n") == 3);
    assert(quota_bound("200000 100000\n") == 2);
    assert(quota_bound("0 100000\n") == 0);
    assert(quota_bound("100000 0\n") == 0);
    assert(quota_bound("-1 100000\n") == 0);
    assert(quota_bound("100000 -1\n") == 0);
    assert(quota_bound("18446744073709551615 2\n") == ULONG_MAX / 2 + 1);
    assert(quota_bound("18446744073709551616 1\n") == 0);
    assert(quota_bound("100000 100000 extra\n") == 0);
    assert(quota_bound("maximal 100000\n") == 0);
    assert(quota_bound("") == 0);
    assert(linea_available_parallelism() >= 1);
    assert(linea_available_parallelism() >= 1);
#if defined(__linux__)
    cpu_set_t original;
    if (sched_getaffinity(0, sizeof original, &original) == 0) {
        cpu_set_t single;
        CPU_ZERO(&single);
        for (int i = 0; i < CPU_SETSIZE; ++i) {
            if (CPU_ISSET(i, &original)) {
                CPU_SET(i, &single);
                break;
            }
        }
        assert(sched_setaffinity(0, sizeof single, &single) == 0);
        assert(linea_available_parallelism() == 1);
        assert(sched_setaffinity(0, sizeof original, &original) == 0);
    }
#endif
#if defined(__APPLE__)
    simulated_cpu_count = 7;
    assert(linea_available_parallelism() == 7);
    simulated_cpu_count = 2;
    assert(linea_available_parallelism() == 2);
    simulated_cpu_count = 0;
    assert(linea_available_parallelism() == 1);
#endif
    return 0;
}
