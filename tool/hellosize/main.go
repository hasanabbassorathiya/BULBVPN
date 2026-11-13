package main

import (
	"fmt"
	"net"
	"sort"

	utls "github.com/refraction-networking/utls"
)

// Measures the wire size of the ClientHello each Xray-namable fingerprint
// produces, plus the key-share groups it offers. Two TCP segments (>1448 B)
// is the shape Iranian LTE reportedly drops; one segment is the safe shape.
func main() {
	ids := map[string]*utls.ClientHelloID{
		"chrome":               &utls.HelloChrome_Auto,
		"hellochrome_100":      &utls.HelloChrome_100,
		"hellochrome_106_shuf": &utls.HelloChrome_106_Shuffle,
		"hellochrome_115_pq":   &utls.HelloChrome_115_PQ,
		"hellochrome_120":      &utls.HelloChrome_120,
		"hellochrome_120_pq":   &utls.HelloChrome_120_PQ,
		"hellochrome_131":      &utls.HelloChrome_131,
		"hellochrome_133":      &utls.HelloChrome_133,
		"firefox":              &utls.HelloFirefox_Auto,
		"hellofirefox_105":     &utls.HelloFirefox_105,
		"hellofirefox_120":     &utls.HelloFirefox_120,
		"hellofirefox_148":     &utls.HelloFirefox_148,
		"safari":               &utls.HelloSafari_Auto,
		"hellosafari_16_0":     &utls.HelloSafari_16_0,
		"hellosafari_26_3":     &utls.HelloSafari_26_3,
		"ios":                  &utls.HelloIOS_Auto,
		"helloios_13":          &utls.HelloIOS_13,
		"android_11_okhttp":    &utls.HelloAndroid_11_OkHttp,
		"edge":                 &utls.HelloEdge_Auto,
		"helloedge_106":        &utls.HelloEdge_106,
		"360":                  &utls.Hello360_Auto,
		"qq":                   &utls.HelloQQ_Auto,
		"hellogolang":          &utls.HelloGolang,
	}
	type row struct {
		name  string
		size  int
		group string
		err   string
	}
	rows := []row{}
	names := []string{}
	for n := range ids {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		id := ids[name]
		c, _ := net.Pipe()
		u := utls.UClient(c, &utls.Config{ServerName: "www.cloudflare.com"}, *id)
		if err := u.BuildHandshakeState(); err != nil {
			rows = append(rows, row{name, 0, "", "build: " + err.Error()})
			c.Close()
			continue
		}
		if err := u.MarshalClientHello(); err != nil {
			rows = append(rows, row{name, 0, "", "marshal: " + err.Error()})
			c.Close()
			continue
		}
		hs := u.HandshakeState
		if hs.Hello == nil {
			rows = append(rows, row{name, 0, "", "no hello"})
			c.Close()
			continue
		}
		hello := hs.Hello
		size := len(hello.Raw)
		groups := []string{}
		for _, ks := range hello.KeyShares {
			groups = append(groups, ks.Group.String())
		}
		tls13 := false
		for _, v := range hello.SupportedVersions {
			if uint16(v) == tls_VERSION_TLS_1_3 {
				tls13 = true
			}
		}
		g := "-"
		if len(groups) > 0 {
			g = groups[0]
			if len(groups) > 1 {
				g += "+" + fmt.Sprint(len(groups))
			}
		}
		if !tls13 {
			g += " NO-TLS1.3"
		}
		rows = append(rows, row{name, size, g, ""})
		c.Close()
	}
	fmt.Printf("%-8s %-11s %-26s %s\n", "CH bytes", "segments", "key_share groups", "fingerprint")
	for _, r := range rows {
		if r.err != "" {
			fmt.Printf("%-8s %-11s %-26s %s\n", "-", "-", r.err, r.name)
			continue
		}
		seg := "1 (fits MTU)"
		if r.size > 1448 {
			seg = "2 (split)"
		}
		fmt.Printf("%-8d %-11s %-26s %s\n", r.size, seg, r.group, r.name)
	}
}

const tls_VERSION_TLS_1_3 = uint16(0x0304)
