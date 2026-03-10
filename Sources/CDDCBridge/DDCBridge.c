//
//  DDCBridge.c
//  MonitorSwitchUI
//
//  C bridge for IOKit I2C / IOAVService DDC-CI communication
//

#include "DDCBridge.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <dlfcn.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

// DDC-CI constants
#define DDC_ADDR        0x37  // 7-bit address (0x6E >> 1)
#define DDC_REPLY_ADDR  0x51  // Reply address byte in packet
#define DDC_HOST_ADDR   0x50  // Host address byte (0xA0 >> 1 shifted)

// ============================================================
// Apple Silicon: IOAVService private API
// ============================================================

typedef CFTypeRef IOAVServiceRef;

// Function pointers loaded via dlsym
static IOAVServiceRef (*pIOAVServiceCreate)(CFAllocatorRef) = NULL;
static IOAVServiceRef (*pIOAVServiceCreateWithService)(CFAllocatorRef, io_service_t) = NULL;
static IOReturn (*pIOAVServiceReadI2C)(IOAVServiceRef, uint32_t, uint32_t, void*, uint32_t) = NULL;
static IOReturn (*pIOAVServiceWriteI2C)(IOAVServiceRef, uint32_t, uint32_t, void*, uint32_t) = NULL;

static bool av_symbols_loaded = false;
static bool av_symbols_available = false;

static void load_av_symbols(void) {
    if (av_symbols_loaded) return;
    av_symbols_loaded = true;

    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!handle) return;

    pIOAVServiceCreate = dlsym(handle, "IOAVServiceCreate");
    pIOAVServiceCreateWithService = dlsym(handle, "IOAVServiceCreateWithService");
    pIOAVServiceReadI2C = dlsym(handle, "IOAVServiceReadI2C");
    pIOAVServiceWriteI2C = dlsym(handle, "IOAVServiceWriteI2C");

    av_symbols_available = (pIOAVServiceReadI2C != NULL && pIOAVServiceWriteI2C != NULL);
}

static uint8_t xor_checksum(const uint8_t *data, int length) {
    uint8_t checksum = 0;
    for (int i = 0; i < length; i++) {
        checksum ^= data[i];
    }
    return checksum;
}

// Try to get an IOAVService for any connected external display.
// Strategy: use IOAVServiceCreate first (finds default external display,
// same approach as m1ddc). Fall back to manual iteration if needed.
static IOAVServiceRef get_av_service(void) {
    load_av_symbols();
    if (!av_symbols_available) return NULL;

    // Primary: iterate DCPAVServiceProxy nodes, match Location == "External"
    // (IOAVServiceCreate may return the built-in display which doesn't support DDC)
    if (pIOAVServiceCreateWithService) {
        io_iterator_t iterator;
        kern_return_t kr = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        );
        if (kr == KERN_SUCCESS) {
            io_service_t service;
            IOAVServiceRef avService = NULL;

            while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
                CFTypeRef location = IORegistryEntrySearchCFProperty(
                    service, kIOServicePlane, CFSTR("Location"),
                    kCFAllocatorDefault, kIORegistryIterateRecursively);

                bool isExternal = false;
                if (location) {
                    if (CFGetTypeID(location) == CFStringGetTypeID()) {
                        isExternal = (CFStringCompare(location, CFSTR("External"), 0) == kCFCompareEqualTo);
                    }
                    CFRelease(location);
                }

                if (isExternal) {
                    avService = pIOAVServiceCreateWithService(kCFAllocatorDefault, service);
                    if (avService) {
                        fprintf(stderr, "DDC: got IOAVService via iteration (External), service=%p\n", (void *)avService);
                        IOObjectRelease(service);
                        IOObjectRelease(iterator);
                        return avService;
                    }
                }

                IOObjectRelease(service);
            }

            IOObjectRelease(iterator);
        }
    }

    // Fallback: IOAVServiceCreate (works on single-display setups like Mac Mini)
    if (pIOAVServiceCreate) {
        IOAVServiceRef avService = pIOAVServiceCreate(kCFAllocatorDefault);
        if (avService) {
            fprintf(stderr, "DDC: got IOAVService via IOAVServiceCreate (fallback), service=%p\n", (void *)avService);
            return avService;
        }
    }

    fprintf(stderr, "DDC: no IOAVService found\n");
    return NULL;
}

