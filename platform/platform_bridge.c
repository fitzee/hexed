#ifdef __APPLE__

int platform_is_macos(void) { return 1; }

#else

int platform_is_macos(void) { return 0; }

/* Stub: mac_show_about is a no-op on non-macOS */
void mac_show_about(const char *name, const char *version, const char *copyright) {
    (void)name; (void)version; (void)copyright;
}

#endif
