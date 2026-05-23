package generator

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/aegis/aegis/internal/profiles"
)

// TestGenerate_BasicSmoke ensures the generator runs without crashing for known profiles
// and produces the expected key files.
func TestGenerate_BasicSmoke(t *testing.T) {
	profilesDir := "../../profiles"

	// Test gcp-demo (Ollama)
	t.Run("gcp-demo", func(t *testing.T) {
		p, err := profiles.LoadFromDir("gcp-demo", profilesDir)
		if err != nil {
			t.Fatalf("failed to load profile: %v", err)
		}

		tmpDir := t.TempDir()
		err = Generate(p, tmpDir)
		if err != nil {
			t.Fatalf("Generate failed: %v", err)
		}

		// Check key files exist
		expectedFiles := []string{
			"ollama-deployment.yaml",
			"mission-control-deployment.yaml",
			"kustomization.yaml",
			"bootstrap.sh",
			"profile-used.yaml",
		}

		for _, f := range expectedFiles {
			path := filepath.Join(tmpDir, f)
			if _, err := os.Stat(path); os.IsNotExist(err) {
				t.Errorf("expected file %s was not generated", f)
			}
		}
	})

	// Test gcp-vllm
	t.Run("gcp-vllm", func(t *testing.T) {
		p, err := profiles.LoadFromDir("gcp-vllm", profilesDir)
		if err != nil {
			t.Fatalf("failed to load profile: %v", err)
		}

		tmpDir := t.TempDir()
		err = Generate(p, tmpDir)
		if err != nil {
			t.Fatalf("Generate failed: %v", err)
		}

		// Should generate vllm deployment, not ollama
		if _, err := os.Stat(filepath.Join(tmpDir, "vllm-deployment.yaml")); os.IsNotExist(err) {
			t.Error("expected vllm-deployment.yaml for gcp-vllm profile")
		}
		if _, err := os.Stat(filepath.Join(tmpDir, "ollama-deployment.yaml")); err == nil {
			t.Error("ollama-deployment.yaml should not be generated for gcp-vllm profile")
		}
	})
}