#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <sys/select.h>
#include <sys/sysctl.h>

static char unit_str[3][6] = { { " Bps" }, { "KBps" }, { "MBps" }, };

enum unit {
  UNIT_BPS,
  UNIT_KBPS,
  UNIT_MBPS
};

struct network_snapshot {
  uint64_t bytes_in;
  uint64_t bytes_out;
  uint64_t packets_in;
  uint64_t packets_out;
};

static inline void network_snapshot_add(struct network_snapshot* snapshot,
                                        bool is_loopback,
                                        uint64_t bytes_in,
                                        uint64_t bytes_out,
                                        uint64_t packets_in,
                                        uint64_t packets_out) {
  if (is_loopback) return;
  snapshot->bytes_in += bytes_in;
  snapshot->bytes_out += bytes_out;
  snapshot->packets_in += packets_in;
  snapshot->packets_out += packets_out;
}

static inline double network_snapshot_rate(uint64_t current,
                                           uint64_t previous,
                                           double seconds) {
  if (seconds < 1e-6 || seconds > 1e2 || current < previous) return 0;
  return (current - previous) / seconds;
}

static inline bool network_parse_update_frequency(int argc,
                                                  char** argv,
                                                  float* update_frequency) {
  return argc == 3
         && sscanf(argv[2], "%f", update_frequency) == 1
         && *update_frequency > 0;
}

struct network {
  struct network_snapshot snapshot;
  struct timeval tv_nm1, tv_n, tv_delta;

  int up;
  int down;
  int packets_in;
  int packets_out;
  enum unit up_unit, down_unit;
};

static inline bool network_read_interface(uint32_t net_row,
                                          struct ifmibdata* data) {
  size_t size = sizeof(struct ifmibdata);
  int32_t data_option[] = { CTL_NET, PF_LINK, NETLINK_GENERIC,
                           IFMIB_IFDATA, 0, IFDATA_GENERAL };
  data_option[4] = net_row;
  return sysctl(data_option, 6, data, &size, NULL, 0) == 0;
}

static inline bool network_read_snapshot(struct network_snapshot* snapshot) {
  int count_option[] = { CTL_NET, PF_LINK, NETLINK_GENERIC,
                         IFMIB_SYSTEM, IFMIB_IFCOUNT };
  uint32_t interface_count = 0;
  size_t size = sizeof(uint32_t);
  if (sysctl(count_option, 5, &interface_count, &size, NULL, 0) != 0) {
    return false;
  }

  memset(snapshot, 0, sizeof(struct network_snapshot));
  for (uint32_t row = 1; row <= interface_count; row++) {
    struct ifmibdata data;
    if (!network_read_interface(row, &data)) continue;

    network_snapshot_add(snapshot,
                         (data.ifmd_flags & IFF_LOOPBACK) != 0,
                         data.ifmd_data.ifi_ibytes,
                         data.ifmd_data.ifi_obytes,
                         data.ifmd_data.ifi_ipackets,
                         data.ifmd_data.ifi_opackets);
  }
  return true;
}

static inline void network_init(struct network* net) {
  memset(net, 0, sizeof(struct network));
  network_read_snapshot(&net->snapshot);
  gettimeofday(&net->tv_nm1, NULL);
}

static inline void network_update(struct network* net) {
  struct network_snapshot current;
  if (!network_read_snapshot(&current)) {
    net->up = 0;
    net->down = 0;
    net->packets_in = 0;
    net->packets_out = 0;
    return;
  }

  gettimeofday(&net->tv_n, NULL);
  timersub(&net->tv_n, &net->tv_nm1, &net->tv_delta);
  net->tv_nm1 = net->tv_n;

  double time_scale = (net->tv_delta.tv_sec + 1e-6*net->tv_delta.tv_usec);
  net->packets_in = network_snapshot_rate(current.packets_in,
                                          net->snapshot.packets_in,
                                          time_scale);
  net->packets_out = network_snapshot_rate(current.packets_out,
                                           net->snapshot.packets_out,
                                           time_scale);
  double delta_ibytes = network_snapshot_rate(current.bytes_in,
                                              net->snapshot.bytes_in,
                                              time_scale);
  double delta_obytes = network_snapshot_rate(current.bytes_out,
                                              net->snapshot.bytes_out,
                                              time_scale);
  net->snapshot = current;

  double exponent_ibytes = log10(delta_ibytes);
  double exponent_obytes = log10(delta_obytes);

  if (exponent_ibytes < 3) {
    net->down_unit = UNIT_BPS;
    net->down = delta_ibytes;
  } else if (exponent_ibytes < 6) {
    net->down_unit = UNIT_KBPS;
    net->down = delta_ibytes / 1000.0;
  } else if (exponent_ibytes < 9) {
    net->down_unit = UNIT_MBPS;
    net->down = delta_ibytes / 1000000.0;
  }

  if (exponent_obytes < 3) {
    net->up_unit = UNIT_BPS;
    net->up = delta_obytes;
  } else if (exponent_obytes < 6) {
    net->up_unit = UNIT_KBPS;
    net->up = delta_obytes / 1000.0;
  } else if (exponent_obytes < 9) {
    net->up_unit = UNIT_MBPS;
    net->up = delta_obytes / 1000000.0;
  }
}
