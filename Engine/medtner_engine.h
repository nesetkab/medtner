#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void (*MedtnerAudioCallback)(void *context, const float *samples, size_t count);
typedef void (*MedtnerEventCallback)(void *context, const char *event, int64_t value);

typedef struct {
    const char *name;
    const char *log_path;
    const char *system_cache;
    const char *audio_cache;
    uint64_t audio_cache_limit;
    uint32_t bitrate;
    bool normalize;
    uint32_t initial_volume;
    bool autoplay;
    MedtnerAudioCallback audio;
    MedtnerEventCallback event;
    void *context;
} MedtnerEngineConfig;

bool medtner_engine_start(const MedtnerEngineConfig *config);
void medtner_engine_stop(void);
bool medtner_engine_radio(const char *track_uri);
bool medtner_engine_next(void);
bool medtner_engine_previous(void);
bool medtner_engine_seek(uint32_t position_ms);
