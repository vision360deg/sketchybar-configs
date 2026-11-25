#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Presses Mission Control's "Switch to Desktop N" shortcut as configured in
// System Settings. macOS numbers desktops across all displays in the order of
// yabai's space indices, and switches the display that shows desktop N. The
// process that runs this must be allowed to post events (Accessibility).

#define SWITCH_TO_DESKTOP_1 118
#define LAST_DESKTOP 16
#define MODIFIER_MASK (kCGEventFlagMaskShift | kCGEventFlagMaskControl \
                       | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand \
                       | kCGEventFlagMaskSecondaryFn)

static bool number_value(CFTypeRef value, long long* result) {
  return value
    && CFGetTypeID(value) == CFNumberGetTypeID()
    && CFNumberGetValue(value, kCFNumberLongLongType, result);
}

static bool enabled(CFTypeRef value) {
  if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
    return CFBooleanGetValue(value);
  }
  long long number = 0;
  return number_value(value, &number) && number != 0;
}

// Reads the key and modifiers of the desktop's shortcut; false when the
// shortcut is missing or disabled.
static bool desktop_shortcut(int desktop, CGKeyCode* key_code, CGEventFlags* flags) {
  CFPropertyListRef hotkeys = CFPreferencesCopyAppValue(CFSTR("AppleSymbolicHotKeys"),
                                                        CFSTR("com.apple.symbolichotkeys"));
  if (!hotkeys) return false;

  bool found = false;
  if (CFGetTypeID(hotkeys) == CFDictionaryGetTypeID()) {
    CFStringRef key = CFStringCreateWithFormat(NULL, NULL, CFSTR("%d"),
                                               SWITCH_TO_DESKTOP_1 + desktop - 1);
    CFTypeRef entry = CFDictionaryGetValue(hotkeys, key);
    CFRelease(key);

    CFTypeRef value = NULL;
    if (entry && CFGetTypeID(entry) == CFDictionaryGetTypeID()
        && enabled(CFDictionaryGetValue(entry, CFSTR("enabled")))) {
      value = CFDictionaryGetValue(entry, CFSTR("value"));
    }

    CFTypeRef parameters = NULL;
    if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
      parameters = CFDictionaryGetValue(value, CFSTR("parameters"));
    }

    // parameters: character (unused), virtual key code, modifier flags.
    long long code = 0;
    long long modifiers = 0;
    if (parameters && CFGetTypeID(parameters) == CFArrayGetTypeID()
        && CFArrayGetCount(parameters) >= 3
        && number_value(CFArrayGetValueAtIndex(parameters, 1), &code)
        && number_value(CFArrayGetValueAtIndex(parameters, 2), &modifiers)
        && code >= 0 && code < 0xFFFF) {
      *key_code = (CGKeyCode)code;
      *flags = (CGEventFlags)modifiers & MODIFIER_MASK;
      found = true;
    }
  }

  CFRelease(hotkeys);
  return found;
}

static void post_key(CGEventSourceRef source, CGKeyCode key_code,
                     CGEventFlags flags, bool down) {
  CGEventRef event = CGEventCreateKeyboardEvent(source, key_code, down);
  if (!event) return;
  CGEventSetFlags(event, flags);
  CGEventPost(kCGHIDEventTap, event);
  CFRelease(event);
}

int main(int argc, char** argv) {
  int desktop = argc == 2 ? atoi(argv[1]) : 0;
  if (desktop < 1 || desktop > LAST_DESKTOP) {
    fprintf(stderr, "usage: %s <desktop 1-%d>\n", argv[0], LAST_DESKTOP);
    return 64;
  }

  CGKeyCode key_code = 0;
  CGEventFlags flags = 0;
  if (!desktop_shortcut(desktop, &key_code, &flags)) {
    fprintf(stderr,
            "switch_desktop: enable \"Switch to Desktop %d\" in System Settings > "
            "Keyboard > Keyboard Shortcuts > Mission Control\n",
            desktop);
    return 69;
  }

  if (!CGPreflightPostEventAccess()) {
    fprintf(stderr,
            "switch_desktop: not allowed to post events; grant Accessibility to "
            "the app that runs it\n");
    return 77;
  }

  // Press the key like a keyboard does: an instant press without an event
  // source did not trigger the shortcut in testing.
  CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  post_key(source, key_code, flags, true);
  usleep(20000);
  post_key(source, key_code, flags, false);
  if (source) CFRelease(source);
  return 0;
}
