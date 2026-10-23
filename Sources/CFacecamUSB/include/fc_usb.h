#ifndef FC_USB_H
#define FC_USB_H

#include <dispatch/dispatch.h>
#include <stddef.h>
#include <stdint.h>

typedef struct fc_device fc_device;

typedef struct {
    uint64_t registry_id;
    uint16_t vendor_id;
    uint16_t product_id;
    char name[128];
    char serial[64];
} fc_device_info;

/// Lists USB devices with the given vendor ID that expose a UVC VideoControl interface.
/// Returns the number of devices written to `out` (at most `max`), or a negative IOReturn.
int fc_list(uint16_t vendor_id, fc_device_info *out, int max);

/// Opens the VideoControl interface of the device with the given registry ID.
int fc_open(uint64_t registry_id, fc_device **out);
void fc_close(fc_device *device);

uint8_t fc_interface_number(const fc_device *device);

/// Full configuration descriptor (owned by the device handle).
const uint8_t *fc_config_descriptor(const fc_device *device, size_t *length);

/// Class-specific control request on endpoint 0 of the VideoControl interface.
/// Sent without opening or claiming the interface, so it works while the UVC driver owns it.
int fc_control(fc_device *device, uint8_t request_type, uint8_t request,
               uint16_t value, uint16_t index, void *data, uint16_t length,
               uint32_t *transferred);

const char *fc_error_string(int code);

typedef struct fc_watcher fc_watcher;

/// Called on `queue` with arrived=1 when a matching device appears and arrived=0 when one is removed.
/// Devices already present are reported synchronously from fc_watch.
typedef void (*fc_watch_callback)(void *context, int arrived);

fc_watcher *fc_watch(uint16_t vendor_id, dispatch_queue_t queue, fc_watch_callback callback, void *context);
void fc_unwatch(fc_watcher *watcher);

#endif
