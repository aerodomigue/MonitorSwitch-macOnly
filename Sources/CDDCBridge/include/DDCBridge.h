#ifndef DDCBridge_h
#define DDCBridge_h

#include <stdint.h>
#include <stdbool.h>
#include <IOKit/IOKitLib.h>

// DDC-CI result structure
typedef struct {
    bool success;
    uint8_t currentValue;
    uint8_t maxValue;
} DDCReadResult;

// Apple Silicon: IOAVService-based DDC
bool ddc_av_write(uint8_t command, uint8_t value);
DDCReadResult ddc_av_read(uint8_t command);

// Intel: IOFramebuffer I2C-based DDC
bool ddc_i2c_write(uint8_t command, uint8_t value);
DDCReadResult ddc_i2c_read(uint8_t command);

#endif /* DDCBridge_h */
