#!/usr/bin/env bash
# Launches a built Linux bundle with no keyring and fails unless the app
# survives it.
#
#   tools/check_linux_keyring_failure.sh [bundle-dir]
#
# Why: flutter_secure_storage_linux reports a keyring failure by throwing a C++
# exception and catching it. Flutter 3.50's engine exports its own unwinder,
# and unless libgcc_s is loaded ahead of it the catch is never found, so the
# app aborted before its first frame wherever the keyring was locked or
# unreachable (invoiceninja/app#194, docs/upstream-workarounds.md entry 23).
# Nothing else in CI runs the Linux build, and the failure needs a broken
# keyring to show, so this is the only thing that catches it coming back —
# from a Flutter bump, a plugin bump, or a change to linux/runner/CMakeLists.txt.
#
# Two checks:
#   1. Static: while the engine exports `_Unwind_*`, libgcc_s.so.1 is the
#      executable's first DT_NEEDED.
#   2. Behavioural: on a session bus with no services (so no Secret Service and
#      no Secret portal, whatever the machine has installed) the app logs the
#      plugin's `libsecret_error` and is still running afterwards.
#
# Needs: readelf (binutils), xvfb-run, dbus-run-session, and the GTK runtime.
set -euo pipefail

bundle="${1:-build/linux/x64/release/bundle}"
exe="$bundle/admin"
engine="$bundle/lib/libflutter_linux_gtk.so"
wait_seconds="${KEYRING_CHECK_WAIT_SECONDS:-60}"
settle_seconds="${KEYRING_CHECK_SETTLE_SECONDS:-5}"

for f in "$exe" "$engine"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found. Build first: flutter build linux --release" >&2
    exit 2
  fi
done
for tool in readelf xvfb-run dbus-run-session; do
  if ! command -v "$tool" >/dev/null; then
    echo "ERROR: $tool is not installed." >&2
    exit 2
  fi
done

# --- 1. Link order ----------------------------------------------------------
if readelf --dyn-syms --wide "$engine" | grep -E ' (FUNC|NOTYPE) +GLOBAL +DEFAULT +[0-9]+ _Unwind_RaiseException' >/dev/null; then
  first_needed="$(readelf -d "$exe" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | head -n 1)"
  if [[ "$first_needed" != "libgcc_s.so.1" ]]; then
    echo "ERROR: the engine exports _Unwind_RaiseException, and the first library" >&2
    echo "  $exe loads is '$first_needed', not libgcc_s.so.1." >&2
    echo "  A C++ exception thrown in a plugin will abort the app." >&2
    echo "  See linux/runner/CMakeLists.txt and docs/upstream-workarounds.md entry 23." >&2
    exit 1
  fi
  echo "==> link order: libgcc_s.so.1 is loaded ahead of the engine"
else
  echo "==> link order: this engine no longer exports _Unwind_*."
  echo "    The link option in linux/runner/CMakeLists.txt can go"
  echo "    (docs/upstream-workarounds.md entry 23)."
fi

# --- 2. Launch with no keyring ----------------------------------------------
work="$(mktemp -d)"
log="$work/app.log"

# A session bus that can start nothing: no service directories, so neither
# org.freedesktop.secrets nor the desktop portal can be activated.
cat >"$work/bus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

# A clean profile, so a database or key from an earlier run can't change the
# path the app takes. Software GL: the runner has no GPU.
export HOME="$work/home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export LIBGL_ALWAYS_SOFTWARE=1
export GDK_BACKEND=x11
unset SECRET_BACKEND SNAP_NAME WAYLAND_DISPLAY

echo "==> launching $exe with no keyring (up to ${wait_seconds}s)"
xvfb-run --auto-servernum --server-args='-screen 0 1280x800x24' \
  dbus-run-session --config-file="$work/bus.conf" -- "$exe" >"$log" 2>&1 &
launcher=$!

app_running() { kill -0 "$launcher" 2>/dev/null; }
stop_app() {
  pkill -TERM -f "^$exe\$" 2>/dev/null || true
  kill "$launcher" 2>/dev/null || true
  wait "$launcher" 2>/dev/null || true
}
fail() {
  echo "ERROR: $1" >&2
  echo "----- app output -----" >&2
  cat "$log" >&2 || true
  echo "----------------------" >&2
  stop_app
  exit 1
}

# Wait for the plugin to report the keyring failure, or for the app to die.
saw_error=false
for ((i = 0; i < wait_seconds; i++)); do
  if grep -q 'terminate called' "$log"; then
    fail "the app aborted on a C++ exception instead of handling the keyring failure."
  fi
  if grep -q 'libsecret_error' "$log"; then
    saw_error=true
    break
  fi
  if ! app_running; then
    fail "the app exited before it reported the keyring failure."
  fi
  sleep 1
done
if [[ "$saw_error" != true ]]; then
  fail "the app never reported a keyring failure in ${wait_seconds}s, so the failing path was not exercised."
fi

# The failure was reported; the app must outlive it.
sleep "$settle_seconds"
if grep -q 'terminate called' "$log"; then
  fail "the app aborted on a C++ exception after the keyring failure."
fi
if ! app_running; then
  fail "the app exited after the keyring failure instead of showing the keyring screen."
fi

stop_app
echo "==> ok: the keyring failure was caught and the app kept running"