bool ddc_av_write(uint8_t command, uint8_t value) {
    IOAVServiceRef avService = get_av_service();
    if (!avService) return false;

    // Build DDC-CI Set VCP packet
    // IOAVServiceWriteI2C handles chipAddr (0x37) and dataAddr (0x51) separately,
    // so the buffer starts at the length byte. Checksum includes dataAddr (0x51).
    uint8_t data[6];
    data[0] = 0x84;          // length byte (0x80 | 4 payload bytes)
    data[1] = 0x03;          // Set VCP opcode
    data[2] = command;        // VCP code
    data[3] = 0x00;          // value high byte
    data[4] = value;          // value low byte
    data[5] = 0x6E ^ 0x51 ^ xor_checksum(data, 5);  // checksum includes dest addr + dataAddr

    // Pre-write delay + retry (matching m1ddc DDC_WAIT/DDC_ITERATIONS)
    IOReturn ret;
    for (int attempt = 0; attempt < 2; attempt++) {
        usleep(10000);
        ret = pIOAVServiceWriteI2C(avService, DDC_ADDR, 0x51, data, 6);
        if (ret == kIOReturnSuccess) break;
    }

    CFRelease(avService);

    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "DDC AV write failed: 0x%x\n", ret);
        return false;
    }

    return true;
}

DDCReadResult ddc_av_read(uint8_t command) {
    DDCReadResult result = { false, 0, 0 };

    IOAVServiceRef avService = get_av_service();
    if (!avService) return result;

    // Step 1: Send Get VCP request
    // Buffer starts at length byte; checksum includes dataAddr (0x51)
    uint8_t request[4];
    request[0] = 0x82;       // length byte (0x80 | 2 payload bytes)
    request[1] = 0x01;       // Get VCP opcode
    request[2] = command;     // VCP code
    request[3] = 0x6E ^ xor_checksum(request, 3);  // checksum includes dest addr

    // Pre-write delay + retry (matching m1ddc DDC_WAIT/DDC_ITERATIONS)
    IOReturn ret;
    for (int attempt = 0; attempt < 2; attempt++) {
        usleep(10000);
        ret = pIOAVServiceWriteI2C(avService, DDC_ADDR, 0x51, request, 4);
        if (ret == kIOReturnSuccess) break;
    }
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "DDC AV read request failed: 0x%x\n", ret);
        CFRelease(avService);
        return result;
    }

    // Wait for monitor to process, then read with retry (matching m1ddc approach)
    usleep(10000);

    // Step 2: Read response
    uint8_t reply[12];
    memset(reply, 0, sizeof(reply));

    ret = pIOAVServiceReadI2C(avService, DDC_ADDR, 0x51, reply, 12);

    // Retry once if first read fails
    if (ret != kIOReturnSuccess) {
        usleep(10000);
        memset(reply, 0, sizeof(reply));
        ret = pIOAVServiceReadI2C(avService, DDC_ADDR, 0x51, reply, 12);
    }

    CFRelease(avService);

    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "DDC AV read response failed: 0x%x\n", ret);
        return result;
    }

    // Parse Get VCP Reply
    // reply[0] = length byte (0x88 = 8 bytes | 0x80)
    // reply[1] = 0x02 (Get VCP Reply opcode)
    // reply[2] = result code (0x00 = no error)
    // reply[3] = VCP opcode
    // reply[4] = VCP type (0 = set parameter, 1 = momentary)
    // reply[5] = max value high byte
    // reply[6] = max value low byte
    // reply[7] = current value high byte
    // reply[8] = current value low byte

    if (reply[1] == 0x02 && reply[2] == 0x00 && reply[3] == command) {
        result.success = true;
        result.maxValue = reply[6];  // low byte of max
        result.currentValue = reply[8];  // low byte of current
    } else {
        fprintf(stderr, "DDC reply parse error: opcode=0x%02x result=0x%02x vcp=0x%02x\n",
                reply[1], reply[2], reply[3]);
    }

    return result;
}

// ============================================================
// Intel: IOFramebuffer I2C-based DDC
// ============================================================

static io_service_t get_framebuffer_port(void) {
    io_iterator_t iterator;
    io_service_t service;

    kern_return_t kr = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOFramebuffer"),
        &iterator
    );

    if (kr != KERN_SUCCESS) return IO_OBJECT_NULL;

    service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);

    return service;
}

