package t2swrapper

import (
	"fmt"

	"github.com/xjasonlyu/tun2socks/v2/engine"
	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

func StartVpn(fd int32, proxy string) error {
	key := &engine.Key{
		Device:   fmt.Sprintf("fd://%d", fd),
		Proxy:    proxy,
		LogLevel: "debug",
	}

	engine.Insert(key)
	return engine.StartWithError()
}

func StopVpn() error {
	return engine.StopWithError()
}

type OwnerResolver interface {
	LookupOwner(protocol int32, source string, sourcePort int32, destination string, destinationPort int32) int32
}

func SetOwnerResolver(resolver OwnerResolver) {
	if resolver == nil {
		statistic.SetOwnerLookup(nil)
		return
	}
	statistic.SetOwnerLookup(func(protocol int, source string, sourcePort int, destination string, destinationPort int) int {
		return int(resolver.LookupOwner(int32(protocol), source, int32(sourcePort), destination, int32(destinationPort)))
	})
}
func ResetTraffic()           { statistic.ResetTraffic() }
func TrafficSnapshot() string { return statistic.TrafficSnapshot() }

func SetAppPolicy(config string) error { return statistic.SetAppPolicy(config) }
