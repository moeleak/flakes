// proxy-config serves each proxy user's client configuration. The user is
// named by a secret token in the query: GET /query?token=<token>, and
// &tailscale=true selects the variant with Tailscale.
//
// Browsers get a page with a QR code that the sing-box apps scan to import
// the profile as a remote one, and a switch between the two variants;
// everything else, such as the apps updating the profile, gets the JSON.
// &qr-code=true or &qr-code=false chooses explicitly. The page's script and
// its Material Web components are served from -assets at /assets/.
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
	assets := flag.String("assets", "", "directory with the page's page.js")
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
	if _, err := os.Stat(*assets + "/page.js"); err != nil {
		log.Fatalf("-assets: %v", err)
	}
	assetsFS := os.DirFS(*assets)

	http.HandleFunc("GET /assets/{name}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=3600")
		http.ServeFileFS(w, r, assetsFS, r.PathValue("name"))
	})

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
<meta name="color-scheme" content="light dark">
<title>leak.moe</title>
<script type="module" src="/assets/page.js"></script>
<style>
/* Material 3 baseline scheme. */
:root {
  --md-ref-typeface-brand: system-ui, -apple-system, "PingFang SC", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif;
  --md-ref-typeface-plain: var(--md-ref-typeface-brand);
  --md-sys-color-primary: #6750a4;
  --md-sys-color-on-primary: #ffffff;
  --md-sys-color-primary-container: #eaddff;
  --md-sys-color-on-primary-container: #21005d;
  --md-sys-color-secondary-container: #e8def8;
  --md-sys-color-surface: #fef7ff;
  --md-sys-color-surface-container-low: #f7f2fa;
  --md-sys-color-surface-container-highest: #e6e0e9;
  --md-sys-color-on-surface: #1d1b20;
  --md-sys-color-on-surface-variant: #49454f;
  --md-sys-color-outline: #79747e;
  --md-sys-color-outline-variant: #cac4d0;
  --md-sys-color-shadow: #000000;
}
@media (prefers-color-scheme: dark) {
  :root {
    --md-sys-color-primary: #d0bcff;
    --md-sys-color-on-primary: #381e72;
    --md-sys-color-primary-container: #4f378b;
    --md-sys-color-on-primary-container: #eaddff;
    --md-sys-color-secondary-container: #4a4458;
    --md-sys-color-surface: #141218;
    --md-sys-color-surface-container-low: #1d1b20;
    --md-sys-color-surface-container-highest: #36343b;
    --md-sys-color-on-surface: #e6e0e9;
    --md-sys-color-on-surface-variant: #cac4d0;
    --md-sys-color-outline: #938f99;
    --md-sys-color-outline-variant: #49454f;
  }
}
[hidden] { display: none !important; }
body {
  margin: 0;
  background: var(--md-sys-color-surface);
  color: var(--md-sys-color-on-surface);
  font-family: var(--md-ref-typeface-plain);
}
main { max-width: 400px; margin: 0 auto; padding: 24px 16px; }
.card {
  position: relative;
  border-radius: 12px;
  padding: 24px;
  background: var(--md-sys-color-surface-container-low);
  --md-elevation-level: 1;
  text-align: center;
}
h1 { margin: 0 0 4px; }
.muted { color: var(--md-sys-color-on-surface-variant); margin: 0; }
.qr { display: inline-block; margin: 20px 0 16px; padding: 12px; border-radius: 16px; background: #ffffff; }
.qr svg { display: block; width: min(264px, 70vw); height: auto; }
.actions { display: flex; flex-direction: column; align-items: stretch; gap: 8px; }
.row {
  display: flex; align-items: center; justify-content: space-between; gap: 16px;
  margin-top: 16px; padding-top: 16px; border-top: 1px solid var(--md-sys-color-outline-variant);
  text-align: start; cursor: pointer;
}
.row > span { display: flex; flex-direction: column; gap: 2px; }
</style>
</head>
<body>
<main>
<div class="card">
<md-elevation></md-elevation>
<h1 class="md-typescale-headline-small">leak.moe</h1>
<p class="md-typescale-body-medium muted">在 sing-box 里扫描二维码，导入为远程配置</p>
{{range .Variants}}
<section data-variant="{{.Key}}"{{if not .Shown}} hidden{{end}}>
<div class="qr">{{.QR}}</div>
<div class="actions">
<md-filled-button href="{{.ImportLink}}">在 sing-box 中打开</md-filled-button>
<md-text-button href="{{.JSON}}">查看 JSON</md-text-button>
</div>
</section>
{{end}}
<label class="row">
<span>
<span class="md-typescale-body-large">Tailscale</span>
<span class="md-typescale-body-medium muted">同时加入 tailnet，首次启动时用日志里的链接登录</span>
</span>
<md-switch id="tailscale"{{if .Tailscale}} selected{{end}}></md-switch>
</label>
</div>
</main>
</body>
</html>
`))

type variant struct {
	Key        string
	Shown      bool
	QR         template.HTML
	ImportLink template.URL
	JSON       string
}

func servePage(w http.ResponseWriter, base *url.URL, token string, tailscale bool) {
	var variants []variant
	for _, withTailscale := range []bool{false, true} {
		key, name := "plain", "leak.moe"
		if withTailscale {
			key, name = "tailscale", "leak.moe + Tailscale"
		}
		jsonURL := profileURL(base, token, withTailscale, false)
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
		variants = append(variants, variant{
			Key:        key,
			Shown:      withTailscale == tailscale,
			QR:         template.HTML(svg(code)),
			ImportLink: template.URL(importLink),
			JSON:       jsonURL,
		})
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	err := page.Execute(w, map[string]any{"Variants": variants, "Tailscale": tailscale})
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
