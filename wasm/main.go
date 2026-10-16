package main

import (
	"fmt"
	"net/http"
	"time"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

// Moscow is UTC+3 year-round (no DST since 2014). time.LoadLocation needs
// the IANA tz database, which a wasip1 module has no access to (the naive
// version failed with "unknown time zone Europe/Moscow" — see lab12 §d),
// so we build a fixed-offset zone instead: same wall clock, no tzdata.
var msk = time.FixedZone("MSK", 3*60*60)

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		now := time.Now().In(msk)
		// TinyGo-safe JSON: fmt.Sprintf + %q verbs instead of the
		// reflection-heavy encoding/json path (lab guideline, §d).
		body := fmt.Sprintf(`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":%q}`,
			now.Unix(), now.Format(time.RFC3339), now.Format("15:04"), "UTC+3 (Moscow)")
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintln(w, body)
	})
}

func main() {}
