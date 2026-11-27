#!/usr/bin/env bash
# Run inside nix develop .#cpu. No GPU SDK or loader belongs to that shell.
set -euo pipefail
case ":$PATH:" in
  *":$PWD/zig-out/bin:"*) ;;
  *) echo 'CPU shell lost the common checkout PATH setup' >&2; exit 1 ;;
esac
if test "${1-}" = --check-shell; then
  echo 'CPU shell retains common checkout setup'
  exit 0
fi
cpu_scratch=${1:?usage: cpu-only.sh ABSOLUTE-SCRATCH-DIRECTORY [GPU-CONTROL-COMPILER]}
gpu_control_compiler=${2-}
mkdir -p "$cpu_scratch"
cpu_scratch=$(cd "$cpu_scratch" && pwd)
mkdir -p "$cpu_scratch/bin" "$cpu_scratch/poison/include/vulkan"
printf '%s\n' '#error CPU-only builds must not include Vulkan headers' > "$cpu_scratch/poison/include/vulkan/vulkan.h"
export LINEA_CPU_REAL_MLIR_OPT
export LINEA_CPU_REAL_MLIR_TRANSLATE
LINEA_CPU_REAL_MLIR_OPT=$(command -v mlir-opt)
LINEA_CPU_REAL_MLIR_TRANSLATE=$(command -v mlir-translate)
export LINEA_CPU_POISON_MARKER="$cpu_scratch/gpu-tool-used"
rm -f "$LINEA_CPU_POISON_MARKER"
cat > "$cpu_scratch/bin/mlir-opt" <<'WRAPPER'
#!/usr/bin/env bash
for argument in "$@"; do
  case "$argument" in
    *spirv*|*gpu.module*) printf '%s\n' "$argument" >> "$LINEA_CPU_POISON_MARKER"; exit 97 ;;
  esac
done
exec "$LINEA_CPU_REAL_MLIR_OPT" "$@"
WRAPPER
cat > "$cpu_scratch/bin/mlir-translate" <<'WRAPPER'
#!/usr/bin/env bash
for argument in "$@"; do
  case "$argument" in
    *spirv*) printf '%s\n' "$argument" >> "$LINEA_CPU_POISON_MARKER"; exit 97 ;;
  esac
done
exec "$LINEA_CPU_REAL_MLIR_TRANSLATE" "$@"
WRAPPER
for command in spirv-val spirv-dis; do
  cat > "$cpu_scratch/bin/$command" <<'WRAPPER'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$LINEA_CPU_POISON_MARKER"
exit 97
WRAPPER
done
chmod +x "$cpu_scratch/bin/"*
export PATH="$cpu_scratch/bin:$PATH"
# Construct the graph with no Vulkan configuration at all first.
env -u LINEA_VULKAN_HEADERS -u LINEA_VULKAN_LOADER \
  zig build -Dgpu=false --help > "$cpu_scratch/graph.log"
# An accidentally selected Vulkan provider now hits a poisoned header even
# on a host that has a Vulkan SDK installed outside this shell.
export LINEA_VULKAN_HEADERS="$cpu_scratch/poison"
export LINEA_VULKAN_LOADER="$cpu_scratch/poison"
zig build -Dgpu=false -j4 --cache-dir "$cpu_scratch/cache" \
  --prefix "$cpu_scratch/install" test-cpu-only install
if test -n "$gpu_control_compiler"; then
  for variant in 0 1; do
    fake_archive="$cpu_scratch/install/test-fixtures/liblinea_rt_fake_gpu$variant.a"
    cpu_archive="$cpu_scratch/install/lib/liblinea_rt.a"
    if test "$variant" = 1; then cpu_archive="$cpu_scratch/install/lib/liblinea_rt_checked.a"; fi
    opened=$(env LINEA_RUNTIME="$fake_archive" "$gpu_control_compiler" run runtime/tests/cpu_only/capability_available.lin)
    test "$opened" = 'fake GPU acquisition entered'
    env LINEA_RUNTIME="$cpu_archive" "$gpu_control_compiler" run runtime/tests/cpu_only/capability_unavailable.lin
  done
fi
zig build -Dgpu=false -j4 --cache-dir "$cpu_scratch/cache" \
  --prefix "$cpu_scratch/install" test \
  -Dtest-filter='the cache stamps every tool a build runs'
zig build -Dgpu=false -j4 --cache-dir "$cpu_scratch/cache" \
  --prefix "$cpu_scratch/install" test \
  -Dtest-filter='CPU-only compiler gates only certified device acquisition'
if test -e "$LINEA_CPU_POISON_MARKER"; then
  cat "$LINEA_CPU_POISON_MARKER" >&2
  echo 'CPU-only execution invoked a GPU tool' >&2
  exit 1
fi
echo 'CPU-only compiler, both runtime archives, capability matrix, tensors and fibers passed without GPU tools'
