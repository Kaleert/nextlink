# NextLink TUN bridge patches

`tun2socks/` is an upstream Git submodule pinned to
`bd06dbfa1d0c376fb0a38dd534edbe87cfcc56bb` from
https://github.com/xjasonlyu/tun2socks.

`tun2socks-nextlink.patch` contains NextLink's engine shutdown/error handling,
UID traffic accounting, UID blocking and their Go tests. These changes are
stored here because no commits have been made to the upstream checkout or a fork.
A plain submodule checkout alone does not include the NextLink changes.

After cloning:

```sh
git submodule update --init -- tun2socks
bash scripts/prepare_tun_bridge.sh
```

`build_tun_bridge.sh` runs preparation automatically. Applying twice is safe;
conflicting local changes cause an error rather than a reset. After preparation,
Git reports the submodule as modified; this is expected for this patch workflow.

To rebuild the Android AAR:

```sh
bash scripts/build_tun_bridge.sh
```

The Android build uses `android/app/libs/t2swrapper.aar`. The duplicate output in
`t2swrapper/` is ignored. When modifying TUN sources, update the patch as well;
new files must be included. Upgrade the upstream pin and patch together.
