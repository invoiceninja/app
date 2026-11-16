#include "font_guard.h"

#ifdef NINJA_HAVE_FONTCONFIG

#include <fontconfig/fontconfig.h>
#include <glib.h>

#include <set>
#include <string>

// Why this exists (invoiceninja/flutter#194, docs/upstream-workarounds.md).
//
// The engine builds Skia's fontconfig font manager on the platform thread
// while the view is realized, and its constructor reads every installed font's
// family names in a loop that ends only when fontconfig answers "no such id":
//
//   for (int id = 0;; ++id) {
//     FcResult result = FcPatternGetString(font, FC_FAMILY, id, &name);
//     if (FcResultNoId == result) break;
//     if (FcResultMatch != result) continue;
//     ...
//
// A font with no family element at all answers FcResultNoMatch for every id,
// so the loop never ends: the process spins on one core before its first
// frame, and since the window is shown on that frame, there is no window. One
// such font on the machine is enough.
//
// The engine cannot be handed a config, only the environment it reads one
// from. So before anything starts: list the fonts as the engine will, and if
// any would loop, point FONTCONFIG_FILE at a generated file that includes the
// user's own configuration and rejects those font files. A machine with no
// such font (nearly all of them) is left exactly as it was.

namespace {

// More family names than any real font carries.
constexpr int kMaxFamilyIds = 4096;

// Whether the engine's loop over this font's family names would end.
bool family_loop_ends(FcPattern* font) {
  for (int id = 0; id < kMaxFamilyIds; ++id) {
    FcChar8* name = nullptr;
    if (FcPatternGetString(font, FC_FAMILY, id, &name) == FcResultNoId) {
      return true;
    }
  }
  return false;
}

struct Scan {
  // Fonts the engine would hang on.
  int unusable = 0;
  // Their files, where fontconfig names one.
  std::set<std::string> files;
};

// The same call the engine makes: a config of its own, read from the
// environment as it is now.
Scan scan_fonts() {
  Scan scan;
  FcConfig* config = FcInitLoadConfigAndFonts();
  if (config == nullptr) {
    return scan;
  }
  static constexpr FcSetName kSets[] = {FcSetSystem, FcSetApplication};
  for (FcSetName set : kSets) {
    // Owned by the config.
    FcFontSet* fonts = FcConfigGetFonts(config, set);
    if (fonts == nullptr) {
      continue;
    }
    for (int i = 0; i < fonts->nfont; ++i) {
      FcPattern* font = fonts->fonts[i];
      if (family_loop_ends(font)) {
        continue;
      }
      ++scan.unusable;
      FcChar8* file = nullptr;
      if (FcPatternGetString(font, FC_FILE, 0, &file) == FcResultMatch &&
          file != nullptr) {
        scan.files.insert(reinterpret_cast<const char*>(file));
      }
    }
  }
  FcConfigDestroy(config);
  return scan;
}

// The configuration file fontconfig would read: $FONTCONFIG_FILE when set,
// else its built-in default.
std::string current_config_file() {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  FcChar8* file = FcConfigFilename(nullptr);
#pragma GCC diagnostic pop
  if (file == nullptr) {
    return std::string();
  }
  std::string result(reinterpret_cast<const char*>(file));
  FcStrFree(file);
  return result;
}

}  // namespace

void ninja_guard_fonts() {
  if (g_strcmp0(g_getenv("INVOICENINJA_NO_FONT_GUARD"), "1") == 0) {
    return;
  }
  const Scan before = scan_fonts();
  if (before.unusable == 0) {
    return;
  }
  if (before.files.empty()) {
    g_warning(
        "%d installed font(s) have no family name and no file name; the app "
        "may not start (invoiceninja/flutter#194).",
        before.unusable);
    return;
  }

  g_autoptr(GString) xml = g_string_new(
      "<?xml version=\"1.0\"?>\n"
      "<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n"
      "<!-- Written by Invoice Ninja at each launch; safe to delete. -->\n"
      "<fontconfig>\n");
  const std::string original = current_config_file();
  if (!original.empty()) {
    g_autofree gchar* escaped = g_markup_escape_text(original.c_str(), -1);
    g_string_append_printf(
        xml, "  <include ignore_missing=\"yes\">%s</include>\n", escaped);
  }
  g_string_append(xml, "  <selectfont>\n    <rejectfont>\n");
  for (const std::string& file : before.files) {
    g_autofree gchar* escaped = g_markup_escape_text(file.c_str(), -1);
    g_string_append_printf(xml, "      <glob>%s</glob>\n", escaped);
  }
  g_string_append(xml, "    </rejectfont>\n  </selectfont>\n</fontconfig>\n");

  g_autofree gchar* dir =
      g_build_filename(g_get_user_cache_dir(), APPLICATION_ID, nullptr);
  g_autofree gchar* path = g_build_filename(dir, "fonts.conf", nullptr);
  g_autoptr(GError) error = nullptr;
  if (g_mkdir_with_parents(dir, 0700) != 0 ||
      !g_file_set_contents(path, xml->str, xml->len, &error)) {
    g_warning(
        "%d installed font(s) have no family name and %s could not be "
        "written (%s); the app may not start (invoiceninja/flutter#194).",
        before.unusable, path, error != nullptr ? error->message : "mkdir");
    return;
  }
  g_setenv("FONTCONFIG_FILE", path, TRUE);

  const Scan after = scan_fonts();
  for (const std::string& file : before.files) {
    g_message("Font left out, it has no family name: %s", file.c_str());
  }
  if (after.unusable != 0) {
    g_warning(
        "%d font(s) with no family name are still listed; the app may not "
        "start (invoiceninja/flutter#194).",
        after.unusable);
  }
}

#else  // NINJA_HAVE_FONTCONFIG

void ninja_guard_fonts() {}

#endif  // NINJA_HAVE_FONTCONFIG
