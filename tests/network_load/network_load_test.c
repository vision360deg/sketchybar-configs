#include <assert.h>
#include <math.h>
#include <stdbool.h>

#include "../../helpers/event_providers/network_load/network.h"

static void test_snapshot_aggregates_external_interfaces(void) {
  struct network_snapshot snapshot = { 0 };

  network_snapshot_add(&snapshot, false, 100, 200, 10, 20);
  network_snapshot_add(&snapshot, true, 1000, 2000, 100, 200);
  network_snapshot_add(&snapshot, false, 300, 400, 30, 40);

  assert(snapshot.bytes_in == 400);
  assert(snapshot.bytes_out == 600);
  assert(snapshot.packets_in == 40);
  assert(snapshot.packets_out == 60);
}

static void test_snapshot_tracks_traffic_on_non_primary_interface(void) {
  struct network_snapshot previous = { 100, 100, 10, 10 };
  struct network_snapshot current = { 500, 700, 50, 70 };

  assert(network_snapshot_rate(current.packets_in,
                               previous.packets_in,
                               2.0) == 20);
  assert(network_snapshot_rate(current.packets_out,
                               previous.packets_out,
                               2.0) == 30);
}

static void test_snapshot_rate_rejects_counter_rollback(void) {
  assert(network_snapshot_rate(50, 100, 2.0) == 0);
}

static void test_snapshot_rate_rejects_invalid_intervals(void) {
  assert(network_snapshot_rate(140, 100, 0.0) == 0);
  assert(network_snapshot_rate(140, 100, 101.0) == 0);
}

static void test_provider_cli_has_no_interface_argument(void) {
  float update_frequency = 0;
  char* valid_argv[] = { "network_load", "network_update", "2.0" };
  char* old_argv[] = { "network_load", "en0", "network_update", "2.0" };

  assert(network_parse_update_frequency(3, valid_argv, &update_frequency));
  assert(fabsf(update_frequency - 2.0f) < 0.001f);
  assert(!network_parse_update_frequency(4, old_argv, &update_frequency));
}

int main(void) {
  test_snapshot_aggregates_external_interfaces();
  test_snapshot_tracks_traffic_on_non_primary_interface();
  test_snapshot_rate_rejects_counter_rollback();
  test_snapshot_rate_rejects_invalid_intervals();
  test_provider_cli_has_no_interface_argument();
  return 0;
}
