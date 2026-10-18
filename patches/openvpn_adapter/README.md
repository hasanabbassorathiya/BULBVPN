# OpenVPNAdapter SoftEther patches

Applied automatically by `scripts/patch_openvpn_adapter.sh` from the iOS and
macOS `Podfile` `post_install` hooks after every `pod install`.

Target: OpenVPNAdapter **0.7.0** (`ss-abramchuk/OpenVPNAdapter` tag).

| Patch | Effect |
| --- | --- |
| `01-mbedtls-sslctx-softether-tls10.patch` | When `force_aes_cbc_ciphersuites` is set, pin TLS min+max to 1.0 so profile `tls-version-min` cannot stall the handshake after VERIFY OK. |
| `02-cliopt-force-aes-after-load.patch` | Re-apply `force_aes_cbc_ciphersuites` after `load()` so profile options cannot clear it. |

Pods are gitignored; do not rely on editing files under `*/Pods/OpenVPNAdapter`.
