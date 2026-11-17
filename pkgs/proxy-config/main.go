// proxy-config serves each proxy user's client configuration. The user is
// named by a secret token in the query: GET /query?token=<token>, and
// &tailscale=true selects the variant with Tailscale.
//
// Browsers get a page with a QR code that the sing-box apps scan to import
// the profile as a remote one; everything else, such as the apps updating it,
// gets the JSON. &qr-code=true or &qr-code=false chooses explicitly.
//
// The file given with -users maps each user name to its token and its two
// configurations (any JSON values), and is read once at startup.
package main

import (
	"crypto/subtle"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"

	"rsc.io/qr"
)

type user struct {
	Token     string          `json:"token"`
	Config    json.RawMessage `json:"config"`
	Tailscale json.RawMessage `json:"tailscale"`
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8090", "address to listen on")
	usersFile := flag.String("users", "", "JSON object of user name to token and configs")
	publicURL := flag.String("url", "", "public URL of /query, for the import links")
	flag.Parse()
	log.SetFlags(0)

	base, err := url.Parse(*publicURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		log.Fatalf("-url %q: needs an absolute URL", *publicURL)
	}
	data, err := os.ReadFile(*usersFile)
	if err != nil {
		log.Fatal(err)
	}
	var users map[string]user
	if err := json.Unmarshal(data, &users); err != nil {
		log.Fatalf("%s: %v", *usersFile, err)
	}
	for name, u := range users {
		if u.Token == "" || len(u.Config) == 0 || len(u.Tailscale) == 0 {
			log.Fatalf("%s: user %q needs a token, a config and a tailscale config", *usersFile, name)
		}
	}

	http.HandleFunc("GET /query", func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		token := []byte(query.Get("token"))
		// Compare against every token so the time taken does not tell which user matched.
		var match string
		for name, u := range users {
			if subtle.ConstantTimeCompare([]byte(u.Token), token) == 1 {
				match = name
			}
		}
		if match == "" {
			http.NotFound(w, r)
			return
		}
		tailscale, err := boolParam(query, "tailscale", false)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		showQR, err := boolParam(query, "qr-code", strings.Contains(r.Header.Get("Accept"), "text/html"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Vary", "Accept")
		log.Printf("config for %s (tailscale: %t, qr-code: %t)", match, tailscale, showQR)
		if showQR {
			servePage(w, base, string(token), tailscale)
			return
		}
		config := users[match].Config
		if tailscale {
			config = users[match].Tailscale
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(config)
	})

	log.Printf("listening on %s, %d users", *listen, len(users))
	log.Fatal(http.ListenAndServe(*listen, nil))
}

// boolParam reads an optional true/false query parameter.
func boolParam(query url.Values, name string, fallback bool) (bool, error) {
	v := query.Get(name)
	if v == "" {
		return fallback, nil
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return false, fmt.Errorf("%s must be true or false", name)
	}
	return b, nil
}

// profileURL is where the apps fetch the profile: always the JSON.
func profileURL(base *url.URL, token string, tailscale bool, qrCode bool) string {
	query := url.Values{"token": {token}}
	if tailscale {
		query.Set("tailscale", "true")
	}
	query.Set("qr-code", strconv.FormatBool(qrCode))
	u := *base
	u.RawQuery = query.Encode()
	return u.String()
}

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>{{.Name}}</title>
<style>
:root { color-scheme: light dark; --bg: #f6f6f4; --fg: #1d1d1b; --muted: #6b6b66; --card: #fff; --accent: #2457c5; }
@media (prefers-color-scheme: dark) { :root { --bg: #151514; --fg: #ecece8; --muted: #a2a29b; --card: #222220; --accent: #8fb0ff; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, -apple-system, "PingFang SC", "Noto Sans CJK SC", sans-serif; }
main { max-width: 420px; margin: 0 auto; padding: 32px 16px; text-align: center; }
h1 { font-size: 1.25rem; margin: 0 0 4px; }
p { margin: 0 0 16px; color: var(--muted); }
.qr { background: #fff; border-radius: 12px; padding: 12px; display: inline-block; }
.qr svg { display: block; width: min(300px, 80vw); height: auto; }
.actions { display: flex; flex-direction: column; gap: 10px; margin-top: 20px; }
a { color: var(--accent); }
a.button { display: block; padding: 12px; border-radius: 10px; background: var(--accent); color: var(--card); text-decoration: none; font-weight: 600; }
</style>
</head>
<body>
<main>
<h1>{{.Name}}</h1>
<p>在 sing-box 里扫描二维码，导入为远程配置</p>
<div class="qr">{{.QR}}</div>
<div class="actions">
<a class="button" href="{{.ImportLink}}">在 sing-box 中打开</a>
<a href="{{.JSON}}">查看 JSON</a>
<a href="{{.Other}}">{{.OtherLabel}}</a>
</div>
</main>
</body>
</html>
`))

func servePage(w http.ResponseWriter, base *url.URL, token string, tailscale bool) {
	name := "leak.moe"
	otherLabel := "改用带 Tailscale 的配置"
	if tailscale {
		name = "leak.moe + Tailscale"
		otherLabel = "改用不带 Tailscale 的配置"
	}
	jsonURL := profileURL(base, token, tailscale, false)
	// As libbox.GenerateRemoteProfileImportLink builds it.
	importLink := (&url.URL{
		Scheme:   "sing-box",
		Host:     "import-remote-profile",
		RawQuery: url.Values{"url": {jsonURL}}.Encode(),
		Fragment: name,
	}).String()
	code, err := qr.Encode(importLink, qr.M)
	if err != nil {
		http.Error(w, "QR code: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	err = page.Execute(w, map[string]any{
		"Name":       name,
		"QR":         template.HTML(svg(code)),
		"ImportLink": template.URL(importLink),
		"JSON":       jsonURL,
		"Other":      profileURL(base, token, !tailscale, true),
		"OtherLabel": otherLabel,
	})
	if err != nil {
		log.Print(err)
	}
}

// svg draws the code with a four-module quiet zone, one path for all modules.
func svg(code *qr.Code) string {
	const quiet = 4
	size := code.Size + 2*quiet
	var path strings.Builder
	for y := 0; y < code.Size; y++ {
		for x := 0; x < code.Size; x++ {
			if code.Black(x, y) {
				fmt.Fprintf(&path, "M%d %dh1v1h-1z", x+quiet, y+quiet)
			}
		}
	}
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" shape-rendering="crispEdges" role="img" aria-label="QR code"><rect width="%d" height="%d" fill="#fff"/><path d="%s" fill="#000"/></svg>`,
		size, size, size, size, path.String())
}
