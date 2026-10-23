#include "fc_usb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach_error.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define FC_TRACE(...) do { if (getenv("FC_DEBUG")) fprintf(stderr, "fc: " __VA_ARGS__); } while (0)

#define FC_VIDEO_CLASS 0x0E
#define FC_VIDEO_CONTROL_SUBCLASS 0x01

struct fc_device {
    IOUSBDeviceInterface942 **dev;
    IOUSBInterfaceInterface942 **intf;
    uint8_t interface_number;
    uint8_t *config;
    size_t config_length;
};

static IOUSBDeviceInterface942 **device_interface(io_service_t service) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                          kIOCFPlugInInterfaceID, &plugin, &score) != kIOReturnSuccess ||
        plugin == NULL) {
        FC_TRACE("device plugin failed\n");
        return NULL;
    }
    IOUSBDeviceInterface942 **dev = NULL;
    (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID *)&dev);
    IODestroyPlugInInterface(plugin);
    return dev;
}

static IOUSBInterfaceInterface942 **video_control_interface(IOUSBDeviceInterface942 **dev) {
    IOUSBFindInterfaceRequest request = {
        .bInterfaceClass = FC_VIDEO_CLASS,
        .bInterfaceSubClass = FC_VIDEO_CONTROL_SUBCLASS,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare,
    };
    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn ikr = (*dev)->CreateInterfaceIterator(dev, &request, &iterator);
    if (ikr != kIOReturnSuccess) {
        FC_TRACE("CreateInterfaceIterator: %s\n", mach_error_string(ikr));
        return NULL;
    }
    io_service_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (service == IO_OBJECT_NULL) {
        FC_TRACE("no VideoControl interface\n");
        return NULL;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn kr = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
                                                    kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || plugin == NULL) {
        FC_TRACE("interface plugin: %s\n", mach_error_string(kr));
        return NULL;
    }
    IOUSBInterfaceInterface942 **intf = NULL;
    (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID942), (LPVOID *)&intf);
    IODestroyPlugInInterface(plugin);
    return intf;
}

static void copy_string_property(io_service_t service, CFStringRef key, char *out, size_t size) {
    out[0] = '\0';
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    if (value == NULL) {
        return;
    }
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, out, (CFIndex)size, kCFStringEncodingUTF8);
    }
    CFRelease(value);
}

static int has_video_control(IOUSBDeviceInterface942 **dev) {
    IOUSBInterfaceInterface942 **intf = video_control_interface(dev);
    if (intf == NULL) {
        return 0;
    }
    (*intf)->Release(intf);
    return 1;
}

static CFMutableDictionaryRef vendor_matching(uint16_t vendor_id) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBHostDeviceClassName);
    if (matching == NULL) {
        return NULL;
    }
    int32_t vid = vendor_id;
    CFNumberRef vid_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vid);
    // IOUSBHostDevice ignores top-level property keys; they must go under IOPropertyMatch.
    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(properties, CFSTR(kUSBVendorID), vid_number);
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), properties);
    CFRelease(properties);
    CFRelease(vid_number);
    return matching;
}

int fc_list(uint16_t vendor_id, fc_device_info *out, int max) {
    CFMutableDictionaryRef matching = vendor_matching(vendor_id);
    if (matching == NULL) {
        return kIOReturnNoMemory;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (kr != kIOReturnSuccess) {
        return kr;
    }

    int count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        FC_TRACE("matched service 0x%x\n", service);
        IOUSBDeviceInterface942 **dev = device_interface(service);
        if (dev != NULL) {
            if (has_video_control(dev) && count < max) {
                fc_device_info *info = &out[count++];
                memset(info, 0, sizeof(*info));
                IORegistryEntryGetRegistryEntryID(service, &info->registry_id);
                (*dev)->GetDeviceVendor(dev, &info->vendor_id);
                (*dev)->GetDeviceProduct(dev, &info->product_id);
                copy_string_property(service, CFSTR(kUSBProductString), info->name, sizeof(info->name));
                copy_string_property(service, CFSTR(kUSBSerialNumberString), info->serial, sizeof(info->serial));
            }
            (*dev)->Release(dev);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return count;
}

int fc_open(uint64_t registry_id, fc_device **out) {
    *out = NULL;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registry_id));
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNoDevice;
    }
    IOUSBDeviceInterface942 **dev = device_interface(service);
    IOObjectRelease(service);
    if (dev == NULL) {
        return kIOReturnNotOpen;
    }

    IOUSBConfigurationDescriptorPtr config = NULL;
    IOReturn kr = (*dev)->GetConfigurationDescriptorPtr(dev, 0, &config);
    if (kr != kIOReturnSuccess || config == NULL) {
        (*dev)->Release(dev);
        return kr != kIOReturnSuccess ? kr : kIOReturnNotFound;
    }

    IOUSBInterfaceInterface942 **intf = video_control_interface(dev);
    if (intf == NULL) {
        (*dev)->Release(dev);
        return kIOReturnNotFound;
    }

    fc_device *device = calloc(1, sizeof(*device));
    device->dev = dev;
    device->intf = intf;
    (*intf)->GetInterfaceNumber(intf, &device->interface_number);
    device->config_length = USBToHostWord(config->wTotalLength);
    device->config = malloc(device->config_length);
    memcpy(device->config, config, device->config_length);
    *out = device;
    return kIOReturnSuccess;
}

