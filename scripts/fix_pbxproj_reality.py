import uuid, re

path = 'ios/Runner.xcodeproj/project.pbxproj'
with open(path) as f:
    content = f.read()

existing_ids = set(re.findall(r'\b[0-9A-F]{24}\b', content))


def gen_id():
    while True:
        id_ = uuid.uuid4().hex.upper()[:24]
        if id_ not in existing_ids:
            existing_ids.add(id_)
            return id_


ids = {
    'pods_debug': gen_id(),
    'pods_release': gen_id(),
    'pods_profile': gen_id(),
    'cfg_debug': gen_id(),
    'cfg_release': gen_id(),
    'cfg_profile': gen_id(),
    'cfg_list': gen_id(),
}

T = '\t'
NL = '\n'

# --- 1. PBXFileReference entries for the 3 xcconfig files ---
pods_refs = ''
for key, fname in [('pods_debug', 'Pods-RealityExtension.debug.xcconfig'),
                   ('pods_release', 'Pods-RealityExtension.release.xcconfig'),
                   ('pods_profile', 'Pods-RealityExtension.profile.xcconfig')]:
    pods_refs += (
        T + T + ids[key] + ' /* ' + fname + ' */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; '
        + 'name = "' + fname + '"; path = "Target Support Files/Pods-RealityExtension/' + fname + '"; sourceTree = "<group>"; };'
        + NL
    )

anchor = '/* End PBXFileReference section */'
assert content.count(anchor) == 1, "PBXFileReference section anchor not found or duplicated"
content = content.replace(anchor, pods_refs + anchor)

# --- 2. Add xcconfig refs to Pods group children ---
old_pods_children = (
    T + T + T + 'E290AB978336A1D64EED7007 /* Pods-VPNExtension.debug.xcconfig */,' + NL
    + T + T + T + 'B26B2BD9A74ED16D47F7FF4F /* Pods-VPNExtension.release.xcconfig */,' + NL
    + T + T + T + 'F36544882EF29DAC99E9A5E5 /* Pods-VPNExtension.profile.xcconfig */,' + NL
)
name_map = {
    'pods_debug': 'debug',
    'pods_release': 'release',
    'pods_profile': 'profile',
}
new_pods_children = old_pods_children
for key in ['pods_debug', 'pods_release', 'pods_profile']:
    new_pods_children += T + T + T + ids[key] + ' /* Pods-RealityExtension.' + name_map[key] + '.xcconfig */,' + NL
assert content.count(old_pods_children) == 1, "Pods group children anchor not found"
content = content.replace(old_pods_children, new_pods_children)

