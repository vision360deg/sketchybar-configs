#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsign-compare"
#include "../sketchybar.h"
#pragma clang diagnostic pop

#define EVENT_NAME "mouse_clicked_global"
#define POLL_INTERVAL_US 8000

static bool button_down(CGMouseButton button) {
  return CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState,
                                  button);
}

static CGPoint mouse_location(void) {
  CGEventRef event = CGEventCreate(NULL);
  if (!event) return CGPointZero;
  CGPoint location = CGEventGetLocation(event);
  CFRelease(event);
  return location;
}

static const char* button_name(CGMouseButton button) {
  if (button == kCGMouseButtonLeft) return "left";
  if (button == kCGMouseButtonRight) return "right";
  return "other";
}

static void emit_click(CGMouseButton button) {
  CGPoint point = mouse_location();
  char message[256];
  snprintf(message,
           sizeof(message),
           "--trigger '%s' BUTTON='%s' MOUSE_X='%d' MOUSE_Y='%d'",
           EVENT_NAME,
           button_name(button),
           (int)point.x,
           (int)point.y);
  sketchybar(message);
}

static int probe(void) {
  CGPoint point = mouse_location();
  printf("MOUSE_X=%d MOUSE_Y=%d LEFT=%d RIGHT=%d OTHER=%d\n",
         (int)point.x,
         (int)point.y,
         button_down(kCGMouseButtonLeft),
         button_down(kCGMouseButtonRight),
         button_down(kCGMouseButtonCenter));
  return 0;
}

int main(int argc, char** argv) {
  if (argc > 1 && strcmp(argv[1], "--probe") == 0) return probe();

  const CGMouseButton buttons[] = {
    kCGMouseButtonLeft,
    kCGMouseButtonRight,
    kCGMouseButtonCenter,
  };
  bool previous[] = {
    button_down(buttons[0]),
    button_down(buttons[1]),
    button_down(buttons[2]),
  };

  for (;;) {
    for (size_t index = 0; index < sizeof(buttons) / sizeof(buttons[0]); index++) {
      bool current = button_down(buttons[index]);
      if (current && !previous[index]) emit_click(buttons[index]);
      previous[index] = current;
    }
    usleep(POLL_INTERVAL_US);
  }
}