void fc_close(fc_device *device) {
    if (device == NULL) {
        return;
    }
    (*device->intf)->Release(device->intf);
    (*device->dev)->Release(device->dev);
    free(device->config);
    free(device);
}

uint8_t fc_interface_number(const fc_device *device) {
    return device->interface_number;
}

const uint8_t *fc_config_descriptor(const fc_device *device, size_t *length) {
    *length = device->config_length;
    return device->config;
}

int fc_control(fc_device *device, uint8_t request_type, uint8_t request,
               uint16_t value, uint16_t index, void *data, uint16_t length,
               uint32_t *transferred) {
    IOUSBDevRequest req = {
        .bmRequestType = request_type,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = length,
        .pData = data,
        .wLenDone = 0,
    };
    IOReturn kr = (*device->intf)->ControlRequest(device->intf, 0, &req);
    if (transferred != NULL) {
        *transferred = req.wLenDone;
    }
    FC_TRACE("req type=%02x req=%02x val=%04x idx=%04x len=%u done=%u kr=%x data=", request_type, request,
             value, index, length, (unsigned)req.wLenDone, kr);
    for (uint32_t i = 0; getenv("FC_DEBUG") && i < req.wLenDone && i < 16; i++) {
        fprintf(stderr, "%02x", ((uint8_t *)data)[i]);
    }
    if (getenv("FC_DEBUG")) {
        fputc('\n', stderr);
    }
    return kr;
}

const char *fc_error_string(int code) {
    return mach_error_string(code);
}

struct fc_watcher {
    IONotificationPortRef port;
    io_iterator_t added;
    io_iterator_t removed;
    fc_watch_callback callback;
    void *context;
};

static int drain(io_iterator_t iterator) {
    int count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOObjectRelease(service);
        count++;
    }
    return count;
}

static void on_added(void *refcon, io_iterator_t iterator) {
    fc_watcher *watcher = refcon;
    if (drain(iterator) > 0) {
        watcher->callback(watcher->context, 1);
    }
}

static void on_removed(void *refcon, io_iterator_t iterator) {
    fc_watcher *watcher = refcon;
    if (drain(iterator) > 0) {
        watcher->callback(watcher->context, 0);
    }
}

fc_watcher *fc_watch(uint16_t vendor_id, dispatch_queue_t queue, fc_watch_callback callback, void *context) {
    fc_watcher *watcher = calloc(1, sizeof(*watcher));
    watcher->callback = callback;
    watcher->context = context;
    watcher->port = IONotificationPortCreate(kIOMainPortDefault);
    IONotificationPortSetDispatchQueue(watcher->port, queue);

    // Each registration consumes its matching dictionary.
    if (IOServiceAddMatchingNotification(watcher->port, kIOFirstMatchNotification, vendor_matching(vendor_id),
                                         on_added, watcher, &watcher->added) != kIOReturnSuccess ||
        IOServiceAddMatchingNotification(watcher->port, kIOTerminatedNotification, vendor_matching(vendor_id),
                                         on_removed, watcher, &watcher->removed) != kIOReturnSuccess) {
        fc_unwatch(watcher);
        return NULL;
    }
    // Arm the notifications. Devices already present are reported synchronously, before returning.
    drain(watcher->removed);
    on_added(watcher, watcher->added);
    return watcher;
}

void fc_unwatch(fc_watcher *watcher) {
    if (watcher == NULL) {
        return;
    }
    if (watcher->added != IO_OBJECT_NULL) {
        IOObjectRelease(watcher->added);
    }
    if (watcher->removed != IO_OBJECT_NULL) {
        IOObjectRelease(watcher->removed);
    }
    IONotificationPortDestroy(watcher->port);
    free(watcher);
}
