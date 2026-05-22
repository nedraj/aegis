package profiles

import (
	"fmt"
	"io/fs"

	"github.com/aegis/aegis"
	"gopkg.in/yaml.v3"
)

// Profile represents a deployment profile (gcp-demo, airgap-sim, etc).
type Profile struct {
	Name         string                 `yaml:"name"`
	Description  string                 `yaml:"description"`
	Version      string                 `yaml:"version"`
	Target       Target                 `yaml:"target"`
	Resources    Resources              `yaml:"resources"`
	Model        Model                  `yaml:"model"`
	Inference    Inference              `yaml:"inference"`
	MissionCtrl  MissionControl         `yaml:"mission_control"`
	Registry     Registry               `yaml:"registry"`
	K3s          K3s                    `yaml:"k3s"`
	Bundle       Bundle                 `yaml:"bundle"`
	TemplateVars map[string]interface{} `yaml:"template_vars"`
}

// Nested types for clarity
type Target struct {
	Platform    string `yaml:"platform"`
	Instance    string `yaml:"instance_type,omitempty"`
	Accelerator string `yaml:"accelerator,omitempty"`
	Count       int    `yaml:"count,omitempty"`
	OS          string `yaml:"os,omitempty"`
	K3sMode     string `yaml:"k3s_mode,omitempty"`
}

type Resources struct {
	GPU    int    `yaml:"gpu"`
	Memory string `yaml:"memory"`
	CPU    string `yaml:"cpu"`
}

type Model struct {
	Name           string `yaml:"name"`
	Family         string `yaml:"family"`
	ContextLength  int    `yaml:"context_length"`
	Quantization   string `yaml:"quantization,omitempty"`
}

type Inference struct {
	Engine string `yaml:"engine"`
	Image  string `yaml:"image"`
	Port   int    `yaml:"port"`
}

type MissionControl struct {
	Image  string `yaml:"image"`
	Port   int    `yaml:"port"`
	Replicas int  `yaml:"replicas"`
}

type Registry struct {
	Enabled bool   `yaml:"enabled"`
	Image   string `yaml:"image"`
	Port    int    `yaml:"port"`
}

type K3s struct {
	Version       string `yaml:"version"`
	InstallMethod string `yaml:"install_method,omitempty"`
}

type Bundle struct {
	IncludeK3sAirgap         bool `yaml:"include_k3s_airgap"`
	PreloadImagesToContainerd bool `yaml:"preload_images_to_containerd"`
	ModelPreload             bool `yaml:"model_preload"`
}

// Load reads a profile by name from the embedded FS or falls back to local ./profiles/.
func Load(name string) (*Profile, error) {
	// First try embedded
	data, err := fs.ReadFile(assets.FS, fmt.Sprintf("profiles/%s.yaml", name))
	if err != nil {
		// Fallback: try local filesystem (useful during development before embed update)
		// For production binary this should only hit embed.
		return nil, fmt.Errorf("profile %q not found in embedded assets (run 'go generate' or ensure profiles/ is present): %w", name, err)
	}

	var p Profile
	if err := yaml.Unmarshal(data, &p); err != nil {
		return nil, fmt.Errorf("failed to parse profile %s: %w", name, err)
	}
	return &p, nil
}

// List returns all discoverable profile names from embed.
func List() ([]string, error) {
	entries, err := fs.ReadDir(assets.FS, "profiles")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name()[:len(e.Name())-5]) // strip .yaml
		}
	}
	return names, nil
}