# --- 3. XCBuildConfiguration entries for RealityExtension ---
def config_block(cfg_id, cfg_name, pods_id, pods_name, debug_extra):
    lines = []
    lines.append(T + cfg_id + ' /* ' + cfg_name + ' */ = {')
    lines.append(T + T + 'isa = XCBuildConfiguration;')
    lines.append(T + T + 'baseConfigurationReference = ' + pods_id + ' /* ' + pods_name + ' */;')
    lines.append(T + T + 'buildSettings = {')
    lines.append(T + T + T + 'CODE_SIGN_ENTITLEMENTS = RealityExtension/RealityExtension.entitlements;')
    lines.append(T + T + T + 'CODE_SIGN_STYLE = Automatic;')
    lines.append(T + T + T + 'CURRENT_PROJECT_VERSION = 20;')
    lines.append(T + T + T + 'DEVELOPMENT_TEAM = 3477R2P24R;')
    lines.append(T + T + T + 'ENABLE_USER_SCRIPT_SANDBOXING = YES;')
    lines.append(T + T + T + 'GENERATE_INFOPLIST_FILE = YES;')
    lines.append(T + T + T + 'INFOPLIST_FILE = RealityExtension/Info.plist;')
    lines.append(T + T + T + 'INFOPLIST_KEY_CFBundleDisplayName = BULBVPN;')
    lines.append(T + T + T + 'INFOPLIST_KEY_NSHumanReadableCopyright = "";')
    lines.append(T + T + T + 'IPHONEOS_DEPLOYMENT_TARGET = 15.6;')
    lines.append(T + T + T + 'LD_RUNPATH_SEARCH_PATHS = (')
    lines.append(T + T + T + T + '"$(inherited)",')
    lines.append(T + T + T + T + '"@executable_path/Frameworks",')
    lines.append(T + T + T + T + '"@executable_path/../../Frameworks",')
    lines.append(T + T + T + ');')
    lines.append(T + T + T + 'LOCALIZATION_PREFERS_STRING_CATALOGS = YES;')
    lines.append(T + T + T + 'MARKETING_VERSION = 1.2.0;')
    lines.append(T + T + T + 'PRODUCT_BUNDLE_IDENTIFIER = app.bulbvpn.com.RealityExtension;')
    lines.append(T + T + T + 'PRODUCT_MODULE_NAME = PacketTunnelProvider;')
    lines.append(T + T + T + 'PRODUCT_NAME = "$(TARGET_NAME)";')
    lines.append(T + T + T + 'SKIP_INSTALL = YES;')
    lines.append(T + T + T + 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
    lines.append(T + T + T + 'SUPPORTS_MACCATALYST = NO;')
    lines.append(T + T + T + 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;')
    lines.append(T + T + T + 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;')
    if debug_extra:
        lines.append(T + T + T + 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
        lines.append(T + T + T + 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    lines.append(T + T + T + 'SWIFT_EMIT_LOC_STRINGS = YES;')
    lines.append(T + T + T + 'SWIFT_VERSION = 5.0;')
    lines.append(T + T + T + 'TARGETED_DEVICE_FAMILY = "1,2";')
    lines.append(T + T + '};')
    lines.append(T + T + 'name = ' + cfg_name + ';')
    lines.append(T + '};')
    return NL.join(lines) + NL


configs = ''
configs += config_block(ids['cfg_debug'], 'Debug', ids['pods_debug'],
                        'Pods-RealityExtension.debug.xcconfig', True)
configs += config_block(ids['cfg_release'], 'Release', ids['pods_release'],
                        'Pods-RealityExtension.release.xcconfig', False)
configs += config_block(ids['cfg_profile'], 'Profile', ids['pods_profile'],
                        'Pods-RealityExtension.profile.xcconfig', False)

anchor = '/* End XCBuildConfiguration section */'
assert content.count(anchor) == 1, "XCBuildConfiguration section anchor not found"
content = content.replace(anchor, configs + anchor)

# --- 4. XCConfigurationList for RealityExtension ---
config_list = (
    T + ids['cfg_list'] + ' /* Build configuration list for PBXNativeTarget "RealityExtension" */ = {'
    + NL + T + T + 'isa = XCConfigurationList;' + NL
    + T + T + 'buildConfigurations = (' + NL
    + T + T + T + ids['cfg_debug'] + ' /* Debug */,' + NL
    + T + T + T + ids['cfg_release'] + ' /* Release */,' + NL
    + T + T + T + ids['cfg_profile'] + ' /* Profile */,' + NL
    + T + T + ');' + NL
    + T + T + 'defaultConfigurationIsVisible = 0;' + NL
    + T + T + 'defaultConfigurationName = Release;' + NL
    + T + '};' + NL
)

anchor = '/* End XCConfigurationList section */'
assert content.count(anchor) == 1, "XCConfigurationList section anchor not found"
content = content.replace(anchor, config_list + anchor)

# --- 5. Fix dangling fileSystemSynchronizedGroups on RealityExtension target ---
old_fs = (
    T + T + T + 'fileSystemSynchronizedGroups = (' + NL
    + T + T + T + T + 'C24F6C41D71F4995B96129BC210503B6 /* RealityExtension */,' + NL
    + T + T + T + ');' + NL
)
assert content.count(old_fs) == 1, "fileSystemSynchronizedGroups anchor not found"
content = content.replace(old_fs, '')

with open(path, 'w') as f:
    f.write(content)

print("All insertions done successfully.")
print(f"Pods file refs: {ids['pods_debug']}, {ids['pods_release']}, {ids['pods_profile']}")
print(f"Configs: {ids['cfg_debug']}, {ids['cfg_release']}, {ids['cfg_profile']}")
print(f"Config list: {ids['cfg_list']}")
