# BULB VPN — Required Icon Assets

## Design Description
- **Central element**: White bolt/lightning symbol
- **Background**: Gradient from `#00E5C0` (top-left) to `#6C63FF` (bottom-right)
- **Style**: Flat, minimal, modern
- **No text** on the icon
- **Rounded corners**: iOS auto-masks; Android uses adaptive icon with 22% corner radius
- **Must be recognizable at 48x48 pixels**

## Android Icons (Place in `android/app/src/main/res/`)

| Folder | Size | Filename |
|--------|------|----------|
| `mipmap-mdpi` | 48×48 | `ic_launcher.png` |
| `mipmap-mdpi` | 108×108 | `ic_launcher_adaptive_foreground.png` |
| `mipmap-hdpi` | 72×72 | `ic_launcher.png` |
| `mipmap-hdpi` | 162×162 | `ic_launcher_adaptive_foreground.png` |
| `mipmap-xhdpi` | 96×96 | `ic_launcher.png` |
| `mipmap-xhdpi` | 216×216 | `ic_launcher_adaptive_foreground.png` |
| `mipmap-xxhdpi` | 144×144 | `ic_launcher.png` |
| `mipmap-xxhdpi` | 324×324 | `ic_launcher_adaptive_foreground.png` |
| `mipmap-xxxhdpi` | 192×192 | `ic_launcher.png` |
| `mipmap-xxxhdpi` | 432×432 | `ic_launcher_adaptive_foreground.png` |

### Adaptive Icon (Android 8.0+)
- **Foreground**: `ic_launcher_adaptive_foreground.png` (108dp grid, icon safe zone 66dp centered)
- **Background**: Solid color `#00E5C0` or gradient drawable
- **Shape mask**: Rounded square (default)

## iOS Icons (Place in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`)

| Filename | Size | Scale | Idiom |
|----------|------|-------|-------|
| `Icon-App-20x20@1x.png` | 20×20 | 1x | iPhone |
| `Icon-App-20x20@2x.png` | 40×40 | 2x | iPhone |
| `Icon-App-20x20@3x.png` | 60×60 | 3x | iPhone |
| `Icon-App-29x29@1x.png` | 29×29 | 1x | iPhone |
| `Icon-App-29x29@2x.png` | 58×58 | 2x | iPhone |
| `Icon-App-29x29@3x.png` | 87×87 | 3x | iPhone |
| `Icon-App-40x40@1x.png` | 40×40 | 1x | iPhone |
| `Icon-App-40x40@2x.png` | 80×80 | 2x | iPhone |
| `Icon-App-40x40@3x.png` | 120×120 | 3x | iPhone |
| `Icon-App-60x60@2x.png` | 120×120 | 2x | iPhone |
| `Icon-App-60x60@3x.png` | 180×180 | 3x | iPhone |
| `Icon-App-76x76@1x.png` | 76×76 | 1x | iPad |
| `Icon-App-76x76@2x.png` | 152×152 | 2x | iPad |
| `Icon-App-83.5x83.5@2x.png` | 167×167 | 2x | iPad |
| `Icon-App-1024x1024@1x.png` | 1024×1024 | 1x | App Store |

## Generation Tools
- Android: Android Studio Image Asset Studio
- iOS: Xcode Asset Catalog or `appiconset` generator
- Cross-platform: [Icon Kitchen](https://icon.kitchen) or [App Icon Generator](https://www.appicon.co/)

## Notes
- All icons must be PNG format, no transparency in the final icon
- The 1024×1024 icon is used by the App Store / Play Store listing
- Test every size: icons should be clear and readable at 48×48
