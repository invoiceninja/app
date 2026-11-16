cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
# The ID before the rename, whose data directory my_application.cc moves over.
add_definitions(-DLEGACY_APPLICATION_ID="${KEYRING_APPLICATION_ID}")

# libgcc_s first among the executable's DT_NEEDED entries, ahead of every plugin
# and of libflutter_linux_gtk.so (docs/upstream-workarounds.md entry 23,
# invoiceninja/app#194). Flutter 3.50's engine library exports LLVM libunwind's
# `_Unwind_*` functions, and the dynamic linker binds a symbol to the first
# library in load order that defines it. Without this line that is the engine,
# so a `throw` in a plugin built against libstdc++ is unwound by a second
# unwinder that libstdc++'s personality routine cannot read: the `catch` is
# never found and the process aborts ("terminate called after throwing an
# instance of 'LibsecretError'"). flutter_secure_storage_linux reports every
# keyring failure that way, so a locked or unreachable keyring closed the app
# before its first frame instead of showing the keyring screen.
#
# A link option, not a link library: options are placed before the objects and
# libraries on the link line, and the order there is the order of DT_NEEDED.
# --no-as-needed because the runner itself calls nothing in libgcc_s.
target_link_options(${BINARY_NAME} PRIVATE
  "LINKER:--push-state,--no-as-needed,-lgcc_s,--pop-state")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
