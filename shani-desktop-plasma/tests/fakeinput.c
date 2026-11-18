/* Wayland-native input injection for the test harness, using KWin's
 * org_kde_kwin_fake_input protocol (the same one KDE Connect uses) - the
 * compositor's own virtual keyboard/pointer protocols are not implemented
 * by KWin, and X11 XTest cannot reach Wayland popups.
 *
 *   fakeinput click X Y   absolute pointer move + left press/release
 *   fakeinput move X Y    absolute pointer move (hover)
 *   fakeinput key <keysym-hex>   press+release a keysym (e.g. ff1b = Escape)
 *
 * Build: cc -O2 -o fakeinput fakeinput.c -lwayland-client
 * Requests are hand-marshalled (opcodes per plasma-wayland-protocols
 * fake-input.xml); the stub wl_interface is enough because none of the
 * requests used here create proxy objects.
 */
#include <wayland-client.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OP_AUTHENTICATE 0
#define OP_BUTTON 2
#define OP_POINTER_MOTION_ABSOLUTE 9
#define OP_KEYBOARD_KEYSYM 12

static const struct wl_message fake_requests[] = {
    {"authenticate", "ss", NULL},
    {"pointer_motion", "ff", NULL},
    {"button", "uu", NULL},
    {"axis", "uf", NULL},
    {"touch_down", "uiff", NULL},
    {"touch_motion", "uiff", NULL},
    {"touch_up", "u", NULL},
    {"touch_cancel", "", NULL},
    {"touch_frame", "", NULL},
    {"pointer_motion_absolute", "ff", NULL},
    {"keyboard_key", "uu", NULL},
    {"destroy", "", NULL},
    {"keyboard_keysym", "uu", NULL},
};
static const struct wl_interface fake_if = {
    "org_kde_kwin_fake_input", 6, 13, fake_requests, 0, NULL};
static struct wl_proxy *fake;

static void global_add(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    if (strcmp(iface, "org_kde_kwin_fake_input") == 0) {
        uint32_t v = version > 6 ? 6 : version;
        fake = (struct wl_proxy *)wl_registry_bind(reg, name, &fake_if, v);
    }
}
static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {}

static const struct wl_registry_listener reg_listener = {global_add, global_remove};

static wl_fixed_t fx(double d) { return (wl_fixed_t)(d * 256); }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: fakeinput click X Y | move X Y | key <keysym-hex>\n"); return 2; }
    struct wl_display *d = wl_display_connect(NULL);
    if (!d) { fprintf(stderr, "fakeinput: no WAYLAND_DISPLAY\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(d);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(d);
    if (!fake) { fprintf(stderr, "fakeinput: compositor does not advertise org_kde_kwin_fake_input\n"); return 1; }
    /* authenticate (request 0): kwin grants this to the container's root */
    wl_proxy_marshal(fake, OP_AUTHENTICATE, "shani-plasma-session-test", "theme harness input injection");

    if (strcmp(argv[1], "click") == 0 && argc == 4) {
        wl_fixed_t x = fx(atof(argv[2])), y = fx(atof(argv[3]));
        wl_proxy_marshal(fake, OP_POINTER_MOTION_ABSOLUTE, x, y);
        wl_proxy_marshal(fake, OP_BUTTON, (uint32_t)0x110, (uint32_t)1);
        wl_proxy_marshal(fake, OP_BUTTON, (uint32_t)0x110, (uint32_t)0);
    } else if (strcmp(argv[1], "move") == 0 && argc == 4) {
        wl_proxy_marshal(fake, OP_POINTER_MOTION_ABSOLUTE, fx(atof(argv[2])), fx(atof(argv[3])));
    } else if (strcmp(argv[1], "key") == 0 && argc == 3) {
        uint32_t ks = (uint32_t)strtoul(argv[2], NULL, 16);
        wl_proxy_marshal(fake, OP_KEYBOARD_KEYSYM, ks, (uint32_t)1);
        wl_proxy_marshal(fake, OP_KEYBOARD_KEYSYM, ks, (uint32_t)0);
    } else {
        fprintf(stderr, "fakeinput: bad args\n"); return 2;
    }
    wl_display_flush(d);
    wl_display_roundtrip(d);
    return 0;
}
