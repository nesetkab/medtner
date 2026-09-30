#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *wanted[] = {
    "track_changed", "playing", "paused", "seeked", "stopped",
    "session_connected", "shuffle_changed", "volume_changed", NULL,
};

int main(void) {
    const char *event = getenv("PLAYER_EVENT");
    if (!event) return 0;
    int keep = 0;
    for (int i = 0; wanted[i]; i++) {
        if (strcmp(event, wanted[i]) == 0) keep = 1;
    }
    if (!keep) return 0;
    const char *volume = getenv("VOLUME");
    char payload[128];
    snprintf(payload, sizeof payload, "%s|%s", event, volume ? volume : "");
    CFStringRef object = CFStringCreateWithCString(NULL, payload, kCFStringEncodingUTF8);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
                                         CFSTR("app.medtner.engine.event"), object, NULL, true);
    CFRelease(object);
    return 0;
}