bool ddc_i2c_write(uint8_t command, uint8_t value) {
    io_service_t framebuffer = get_framebuffer_port();
    if (framebuffer == IO_OBJECT_NULL) return false;

    io_service_t interface;
    IOReturn ret = IOFBCopyI2CInterfaceForBus(framebuffer, 0, &interface);
    IOObjectRelease(framebuffer);
    if (ret != kIOReturnSuccess) return false;

    IOI2CConnectRef connect;
    ret = IOI2CInterfaceOpen(interface, kNilOptions, &connect);
    IOObjectRelease(interface);
    if (ret != kIOReturnSuccess) return false;

    // Build DDC-CI Set VCP packet
    uint8_t data[7];
    data[0] = 0x51;
    data[1] = 0x84;
    data[2] = 0x03;
    data[3] = command;
    data[4] = 0x00;
    data[5] = value;
    data[6] = DDC_HOST_ADDR ^ xor_checksum(data, 6);

    IOI2CRequest request;
    memset(&request, 0, sizeof(request));
    request.sendAddress = 0x6E;  // DDC write address (8-bit)
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.sendBuffer = (vm_address_t)data;
    request.sendBytes = 7;

    ret = IOI2CSendRequest(connect, kNilOptions, &request);
    IOI2CInterfaceClose(connect, kNilOptions);

    return (ret == kIOReturnSuccess && request.result == kIOReturnSuccess);
}

DDCReadResult ddc_i2c_read(uint8_t command) {
    DDCReadResult result = { false, 0, 0 };

    io_service_t framebuffer = get_framebuffer_port();
    if (framebuffer == IO_OBJECT_NULL) return result;

    io_service_t interface;
    IOReturn ret = IOFBCopyI2CInterfaceForBus(framebuffer, 0, &interface);
    IOObjectRelease(framebuffer);
    if (ret != kIOReturnSuccess) return result;

    IOI2CConnectRef connect;
    ret = IOI2CInterfaceOpen(interface, kNilOptions, &connect);
    IOObjectRelease(interface);
    if (ret != kIOReturnSuccess) return result;

    // Step 1: Send Get VCP request
    uint8_t sendData[5];
    sendData[0] = 0x51;
    sendData[1] = 0x82;
    sendData[2] = 0x01;
    sendData[3] = command;
    sendData[4] = DDC_HOST_ADDR ^ xor_checksum(sendData, 4);

    IOI2CRequest writeReq;
    memset(&writeReq, 0, sizeof(writeReq));
    writeReq.sendAddress = 0x6E;
    writeReq.sendTransactionType = kIOI2CSimpleTransactionType;
    writeReq.sendBuffer = (vm_address_t)sendData;
    writeReq.sendBytes = 5;

    ret = IOI2CSendRequest(connect, kNilOptions, &writeReq);
    if (ret != kIOReturnSuccess || writeReq.result != kIOReturnSuccess) {
        IOI2CInterfaceClose(connect, kNilOptions);
        return result;
    }

    usleep(80000);

    // Step 2: Read response
    uint8_t reply[12];
    memset(reply, 0, sizeof(reply));

    IOI2CRequest readReq;
    memset(&readReq, 0, sizeof(readReq));
    readReq.replyAddress = 0x6F;  // DDC read address
    readReq.replyTransactionType = kIOI2CSimpleTransactionType;
    readReq.replyBuffer = (vm_address_t)reply;
    readReq.replyBytes = 12;

    ret = IOI2CSendRequest(connect, kNilOptions, &readReq);
    IOI2CInterfaceClose(connect, kNilOptions);

    if (ret != kIOReturnSuccess || readReq.result != kIOReturnSuccess) return result;

    // Parse: reply[0]=source, reply[1]=length, reply[2]=opcode(0x02), reply[3]=result, reply[4]=vcp_code
    // reply[5]=type, reply[6]=max_hi, reply[7]=max_lo, reply[8]=cur_hi, reply[9]=cur_lo
    if (reply[2] == 0x02 && reply[3] == 0x00 && reply[4] == command) {
        result.success = true;
        result.maxValue = reply[7];
        result.currentValue = reply[9];
    }

    return result;
}
