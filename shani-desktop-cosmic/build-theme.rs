// build-theme.rs — generates etc/skel/.config/cosmic/com.system76.CosmicTheme.*
// (Dark, Dark.Builder, Light, Light.Builder; config version v2) — the Saturn
// COSMIC themes. Not shipped (the PKGBUILD copies only etc/ and usr/).
//
// Uses COSMIC's own ThemeBuilder and writes through cosmic-config exactly as
// cosmic-settings does, so the derived theme is what COSMIC itself would
// compute; never hand-edit the generated files. Colours are roles from
// shani-desktop-plasma's Saturn.colors / SaturnDark.colors.
//
// Regenerate (libcosmic at the revision Arch's cosmic-settings pins — see its
// Cargo.lock at tag epoch-<version>; 1.8.0 -> 2a73fbc0edfe):
//   git clone https://github.com/pop-os/libcosmic && cd libcosmic
//   git checkout 2a73fbc0edfe1525381bf999e241d73def79b222
//   git submodule update --init --depth 1 iced
//   cp <this file> cosmic-theme/examples/saturn.rs
//   XDG_CONFIG_HOME=$PWD/out cargo run --example saturn   (in cosmic-theme/)
//   then copy out/cosmic/com.system76.CosmicTheme.*/v2 into etc/skel/.config/cosmic/
//   and out/gtk-4.0/cosmic/{dark,light}.css into etc/skel/.config/gtk-4.0/cosmic/
//   (gtk-{3,4}.0/gtk.css are relative symlinks to cosmic/dark.css - not the
//   absolute ones apply_gtk() makes, which would point into this machine's home)
//
// COSMIC reads the highest version first and falls back to older ones, so
// if a future COSMIC bumps the theme to v3, regenerate rather than keep v2.
use cosmic_config::CosmicConfigEntry;
use cosmic_theme::{palette::Srgba, palette::Srgb, Theme, ThemeBuilder};

fn rgb(h: &str) -> Srgb { let v = u32::from_str_radix(&h[1..], 16).unwrap();
    Srgb::new(((v >> 16) & 255) as f32 / 255.0, ((v >> 8) & 255) as f32 / 255.0, (v & 255) as f32 / 255.0) }
fn rgba(h: &str) -> Srgba { let c = rgb(h); Srgba::new(c.red, c.green, c.blue, 1.0) }

fn saturn(dark: bool) -> ThemeBuilder {
    let (b, p) = if dark { (ThemeBuilder::dark(), [
        "#252434", "#2d2c3b", "#353443", "#ff7f50", "#7dd6aa", "#ffc69b", "#ff8f8f", "#dedee1", "#454456"])
    } else { (ThemeBuilder::light(), [
        "#f2eee9", "#f7f3ed", "#eeeae5", "#bc3e18", "#1e7a54", "#965400", "#b02020", "#232627", "#d2cdc6"]) };
    let mut b = b;
    b.bg_color = Some(rgba(p[0]));
    b.primary_container_bg = Some(rgba(p[1]));
    b.secondary_container_bg = Some(rgba(p[2]));
    b.accent = Some(rgb(p[3]));
    b.success = Some(rgb(p[4]));
    b.warning = Some(rgb(p[5]));
    b.destructive = Some(rgb(p[6]));
    b.text_tint = Some(rgb(p[7]));
    b.neutral_tint = Some(rgb(p[8]));
    // frosted like Plasma's Saturn panel/popups; app windows stay opaque
    b.frosted_panel = true;
    b.frosted_applets = true;
    b.frosted_system_interface = true;
    b
}

fn main() {
    for dark in [true, false] {
        let b = saturn(dark);
        let t: Theme = b.clone().build();
        let (bc, tc) = if dark { (ThemeBuilder::dark_config(), Theme::dark_config()) }
                       else { (ThemeBuilder::light_config(), Theme::light_config()) };
        b.write_entry(&bc.unwrap()).expect("builder");
        t.write_entry(&tc.unwrap()).expect("theme");
        // GTK apps: the CSS cosmic-settings writes when "apply theme to GTK" is on
        t.write_gtk4().expect("gtk4 css");
        println!("{} written: accent {:?}", if dark { "dark" } else { "light" }, t.accent.base);
    }
}
