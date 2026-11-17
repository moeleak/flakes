// proxy-config serves each proxy user's client configuration. The user is
// named by a secret token in the query: GET /config?token=<token>.
//
// The file given with -users maps each user name to its token and its
// configuration (any JSON value), and is read once at startup.
package main

import (
	"crypto/subtle"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
)

type user struct {
	Token  string          `json:"token"`
	Config json.RawMessage `json:"config"`
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8090", "address to listen on")
	usersFile := flag.String("users", "", "JSON object of user name to token and config")
	flag.Parse()
	log.SetFlags(0)

	data, err := os.ReadFile(*usersFile)
	if err != nil {
		log.Fatal(err)
	}
	var users map[string]user
	if err := json.Unmarshal(data, &users); err != nil {
		log.Fatalf("%s: %v", *usersFile, err)
	}
	for name, u := range users {
		if u.Token == "" || len(u.Config) == 0 {
			log.Fatalf("%s: user %q needs a token and a config", *usersFile, name)
		}
	}

	http.HandleFunc("GET /config", func(w http.ResponseWriter, r *http.Request) {
		token := []byte(r.URL.Query().Get("token"))
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
		log.Printf("config for %s", match)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(users[match].Config)
	})

	log.Printf("listening on %s, %d users", *listen, len(users))
	log.Fatal(http.ListenAndServe(*listen, nil))
}
