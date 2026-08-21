/*
 * speccy_bridge.cpp - the plain-C ABI over UnrealSpeccy Portable.
 *
 * A third adapter over xPlatform::eHandler, alongside platform/android/
 * android.cpp and platform/sdl2/sdl2.cpp. It owns no emulation logic; every
 * function here is a translation of one handler call into C types.
 *
 * The one piece of real work is speccy_core_get_framebuffer: the core renders
 * 8-bit palette indices and every existing backend converts those to pixels
 * itself. We do the same conversion, to RGBA8888, with the palette built by
 * the same bit formula gles2.cpp uses -- so the colours a Flutter host draws
 * match the SDL2 and Android builds exactly.
 */

#include "speccy_bridge.h"
#include "audio_backend.h"

#include <string.h>
#include <string>

#include "platform/platform.h"
#include "platform/io.h"
#include "options_common.h"
#include "tools/options.h"
#include "tools/sound_mixer.h"
#include "speccy.h"
#include "devices/ula.h"
#include "devices/input/kempston_joy.h"

/*
 * The -DUSE_EXTERN_RESOURCES ROM globals. android.cpp defines these itself;
 * so must we, since a build links one adapter or the other, never both.
 */
byte sos128_0[16384];
byte sos128_1[16384];
byte sos48[16384];
byte service[16384];
byte dos513f[16384];
byte spxtrm4f[2048];

namespace xPlatform
{
void ProcessKey(char key, bool down, bool shift, bool alt);
/*
 * Touch input is a no-op here by design: the host draws its own controls as
 * widgets and feeds them back through speccy_core_key_event. These stubs
 * exist only because the core's link expects the symbols, exactly as
 * android.cpp stubs them.
 */
void OnTouchKey(float x, float y, bool down, int pointer_id) {}
void OnTouchJoy(float x, float y, bool down, int pointer_id) {}
}

namespace {

using namespace xPlatform;

/*
 * Init/Done are static in every adapter -- android.cpp and sdl2.cpp each
 * define their own -- so this one does too, mirroring android.cpp's.
 * InitSound/DoneSound are omitted deliberately: they are empty on Android,
 * and this bridge drives its own eSoundMixer in speccy_core_drain_audio.
 */
void CoreInit(const char* profile)
{
	char buf[xIo::MAX_PATH_LEN];
	strncpy(buf, profile, sizeof(buf) - 2);
	buf[sizeof(buf) - 2] = 0;
	strcat(buf, "/");
	xIo::SetProfilePath(buf);
	Handler()->OnInit();
}

void CoreDone()
{
	Handler()->OnDone();
}

bool g_running = false;
bool g_paused = false;
int32_t g_frame_counter = 0;
int32_t g_audio_level = 0;
int32_t g_sample_rate = 44100;
std::string g_profile_dir;
std::string g_resource_dir;

eSoundMixer g_sound_mixer;

uint32_t g_framebuffer[SPECCY_SCREEN_WIDTH * SPECCY_SCREEN_HEIGHT];

/*
 * The 16 ULA colours, as RGBA8888. Same construction as eCachedColors in
 * platform/gles2/gles2.cpp: bit 0 blue, bit 1 red, bit 2 green, bit 3 the
 * bright flag, with the two intensity levels the emulator has always used.
 */
struct ePalette
{
	ePalette()
	{
		const byte brightness = 200;
		const byte bright_intensity = 55;
		for(int c = 0; c < 16; ++c)
		{
			byte i = (c & 8) ? (byte)(brightness + bright_intensity) : brightness;
			byte b = (c & 1) ? i : 0;
			byte r = (c & 2) ? i : 0;
			byte g = (c & 4) ? i : 0;
			/* Little-endian RGBA8888: R in the low byte, as dart:ffi and
			 * Flutter's Image.memory both expect. */
			items[c] = (uint32_t)r | ((uint32_t)g << 8) | ((uint32_t)b << 16) | 0xff000000u;
		}
	}
	uint32_t items[16];
} g_palette;

} // namespace

