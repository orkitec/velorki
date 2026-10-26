// Unfolds and turns an iPhone Duo simulator, as the hinge slider and the
// orientation picker of Xcode's Device Hub do. Built for the simulator and run
// inside it by tool/store_screenshots.sh --platform duo (and, to hold the iPad
// sideways, --platform ipad):
//
//   xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -O2 \
//     -o duo_state duo_state.c -framework IOKit -framework CoreFoundation
//   codesign -f -s - duo_state
//   xcrun simctl spawn <udid> /abs/path/duo_state hinge 180
//   xcrun simctl spawn <udid> /abs/path/duo_state orientation portrait
//
// hinge takes degrees, 0 to 180 (180 is unfolded); orientation one of
// portrait, landscape-left, landscape-right, pud. Each posts a vendor-defined
// HID event (usage page 0xFF61, usage 0x5B) whose data is a serialized
// dictionary naming the control and its value.
//
// After hinge_helper.c of https://github.com/artemnovichkov/hinge, under the
// MIT licence below (the rest of this repository is AGPL-3.0-only):
//
// MIT License
//
// Copyright (c) 2026 Artem Novichkov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventRef IOHIDEventCreateVendorDefinedEvent(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t usagePage, uint32_t usage, uint32_t version, const uint8_t *data, CFIndex length, uint32_t options);
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, int type,
    CFDictionaryRef properties);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern CFDataRef IOCFSerialize(CFTypeRef object, CFOptionFlags options);

enum {
    kUsagePage = 0xFF61,
    kUsage = 0x5B,
    kClientTypeSimple = 4,
    kSerializeBinary = 1,
};

// Posts {provider, source, type, value} as the Device Hub's control would.
static int post(CFStringRef source, CFStringRef type, CFTypeRef value) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateWithType(NULL, kClientTypeSimple, NULL);
    if (!client) {
        fprintf(stderr, "duo_state: no HID event system client\n");
        return 1;
    }
    const void *keys[] = {CFSTR("provider"), CFSTR("source"), CFSTR("type"), CFSTR("value")};
    const void *values[] = {CFSTR("com.apple.Virtualization"), source, type, value};
    CFDictionaryRef payload = CFDictionaryCreate(NULL, keys, values, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = IOCFSerialize(payload, kSerializeBinary);
    int status = 1;
    if (data) {
        IOHIDEventRef event = IOHIDEventCreateVendorDefinedEvent(NULL, mach_absolute_time(), kUsagePage, kUsage, 0,
            CFDataGetBytePtr(data), CFDataGetLength(data), 0);
        if (event) {
            IOHIDEventSystemClientDispatchEvent(client, event);
            CFRelease(event);
            status = 0;
        }
        CFRelease(data);
    }
    CFRelease(payload);
    // A moment for the event system to deliver it before the process exits.
    usleep(100000);
    CFRelease(client);
    if (status) fprintf(stderr, "duo_state: could not post the event\n");
    return status;
}

static int usage(void) {
    fprintf(stderr, "usage: duo_state hinge <0-180>\n"
                    "       duo_state orientation portrait|landscape-left|landscape-right|pud\n");
    return 64;
}

int main(int argc, char **argv) {
    if (argc != 3) return usage();
    if (strcmp(argv[1], "hinge") == 0) {
        double degrees = atof(argv[2]);
        if (degrees < 0) degrees = 0;
        if (degrees > 180) degrees = 180;
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &degrees);
        int status = post(CFSTR("hinge-slider-control"), CFSTR("range"), value);
        CFRelease(value);
        return status;
    }
    if (strcmp(argv[1], "orientation") == 0) {
        const char *known[] = {"portrait", "landscape-left", "landscape-right", "pud"};
        int ok = 0;
        for (size_t i = 0; i < sizeof known / sizeof *known; i++) ok |= strcmp(argv[2], known[i]) == 0;
        if (!ok) return usage();
        CFStringRef value = CFStringCreateWithCString(NULL, argv[2], kCFStringEncodingUTF8);
        int status = post(CFSTR("orientation-picker-control"), CFSTR("enum"), value);
        CFRelease(value);
        return status;
    }
    return usage();
}
