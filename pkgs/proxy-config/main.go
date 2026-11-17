// proxy-config serves each proxy user's client configuration. The user is
// named by a secret token in the query: GET /query?token=<token>. Each of the
// switches below is a query parameter too (&tailscale=true, &lab=true), and
// every combination of them is a variant of the configuration.
//
// Browsers get a page with a QR code that the sing-box apps scan to import
// the profile as a remote one, and the switches; everything else, such as
// the apps updating the profile, gets the JSON. &qr-code=true or
// &qr-code=false chooses explicitly. The page's script and its Material Web
// components are served from -assets at /assets/page.js.
//
// The file given with -users maps each user name to its token and its
// configurations (any JSON values), keyed by the enabled switches in the
// order below, joined with commas: "", "lab", "tailscale", "lab,tailscale".
// It is read once at startup.
package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"rsc.io/qr"
)

type user struct {
	Token   string                     `json:"token"`
	Configs map[string]json.RawMessage `json:"configs"`
}

// A profile option: a query parameter, and a switch on the page.
type option struct {
	Name, Title, Label, Description string
}

var switches = []option{
	{"lab", "Lab", "Lab 中转", "所有流量交给 Lab 转发和分流，只在 Lab 所在的校园网里能用"},
	{"tailscale", "Tailscale", "Tailscale", "同时加入 tailnet，首次启动时用日志里的链接登录"},
}

// combinations lists every set of enabled switches, in switch order.
func combinations() [][]string {
	var all [][]string
	for bits := 0; bits < 1<<len(switches); bits++ {
		var on []string
		for i, s := range switches {
			if bits&(1<<i) != 0 {
				on = append(on, s.Name)
			}
		}
		all = append(all, on)
	}
	return all
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8090", "address to listen on")
	usersFile := flag.String("users", "", "JSON object of user name to token and configs")
	publicURL := flag.String("url", "", "public URL of /query, for the import links")
	assets := flag.String("assets", "", "directory with the page's page.js and typescale.css")
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
		if u.Token == "" {
			log.Fatalf("%s: user %q has no token", *usersFile, name)
		}
		for _, on := range combinations() {
			if len(u.Configs[strings.Join(on, ",")]) == 0 {
				log.Fatalf("%s: user %q has no config %q", *usersFile, name, strings.Join(on, ","))
			}
		}
	}
	script, err := os.ReadFile(*assets + "/page.js")
	if err != nil {
		log.Fatalf("-assets: %v", err)
	}
	typescale, err := os.ReadFile(*assets + "/typescale.css")
	if err != nil {
		log.Fatalf("-assets: %v", err)
	}
	pageCSS = template.CSS(typescale)
	// The page names the script by its content, so a browser never keeps an
	// old one. (Files from the Nix store all carry the same modification
	// time, which is no use for revalidating.)
	sum := sha256.Sum256(script)
	scriptVersion = hex.EncodeToString(sum[:6])

	http.HandleFunc("GET /assets/page.js", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
		w.Header().Set("ETag", `"`+scriptVersion+`"`)
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		http.ServeContent(w, r, "page.js", time.Time{}, bytes.NewReader(script))
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
		var on []string
		for _, s := range switches {
			enabled, err := boolParam(query, s.Name, false)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if enabled {
				on = append(on, s.Name)
			}
		}
		key := strings.Join(on, ",")
		showQR, err := boolParam(query, "qr-code", strings.Contains(r.Header.Get("Accept"), "text/html"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Vary", "Accept")
		log.Printf("config for %s (switches: %q, qr-code: %t)", match, key, showQR)
		if showQR {
			servePage(w, base, string(token), key)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(users[match].Configs[key])
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

// profileURL is the profile with the given switches on. The apps get its
// JSON as it is; a browser needs &qr-code=false, which `inBrowser` adds.
func profileURL(base *url.URL, token string, on []string, inBrowser bool) string {
	query := url.Values{"token": {token}}
	for _, name := range on {
		query.Set(name, "true")
	}
	if inBrowser {
		query.Set("qr-code", "false")
	}
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
<script type="module" src="/assets/page.js?v={{.Script}}"></script>
<style>{{.Typescale}}</style>
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
/* Hold the components' final size until page.js defines them. */
md-filled-button:not(:defined), md-text-button:not(:defined) { display: block; height: 40px; visibility: hidden; }
md-switch:not(:defined) { display: block; flex: none; width: 52px; height: 32px; visibility: hidden; }
md-elevation:not(:defined) { display: none; }
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
{{range .Switches}}
<label class="row">
<span>
<span class="md-typescale-body-large">{{.Label}}</span>
<span class="md-typescale-body-medium muted">{{.Description}}</span>
</span>
<md-switch data-switch="{{.Name}}"{{if .On}} selected{{end}}></md-switch>
</label>
{{end}}
</div>
</main>
</body>
</html>
`))

// pageCSS is Material's type scale, read from -assets at startup, and
// scriptVersion a hash of page.js.
var (
	pageCSS       template.CSS
	scriptVersion string
)

type variant struct {
	Key        string
	Shown      bool
	QR         template.HTML
	ImportLink template.URL
	JSON       string
}

func servePage(w http.ResponseWriter, base *url.URL, token string, current string) {
	var variants []variant
	for _, on := range combinations() {
		key, name := strings.Join(on, ","), "leak.moe"
		for _, s := range switches {
			if slices.Contains(on, s.Name) {
				name += " + " + s.Title
			}
		}
		// As libbox.GenerateRemoteProfileImportLink builds it.
		importLink := (&url.URL{
			Scheme:   "sing-box",
			Host:     "import-remote-profile",
			RawQuery: url.Values{"url": {profileURL(base, token, on, false)}}.Encode(),
			Fragment: name,
		}).String()
		code, err := qr.Encode(importLink, qr.M)
		if err != nil {
			http.Error(w, "QR code: "+err.Error(), http.StatusInternalServerError)
			return
		}
		variants = append(variants, variant{
			Key:        key,
			Shown:      key == current,
			QR:         template.HTML(svg(code)),
			ImportLink: template.URL(importLink),
			JSON:       profileURL(base, token, on, true),
		})
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	type pageSwitch struct {
		option
		On bool
	}
	var pageSwitches []pageSwitch
	for _, s := range switches {
		pageSwitches = append(pageSwitches, pageSwitch{s, slices.Contains(strings.Split(current, ","), s.Name)})
	}
	err := page.Execute(w, map[string]any{"Variants": variants, "Switches": pageSwitches, "Typescale": pageCSS, "Script": scriptVersion})
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
