package inspector

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/aegis/aegis/web/inspector"
)

// BundleIndex holds lightweight metadata about the bundle for fast serving.
type BundleIndex struct {
	Filename   string
	TotalSize  int64
	FileCount  int
	Profile    string
	Version    string
	CreatedAt  string
	Metadata   map[string]interface{}
	Contents   map[string][]string // images, models, manifests, scripts
	Files      []FileEntry
	SHA256Sums map[string]string // path -> expected hash
	mu         sync.RWMutex
}

type FileEntry struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
}

type VerifyResult struct {
	Path string `json:"path"`
	OK   bool   `json:"ok"`
}

// Server wraps the inspector HTTP server.
type Server struct {
	bundlePath string
	index      *BundleIndex
	tarData    []byte // we keep the whole thing in memory for simplicity (reasonable for 6-8GB bundles on dev machines)
}

func NewServer(bundlePath string) (*Server, error) {
	s := &Server{bundlePath: bundlePath}

	if err := s.buildIndex(); err != nil {
		return nil, fmt.Errorf("failed to index bundle: %w", err)
	}
	return s, nil
}

func (s *Server) buildIndex() error {
	f, err := os.Open(s.bundlePath)
	if err != nil {
		return err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)

	index := &BundleIndex{
		Filename:   filepath.Base(s.bundlePath),
		Contents:   make(map[string][]string),
		SHA256Sums: make(map[string]string),
		Files:      []FileEntry{},
	}

	var total int64
	var count int

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if hdr.Typeflag != tar.TypeReg {
			continue
		}

		total += hdr.Size
		count++

		entry := FileEntry{Path: hdr.Name, Size: hdr.Size}
		index.Files = append(index.Files, entry)

		// Categorize
		switch {
		case strings.HasPrefix(hdr.Name, "images/"):
			index.Contents["images"] = append(index.Contents["images"], hdr.Name)
		case strings.HasPrefix(hdr.Name, "models/"):
			index.Contents["models"] = append(index.Contents["models"], hdr.Name)
		case strings.HasPrefix(hdr.Name, "manifests/"):
			index.Contents["manifests"] = append(index.Contents["manifests"], hdr.Name)
		case strings.HasPrefix(hdr.Name, "scripts/"):
			index.Contents["scripts"] = append(index.Contents["scripts"], hdr.Name)
		}

		// Load key metadata files
		if hdr.Name == "bundle.json" {
			data := make([]byte, hdr.Size)
			if _, err := io.ReadFull(tr, data); err == nil {
				var meta map[string]interface{}
				json.Unmarshal(data, &meta)
				index.Metadata = meta
				if p, ok := meta["profile"].(string); ok {
					index.Profile = p
				}
				if v, ok := meta["aegis_version"].(string); ok {
					index.Version = v
				}
				if c, ok := meta["created_at"].(string); ok {
					index.CreatedAt = c
				}
			}
			continue
		}

		if hdr.Name == "SHA256SUMS" {
			// Parse checksums
			data := make([]byte, hdr.Size)
			if _, err := io.ReadFull(tr, data); err == nil {
				lines := strings.Split(string(data), "\n")
				for _, line := range lines {
					parts := strings.Fields(line)
					if len(parts) == 2 {
						index.SHA256Sums[parts[1]] = parts[0]
					}
				}
			}
			continue
		}
	}

	index.TotalSize = total
	index.FileCount = count

	// Sort files for nice display
	sort.Slice(index.Files, func(i, j int) bool {
		return index.Files[i].Path < index.Files[j].Path
	})

	s.index = index

	// Re-open and keep full bytes for content serving (tradeoff for simplicity)
	// For very large bundles, we would stream instead.
	data, err := os.ReadFile(s.bundlePath)
	if err != nil {
		return err
	}
	s.tarData = data

	return nil
}

// Start launches the HTTP server.
func (s *Server) Start(port int) error {
	mux := http.NewServeMux()

	// Serve the embedded single-file UI
	mux.Handle("/", http.FileServer(http.FS(inspector.FS)))

	// APIs
	mux.HandleFunc("/api/summary", s.handleSummary)
	mux.HandleFunc("/api/files", s.handleFiles)
	mux.HandleFunc("/api/file", s.handleFileContent)
	mux.HandleFunc("/api/verify", s.handleVerify)

	addr := fmt.Sprintf("127.0.0.1:%d", port)
	fmt.Printf("\n🚀 Aegis Bundle Inspector running at http://%s\n", addr)
	fmt.Println("   Press Ctrl+C to stop")

	// Auto-open in browser (best effort)
	go func() {
		time.Sleep(600 * time.Millisecond)
		openBrowser(fmt.Sprintf("http://%s", addr))
	}()

	return http.ListenAndServe(addr, mux)
}

func (s *Server) handleSummary(w http.ResponseWriter, r *http.Request) {
	s.index.mu.RLock()
	defer s.index.mu.RUnlock()

	resp := map[string]interface{}{
		"filename":    s.index.Filename,
		"total_size":  s.index.TotalSize,
		"file_count":  s.index.FileCount,
		"profile":     s.index.Profile,
		"version":     s.index.Version,
		"created_at":  s.index.CreatedAt,
		"metadata":    s.index.Metadata,
		"contents":    s.index.Contents,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (s *Server) handleFiles(w http.ResponseWriter, r *http.Request) {
	s.index.mu.RLock()
	defer s.index.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(s.index.Files)
}

func (s *Server) handleFileContent(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "missing path", 400)
		return
	}

	// Re-extract from tar on demand (simple & correct)
	content, err := s.extractFile(path)
	if err != nil {
		http.Error(w, "file not found or too large: "+err.Error(), 404)
		return
	}

	// Guess content type
	if strings.HasSuffix(path, ".yaml") || strings.HasSuffix(path, ".yml") {
		w.Header().Set("Content-Type", "text/yaml; charset=utf-8")
	} else if strings.HasSuffix(path, ".json") {
		w.Header().Set("Content-Type", "application/json")
	} else {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	}

	w.Write(content)
}

func (s *Server) handleVerify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", 405)
		return
	}

	s.index.mu.RLock()
	defer s.index.mu.RUnlock()

	var results []VerifyResult

	for _, entry := range s.index.Files {
		expected, ok := s.index.SHA256Sums[entry.Path]
		if !ok {
			results = append(results, VerifyResult{Path: entry.Path, OK: false})
			continue
		}

		actual, err := s.computeHash(entry.Path)
		if err != nil {
			results = append(results, VerifyResult{Path: entry.Path, OK: false})
			continue
		}

		results = append(results, VerifyResult{
			Path: entry.Path,
			OK:   actual == expected,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"results": results,
	})
}

func (s *Server) extractFile(path string) ([]byte, error) {
	// Open our cached tar bytes
	gz, err := gzip.NewReader(strings.NewReader(string(s.tarData)))
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if hdr.Name == path && hdr.Typeflag == tar.TypeReg {
			return io.ReadAll(tr)
		}
	}
	return nil, fmt.Errorf("file not found: %s", path)
}

func (s *Server) computeHash(path string) (string, error) {
	data, err := s.extractFile(path)
	if err != nil {
		return "", err
	}
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:]), nil
}

// openBrowser attempts to open the default browser on the user's system.
func openBrowser(url string) {
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default: // linux, freebsd, etc.
		cmd = exec.Command("xdg-open", url)
	}

	_ = cmd.Start()
}
