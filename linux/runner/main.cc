#include "font_guard.h"
#include "my_application.h"

int main(int argc, char** argv) {
  // Before any thread exists: it may set FONTCONFIG_FILE.
  ninja_guard_fonts();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
