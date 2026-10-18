package main

// Privacy: do not print candidate text or typed content beyond the fixed
// ASCII fixture "nei". Pass/fail is decided by composition + candidate presence.

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	winio "github.com/Microsoft/go-winio"
	moqipb "github.com/gaboolic/moqi-ime/proto"
	"google.golang.org/protobuf/proto"
)

func writeFrame(w io.Writer, msg proto.Message) error {
	b, err := proto.Marshal(msg)
	if err != nil {
		return err
	}
	var hdr [4]byte
	binary.LittleEndian.PutUint32(hdr[:], uint32(len(b)))
	if _, err := w.Write(hdr[:]); err != nil {
		return err
	}
	_, err = w.Write(b)
	return err
}

func readFrame(r io.Reader) (*moqipb.ServerResponse, error) {
	var hdr [4]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return nil, err
	}
	n := binary.LittleEndian.Uint32(hdr[:])
	if n > 4*1024*1024 {
		return nil, fmt.Errorf("frame too large %d", n)
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	var resp moqipb.ServerResponse
	if err := proto.Unmarshal(buf, &resp); err != nil {
		return nil, err
	}
	return &resp, nil
}

func stripControl(s string) string {
	for i, r := range s {
		if r < 0x20 {
			return s[:i]
		}
	}
	return s
}

func main() {
	path := os.Getenv("TYPEDUCK_PIPE_PATH")
	if path == "" {
		user := os.Getenv("USERNAME")
		if user == "" {
			user = "Aidan"
		}
		path = `\\.\pipe\` + user + `\TypeDuckIME\Launcher`
	}
	targetRune := rune(0x4F60) // 你 — checked in-process; never printed as a candidate dump
	if v := os.Getenv("TYPEDUCK_PIPE_TARGET_RUNE"); v != "" {
		r, _ := utf8.DecodeRuneInString(v)
		if r != utf8.RuneError {
			targetRune = r
		}
	}

	timeout := 5 * time.Second
	conn, err := winio.DialPipe(path, &timeout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "pipe-nei-probe: dial failed: %v\n", err)
		os.Exit(2)
	}
	defer conn.Close()

	cid := "pipe-nei-smoke"
	guid := "{c6e8f5df-6504-44f9-b7cf-17a195373a83}"
	seq := uint32(1)
	send := func(method moqipb.Method, mutate func(*moqipb.ClientRequest)) (*moqipb.ServerResponse, error) {
		req := &moqipb.ClientRequest{Method: method, SeqNum: seq, ClientId: &cid}
		seq++
		if mutate != nil {
			mutate(req)
		}
		if err := writeFrame(conn, req); err != nil {
			return nil, err
		}
		_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
		return readFrame(conn)
	}

	fmt.Printf("pipe-nei-probe: connecting %s\n", path)

	r, err := send(moqipb.Method_METHOD_INIT, func(req *moqipb.ClientRequest) {
		req.Guid = &guid
		req.IsWindows8Above = true
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "pipe-nei-probe: INIT failed: %v\n", err)
		os.Exit(2)
	}
	fmt.Printf("init success=%v typeduck_error=%v\n", r.GetSuccess(), r.GetTypeduckError())

	if _, err := send(moqipb.Method_METHOD_ON_ACTIVATE, func(req *moqipb.ClientRequest) {
		req.IsKeyboardOpen = true
	}); err != nil {
		fmt.Fprintf(os.Stderr, "pipe-nei-probe: ACTIVATE failed: %v\n", err)
		os.Exit(2)
	}

	var lastComp string
	var lastCount int
	var firstLen int
	var hasTarget bool
	var show bool

	for _, ch := range []rune{'n', 'e', 'i'} {
		vk := uint32(ch) - 32
		ke := &moqipb.KeyEvent{KeyCode: vk, CharCode: uint32(ch), KeyStates: make([]uint32, 256)}
		if _, err := send(moqipb.Method_METHOD_FILTER_KEY_DOWN, func(req *moqipb.ClientRequest) {
			req.KeyEvent = ke
		}); err != nil {
			fmt.Fprintf(os.Stderr, "pipe-nei-probe: FILTER_KEY_DOWN %c: %v\n", ch, err)
			os.Exit(2)
		}
		resp, err := send(moqipb.Method_METHOD_ON_KEY_DOWN, func(req *moqipb.ClientRequest) {
			req.KeyEvent = ke
		})
		if err != nil {
			fmt.Fprintf(os.Stderr, "pipe-nei-probe: ON_KEY_DOWN %c: %v\n", ch, err)
			os.Exit(2)
		}
		lastComp = stripControl(resp.GetCompositionString())
		lastCount = len(resp.GetCandidateList())
		show = resp.GetShowCandidates()
		firstLen = 0
		hasTarget = false
		if lastCount > 0 {
			first := stripControl(resp.GetCandidateList()[0])
			firstLen = utf8.RuneCountInString(first)
			for _, c := range resp.GetCandidateList() {
				if strings.ContainsRune(stripControl(c), targetRune) {
					hasTarget = true
					break
				}
			}
		}
		// Privacy: counts and ASCII composition only — no candidate dump.
		fmt.Printf("key=%c composition=%q candidates=%d show=%v first_rune_len=%d has_target=%v\n",
			ch, lastComp, lastCount, show, firstLen, hasTarget)
	}

	compOK := strings.EqualFold(lastComp, "nei") || lastComp == "nei"
	asciiSafe := lastCount > 0 && firstLen > 0
	pass := (compOK && hasTarget) || (compOK && asciiSafe)
	fmt.Printf("result composition_ok=%v has_target=%v ascii_safe=%v pass=%v\n",
		compOK, hasTarget, asciiSafe, pass)
	if !pass {
		fmt.Fprintf(os.Stderr, "pipe-nei-probe: FAIL (need composition nei and candidates)\n")
		os.Exit(1)
	}
	fmt.Println("pipe-nei-probe: PASS")
}
