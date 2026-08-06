#include <unistd.h>
#include "network.h"
#include "../sketchybar.h"

int main (int argc, char** argv) {
  float update_freq;
  if (!network_parse_update_frequency(argc, argv, &update_freq)) {
    printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    exit(1);
  }

  alarm(0);
  // Setup the event in sketchybar
  char event_message[512];
  snprintf(event_message, 512, "--add event '%s'", argv[1]);
  sketchybar(event_message);

  struct network network;
  network_init(&network);
  char trigger_message[512];
  for (;;) {
    // Acquire new info
    network_update(&network);

    // Prepare the event message
    snprintf(trigger_message,
             512,
             "--trigger '%s' upload='%03d%s' download='%03d%s' packets_in='%d' packets_out='%d'",
             argv[1],
             network.up,
             unit_str[network.up_unit],
             network.down,
             unit_str[network.down_unit],
             network.packets_in,
             network.packets_out);

    // Trigger the event
    sketchybar(trigger_message);

    // Wait
    usleep(update_freq * 1000000);
  }
  return 0;
}
