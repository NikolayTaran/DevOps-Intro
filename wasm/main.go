package main

import (
	"fmt"
	"net/http"
	"time"

	spinhttp "github.com/spinframework/spin-go-sdk/v3/http"
)

func init() {
	spinhttp.Handle(handleTime)
}

// handleTime answers GET /time with the current Moscow (UTC+3) wall clock
// as a JSON object. Deliberately stdlib-minimal:
//   - time.LoadLocation("Europe/Moscow") would need tzdata, which is not
//     embedded in a WASM component — a FixedZone carries the same offset
//     without the tzdata dependency;
//   - the JSON body is built with fmt.Sprintf instead of encoding/json over
//     a map, avoiding reflection-heavy paths in the WASM toolchain.
func handleTime(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		fmt.Fprint(w, `{"error":"method not allowed"}`)
		return
	}

	// FixedZone("Europe/Moscow", 3h): same Unix instant, wall clock shifted
	// to UTC+3. Moscow has had a permanent UTC+3 since 2014 (no DST).
	moscow := time.Now().In(time.FixedZone("Europe/Moscow", 3*60*60))

	body := fmt.Sprintf(
		`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":"Europe/Moscow","utc_offset":"+03:00"}`,
		moscow.Unix(),
		moscow.Format(time.RFC3339),
		moscow.Format("15:04"),
	)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, body)
}

// main must exist for the compiler; Spin invokes the registered handler
// through the wasi-http interface instead of calling main.
func main() {}
