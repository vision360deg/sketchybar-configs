#include <ApplicationServices/ApplicationServices.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsign-compare"
#include "../sketchybar.h"
#pragma clang diagnostic pop

#define EVENT_NAME "spaces_horizontal_scroll"

struct event_tap_context {
  CFMachPortRef event_tap;
};

static int64_t horizontal_delta(CGEventRef event) {
  int64_t delta = CGEventGetIntegerValueField(
      event,
      kCGScrollWheelEventPointDeltaAxis2);

  if (delta == 0) {
    delta = CGEventGetIntegerValueField(
        event,
        kCGScrollWheelEventDeltaAxis2);
  }

  return delta;
}

static void emit_scroll(int64_t delta, CGPoint point) {
  char message[256];
  snprintf(message,
           sizeof(message),
           "--trigger '%s' SCROLL_DELTA='%lld' MOUSE_X='%d' MOUSE_Y='%d'",
           EVENT_NAME,
           (long long)delta,
           (int)point.x,
           (int)point.y);
  sketchybar(message);
}

static CGEventRef handle_scroll(CGEventTapProxy proxy,
                                CGEventType type,
                                CGEventRef event,
                                void* context) {
  (void)proxy;
  struct event_tap_context* tap_context = context;

  if (type == kCGEventTapDisabledByTimeout
      || type == kCGEventTapDisabledByUserInput) {
    if (tap_context && tap_context->event_tap) {
      CGEventTapEnable(tap_context->event_tap, true);
    }
    return event;
  }

  int64_t delta = horizontal_delta(event);
  if (delta != 0) {
    emit_scroll(delta, CGEventGetLocation(event));
  }

  return event;
}

int main(void) {
  alarm(0);

  CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel);
  struct event_tap_context context = { 0 };
  CFMachPortRef event_tap = CGEventTapCreate(
      kCGSessionEventTap,
      kCGHeadInsertEventTap,
      kCGEventTapOptionListenOnly,
      mask,
      handle_scroll,
      &context);

  if (!event_tap) {
    fprintf(stderr,
            "horizontal_scroll: unable to create event tap; "
            "grant Input Monitoring permission to horizontal_scroll "
            "and reload SketchyBar.\n");
    return 1;
  }

  context.event_tap = event_tap;

  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(
      kCFAllocatorDefault,
      event_tap,
      0);

  if (!source) {
    fprintf(stderr, "horizontal_scroll: unable to create run-loop source.\n");
    CFRelease(event_tap);
    return 1;
  }

  CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
  CGEventTapEnable(event_tap, true);
  CFRunLoopRun();

  CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
  CFRelease(source);
  CFRelease(event_tap);
  return 0;
}
