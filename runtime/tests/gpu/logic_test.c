#include "probe.h"
#include <assert.h>
#include <stdio.h>

void check_float_references(void);

int main(void) {
    check_float_references();
    size_t selected = 99;
    assert(!probe_select_device(NULL, 0, &selected));
    const struct probe_candidate candidates[] = {
        { .vendor = 0x106b, .hardware = 0, .compute = 1, .api = PROBE_MIN_API },
        { .vendor = 0x10de, .hardware = 1, .compute = 1, .api = PROBE_MIN_API },
        { .vendor = 0x106b, .hardware = 1, .compute = 0, .api = PROBE_MIN_API },
        { .vendor = 0x106b, .hardware = 1, .compute = 1, .api = PROBE_MIN_API },
        { .vendor = 0x106b, .hardware = 1, .compute = 1, .api = PROBE_MIN_API },
    };
    assert(!probe_select_device(candidates, 1, &selected));
    assert(!probe_select_device(candidates + 1, 1, &selected));
    assert(!probe_select_device(candidates + 2, 1, &selected));
    assert(probe_select_device(candidates, 5, &selected));
    assert(selected == 3);
    uint32_t groups = 99;
    assert(probe_workgroups(0, 65535, &groups) && groups == 0);
    assert(probe_workgroups(1, 65535, &groups) && groups == 1);
    assert(probe_workgroups(1000, 65535, &groups) && groups == 16);
    assert(probe_workgroups(1024, 65535, &groups) && groups == 16);
    assert(!probe_workgroups(UINT64_MAX, 65535, &groups));
    assert(!probe_workgroups(1024, 15, &groups));
    uint64_t bytes = 0;
    assert(probe_buffer_bytes(1000, 4096, &bytes) && bytes == 4008);
    assert(!probe_buffer_bytes(UINT32_MAX, UINT64_MAX, &bytes));
    assert(!probe_buffer_bytes(1000, 4007, &bytes));
    const uint32_t expected[] = { 11, 22, 33 };
    uint32_t got[] = { 0x12345678, 11, 22, 33, 0x12345678 };
    assert(probe_check_words(expected, got, 3) == PROBE_OK);
    got[2] = 23;
    assert(probe_check_words(expected, got, 3) == PROBE_MISMATCH);
    got[2] = 22;
    got[4] = 0;
    assert(probe_check_words(expected, got, 3) == PROBE_MISMATCH);
    assert(probe_compare_word("identity", 0x7fc12345, 0, 0x7fc12345, 0x7fc12345) == PROBE_OK);
    assert(probe_compare_word("identity", 0x7fc12345, 0, 0x7fc00000, 0x7fc12345) == PROBE_MISMATCH);
    assert(probe_compare_word("add", 0, 0, 0xffc00000, 0x7fc00000) == PROBE_MISMATCH);
    assert(probe_compare_word("divide", 0, 0, 0x3eaaaaaa, 0x3eaaaaab) == PROBE_MISMATCH);
    for (unsigned mask = 0; mask < 8; ++mask)
        assert(probe_float_profile(mask & 1, mask & 2, mask & 4) == mask);
    puts("GPU probe policies passed");
    return 0;
}
