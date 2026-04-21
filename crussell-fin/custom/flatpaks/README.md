# Flatpak Management

Flatpak applications are managed declaratively via [Brunch](../../brunch/README.md).

## How It Works

Flatpaks are listed in `brunch/config/flatpaks/brunch.bri` as a simple array of IDs:

```typescript
export const brunchConfig: BrunchConfig = {
  flatpaks: [
    "org.mozilla.firefox",
    "org.gnome.Calculator",
    // ...
  ],
};
```

On `brunch apply`, missing flatpaks are installed and flatpaks removed from the list are uninstalled.

## Finding Flatpak IDs

```bash
flatpak search app-name
```

Or browse Flathub: https://flathub.org/
