int main (string[] args) {
#if SAILFISHOS || !A11Y
    /* Sailfish OS has no AT-SPI accessibility bus, and -Da11y=false builds
       opt out of assistive technology entirely. Select GTK's supported
       no-a11y backend before Adw.Application can initialize GTK; otherwise
       every launch waits for D-Bus and prints a misleading warning. */
    Environment.set_variable ("GTK_A11Y", "none", true);
#endif
    Dc.Platform.setup_macos_bundle_environment ();

    // X11 uses this as WM_CLASS and as the switcher's uninstalled-app name.
    // GtkApplication supplies the desktop-file ID separately on Wayland.
    if (Environment.get_prgname () == null) {
        Environment.set_prgname ("Parla");
    }
    Environment.set_application_name ("Parla");

    /* Initialize gettext before any UI string is constructed. The locale is
       picked from the usual envvars (LANG, LC_ALL, ...); see doc/locales.md
       for how to override it per-launch. */
    GLib.Intl.setlocale (LocaleCategory.ALL, "");
    GLib.Intl.bindtextdomain (Parla.GETTEXT_PACKAGE, Parla.LOCALEDIR);
    GLib.Intl.bind_textdomain_codeset (Parla.GETTEXT_PACKAGE, "UTF-8");
    GLib.Intl.textdomain (Parla.GETTEXT_PACKAGE);

    var app = new Dc.Application ();
    return app.run (args);
}