extern "C" {

/* ---------------------------------------------------------------- lifecycle */

void speccy_core_init(const char *profile_dir, const char *resource_dir)
{
	g_profile_dir = profile_dir ? profile_dir : "";
	g_resource_dir = resource_dir ? resource_dir : "";
}

void speccy_core_set_rom(int32_t id, const void *data, int32_t size)
{
	if(!data || size <= 0)
		return;
	switch(id)
	{
	case SPECCY_ROM_SOS128_0: memcpy(sos128_0, data, size < (int32_t)sizeof(sos128_0) ? size : (int32_t)sizeof(sos128_0)); break;
	case SPECCY_ROM_SOS128_1: memcpy(sos128_1, data, size < (int32_t)sizeof(sos128_1) ? size : (int32_t)sizeof(sos128_1)); break;
	case SPECCY_ROM_SOS48:    memcpy(sos48,    data, size < (int32_t)sizeof(sos48)    ? size : (int32_t)sizeof(sos48));    break;
	case SPECCY_ROM_SERVICE:  memcpy(service,  data, size < (int32_t)sizeof(service)  ? size : (int32_t)sizeof(service));  break;
	case SPECCY_ROM_DOS:      memcpy(dos513f,  data, size < (int32_t)sizeof(dos513f)  ? size : (int32_t)sizeof(dos513f));  break;
	default: break;
	}
}

void speccy_core_set_font(const void *data, int32_t size)
{
	if(!data || size <= 0)
		return;
	memcpy(spxtrm4f, data, size < (int32_t)sizeof(spxtrm4f) ? size : (int32_t)sizeof(spxtrm4f));
}

int32_t speccy_core_start(void)
{
	if(g_running)
		return 0;
	if(!xPlatform::Handler())
		return -1;
	CoreInit(g_profile_dir.c_str());
	Handler()->AudioSetSampleRate(g_sample_rate);
	/* Opened here rather than by the host: the device has to agree with the
	   rate the core was just told to mix at, and doing it in one place is
	   what stops the two drifting. A failure is not fatal -- a silent
	   emulator still plays. */
	speccy_audio_start(g_sample_rate);
	g_running = true;
	g_paused = false;
	g_frame_counter = 0;
	return 0;
}

void speccy_core_stop(void)
{
	if(!g_running)
		return;
	CoreDone();
	/* Closed, not just silenced. An open AAudio stream holds an AudioMix
	   wake lock for as long as it exists, so leaving one behind keeps the
	   CPU awake with nothing playing -- the same fault, and the same fix,
	   as Retro-Amiga's music player. */
	speccy_audio_stop();
	g_running = false;
	g_paused = false;
}

int32_t speccy_core_is_running(void) { return g_running ? 1 : 0; }

const char *speccy_core_run_frame(void)
{
	if(!g_running || g_paused)
		return NULL;
	const char *err = Handler()->OnLoop();
	if(!err)
		++g_frame_counter;
	return err;
}

void speccy_core_set_paused(int32_t paused)
{
	g_paused = paused != 0;
	/* Muted rather than closed: a pause is usually brief, and reopening the
	   device costs more than the silence is worth. */
	speccy_audio_set_muted(g_paused ? 1 : 0);
	if(g_running)
		Handler()->VideoPaused(g_paused);
}

void speccy_core_reset(void)
{
	if(g_running)
		Handler()->OnAction(A_RESET);
}

/* ------------------------------------------------------------------- video */

const uint32_t *speccy_core_get_framebuffer(int32_t *w, int32_t *h)
{
	if(w) *w = SPECCY_SCREEN_WIDTH;
	if(h) *h = SPECCY_SCREEN_HEIGHT;
	if(!g_running)
		return g_framebuffer;
	const byte *src = (const byte *)Handler()->VideoData();
	if(!src)
		return g_framebuffer;
	uint32_t *dst = g_framebuffer;
	for(int i = SPECCY_SCREEN_WIDTH * SPECCY_SCREEN_HEIGHT; --i >= 0;)
		*dst++ = g_palette.items[*src++ & 0x0f];
	return g_framebuffer;
}

int32_t speccy_core_get_frame_counter(void) { return g_frame_counter; }

/* ------------------------------------------------------------------- audio */

int32_t speccy_core_drain_audio(void *dst, int32_t max_bytes)
{
	if(!g_running || !dst || max_bytes <= 0)
		return 0;
	g_sound_mixer.Update((byte *)dst);
	dword size = g_sound_mixer.Ready();
	if((int32_t)size > max_bytes)
		size = (dword)max_bytes;
	g_sound_mixer.Use(size, (byte *)dst);

	/* Peak level over the drained window, for the host's meter. Signed 16-bit
	 * stereo, so step two bytes at a time. */
	int32_t peak = 0;
	const int16_t *s = (const int16_t *)dst;
	for(dword i = 0; i < size / 2; ++i)
	{
		int32_t v = s[i] < 0 ? -s[i] : s[i];
		if(v > peak)
			peak = v;
	}
	g_audio_level = peak * 1000 / 32768;
	return (int32_t)size;
}

void speccy_core_set_sample_rate(int32_t rate)
{
	g_sample_rate = rate;
	if(g_running)
		Handler()->AudioSetSampleRate(rate);
}

int32_t speccy_core_get_audio_level(void) { return g_audio_level; }

/* ------------------------------------------------------------------- input */

void speccy_core_key_event(int32_t key, int32_t flags)
{
	if(g_running)
		Handler()->OnKey((char)key, (dword)flags);
}

void speccy_core_kempston(int32_t mask)
{
	if(!g_running)
		return;
	eSpeccy *s = Handler()->Speccy();
	if(!s)
		return;
	eKempstonJoy *joy = s->Device<eKempstonJoy>();
	if(!joy)
		return;
	/* Bit order matches the sibling front ends' joystick masks:
	 * 0x01 up, 0x02 down, 0x04 left, 0x08 right, 0x10 fire. */
	joy->OnKey('u', (mask & 0x01) != 0);
	joy->OnKey('d', (mask & 0x02) != 0);
	joy->OnKey('l', (mask & 0x04) != 0);
	joy->OnKey('r', (mask & 0x08) != 0);
	joy->OnKey('f', (mask & 0x10) != 0);
}

/* ------------------------------------------------------------------- media */

int32_t speccy_core_file_type_supported(const char *name)
{
	if(!name || !g_running)
		return 0;
	return Handler()->FileTypeSupported(name) ? 1 : 0;
}

int32_t speccy_core_open_file(const char *path)
{
	if(!path || !g_running)
		return -1;
	return Handler()->OnOpenFile(path) ? 0 : -1;
}

int32_t speccy_core_open_data(const char *name, const void *data, int32_t size)
{
	if(!name || !data || size <= 0 || !g_running)
		return -1;
	return Handler()->OnOpenFile(name, data, (size_t)size) ? 0 : -1;
}

int32_t speccy_core_save_file(const char *path)
{
	if(!path || !g_running)
		return -1;
	return Handler()->OnSaveFile(path) ? 0 : -1;
}

int32_t speccy_core_tape_state(void)
{
	if(!g_running)
		return -1;
	switch(Handler()->OnAction(A_TAPE_QUERY))
	{
	case AR_TAPE_NOT_INSERTED: return -1;
	case AR_TAPE_STOPPED:      return 0;
	case AR_TAPE_STARTED:      return 1;
	default:                   return -1;
	}
}

void speccy_core_tape_toggle(void)
{
	if(g_running)
		Handler()->OnAction(A_TAPE_TOGGLE);
}

int32_t speccy_core_disk_changed(void)
{
	if(!g_running)
		return 0;
	return Handler()->OnAction(A_DISK_QUERY) == AR_DISK_CHANGED ? 1 : 0;
}

/* ------------------------------------------------------------- save states */

int32_t speccy_core_save_state(const char *path)
{
	if(!path || !g_running)
		return -1;
	return Handler()->OnSaveFile(path) ? 0 : -1;
}

int32_t speccy_core_load_state(const char *path)
{
	if(!path || !g_running)
		return -1;
	return Handler()->OnOpenFile(path) ? 0 : -1;
}

/* ----------------------------------------------------------------- options */

int32_t speccy_core_get_option_int(const char *name, int32_t fallback)
{
	if(!name)
		return fallback;
	xOptions::eOption<int> *o = xOptions::eOption<int>::Find(name);
	return o ? *o : fallback;
}

void speccy_core_set_option_int(const char *name, int32_t value)
{
	if(!name)
		return;
	xOptions::eOption<int> *o = xOptions::eOption<int>::Find(name);
	if(o)
	{
		o->Set(value);
		o->Apply();
	}
}

int32_t speccy_core_get_option_bool(const char *name, int32_t fallback)
{
	if(!name)
		return fallback;
	xOptions::eOption<bool> *o = xOptions::eOption<bool>::Find(name);
	return o ? (*o ? 1 : 0) : fallback;
}

void speccy_core_set_option_bool(const char *name, int32_t value)
{
	if(!name)
		return;
	xOptions::eOption<bool> *o = xOptions::eOption<bool>::Find(name);
	if(o)
	{
		o->Set(value != 0);
		o->Apply();
	}
}

void speccy_core_store_options(void)
{
	xOptions::Store();
}

/* ------------------------------------------------------------------ status */

int32_t speccy_core_get_fps_x100(void)
{
	/* The Spectrum's ULA is fixed at 50Hz; the core has no measured-FPS
	 * counter of its own. The host measures wall-clock rate if it wants a
	 * real figure -- this reports the nominal one. */
	return 5000;
}

int32_t speccy_core_replay_progress(int32_t *frame_current,
                                    int32_t *frames_total,
                                    int32_t *frames_cached)
{
	if(frame_current) *frame_current = 0;
	if(frames_total)  *frames_total = 0;
	if(frames_cached) *frames_cached = 0;
	if(!g_running)
		return 0;
	dword cur = 0, total = 0, cached = 0;
	bool active = Handler()->GetReplayProgress(&cur, &total, &cached);
	if(frame_current) *frame_current = (int32_t)cur;
	if(frames_total)  *frames_total = (int32_t)total;
	if(frames_cached) *frames_cached = (int32_t)cached;
	return active ? 1 : 0;
}

} /* extern "C" */
