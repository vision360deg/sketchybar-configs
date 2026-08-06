#include "bridge.h"

#include <bootstrap.h>
#include <mach/mach.h>
#include <mach/message.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

struct spaces_mach_message {
  mach_msg_header_t header;
  mach_msg_size_t descriptor_count;
  mach_msg_ool_descriptor_t descriptor;
};

struct spaces_mach_buffer {
  struct spaces_mach_message message;
  mach_msg_trailer_t trailer;
};

extern void spaces_overlay_receive(const void *payload, size_t length);

static mach_port_t bootstrap_port_for_task(void) {
  mach_port_t bootstrap_port = MACH_PORT_NULL;
  if (task_get_special_port(mach_task_self(),
                            TASK_BOOTSTRAP_PORT,
                            &bootstrap_port) != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }
  return bootstrap_port;
}

static mach_port_t check_in(const char *service_name) {
  mach_port_t bootstrap_port = bootstrap_port_for_task();
  if (bootstrap_port == MACH_PORT_NULL) {
    return MACH_PORT_NULL;
  }

  mach_port_t service_port = MACH_PORT_NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  kern_return_t result = bootstrap_check_in(bootstrap_port,
                                             service_name,
                                             &service_port);
#pragma clang diagnostic pop
  return result == KERN_SUCCESS ? service_port : MACH_PORT_NULL;
}

int spaces_mach_service_run(const char *service_name) {
  if (service_name == NULL || service_name[0] == '\0') {
    return 64;
  }

  mach_port_t service_port = check_in(service_name);
  if (service_port == MACH_PORT_NULL) {
    return 69;
  }

  for (;;) {
    struct spaces_mach_buffer buffer = {0};
    mach_msg_return_t result = mach_msg(&buffer.message.header,
                                        MACH_RCV_MSG,
                                        0,
                                        sizeof(buffer),
                                        service_port,
                                        MACH_MSG_TIMEOUT_NONE,
                                        MACH_PORT_NULL);
    if (result != MACH_MSG_SUCCESS) {
      return 70;
    }

    bool valid = MACH_MSGH_BITS_IS_COMPLEX(buffer.message.header.msgh_bits)
      && buffer.message.descriptor_count == 1
      && buffer.message.descriptor.type == MACH_MSG_OOL_DESCRIPTOR
      && buffer.message.descriptor.address != NULL
      && buffer.message.descriptor.size > 0;

    if (valid) {
      const void *payload = buffer.message.descriptor.address;
      size_t length = buffer.message.descriptor.size;
      if (!(length == 2 && memcmp(payload, "k", 2) == 0)) {
        spaces_overlay_receive(payload, length);
      }
    }

    mach_msg_destroy(&buffer.message.header);
  }
}
