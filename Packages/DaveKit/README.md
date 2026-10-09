# DaveKit

DaveKit is SakuraCord's Swift wrapper around the vendored
[Discord Audio and Video End-to-End Encryption (DAVE)](https://github.com/discord/libdave)
and MLS implementations. `MediaPipeline` uses it for voice and video encryption;
the app target does not import DaveKit directly.

Run its package tests with:

```sh
./script/test.sh dave
```

The upstream libdave and MLS++ sources retain their own READMEs and license
files under `Sources/CLibdave` and `Sources/CMLS`.

## Vendored sources

- libdave: `v1.2.1/cpp` from `discord/libdave`.
- MLS++ (including HPKE, bytes, and TLS helpers):
  `fc724c3100ce3b5d8565dbd6d93648a440991a8c` from `cisco/mlspp`.

The SwiftPM integration keeps transient signing keys and the OpenSSL 3 / ML-KEM
adaptations. Preserve those choices when importing upstream source updates.

The sender also retains its nonce sequence when the same MLS key domain is
installed again during a protocol transition, matching the receiver’s replay
protection for repeated ratchets.
