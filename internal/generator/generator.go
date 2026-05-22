package generator

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"text/template"

	"github.com/aegis/aegis"
	"github.com/aegis/aegis/internal/profiles"
	"gopkg.in/yaml.v3"
)

// RenderContext is passed to every template during generation.
type RenderContext struct {
	ProfileName string
	Namespace   string

	// Flattened commonly used values for easy {{ .Foo }} access in templates
	OllamaImage           string
	OllamaReplicas        int
	MissionControlImage   string
	MissionControlReplicas int
	ZotImage              string
	ModelName             string
	GPUCount              int

	GPUNodeSelectorKey   string
	GPUNodeSelectorValue string
	ImagePullPolicy      string

	// Raw access if needed
	Profile *profiles.Profile
}

// Generate renders all embedded templates for the given profile into outDir.
func Generate(p *profiles.Profile, outDir string) error {
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return err
	}

	// Build a rich context from the profile + sensible defaults
	ctx := buildContext(p)

	// Find all templates
	tplFiles, err := fs.Glob(assets.FS, assets.TemplateGlob)
	if err != nil {
		return fmt.Errorf("glob templates: %w", err)
	}
	if len(tplFiles) == 0 {
		return fmt.Errorf("no templates found in embed (pattern: %s)", assets.TemplateGlob)
	}

	for _, tplPath := range tplFiles {
		content, err := fs.ReadFile(assets.FS, tplPath)
		if err != nil {
			return err
		}

		t, err := template.New(filepath.Base(tplPath)).Parse(string(content))
		if err != nil {
			return fmt.Errorf("parse template %s: %w", tplPath, err)
		}

		var buf bytes.Buffer
		if err := t.Execute(&buf, ctx); err != nil {
			return fmt.Errorf("execute template %s: %w", tplPath, err)
		}

		// Output filename: strip .tpl
		outName := filepath.Base(tplPath)
		if filepath.Ext(outName) == ".tpl" {
			outName = outName[:len(outName)-4]
		}
		outPath := filepath.Join(outDir, outName)

		if err := os.WriteFile(outPath, buf.Bytes(), 0644); err != nil {
			return err
		}
		fmt.Printf("  ✓ rendered %s\n", outName)
	}

	// Also write the resolved profile for reference / debugging
	profileOut := filepath.Join(outDir, "profile-used.yaml")
	_ = os.WriteFile(profileOut, mustYAML(p), 0644)

	fmt.Printf("\nGenerated %d manifests into %s\n", len(tplFiles), outDir)
	return nil
}

func buildContext(p *profiles.Profile) RenderContext {
	ns := "aegis"
	if v, ok := p.TemplateVars["namespace"].(string); ok && v != "" {
		ns = v
	}

	gpuKey := "nvidia.com/gpu"
	gpuVal := "true"
	if m, ok := p.TemplateVars["gpu_node_selector"].(map[string]interface{}); ok {
		if k, ok := m["key"].(string); ok {
			gpuKey = k
		}
		if v, ok := m["value"].(string); ok {
			gpuVal = v
		}
	}

	pullPolicy := "IfNotPresent"
	if v, ok := p.TemplateVars["image_pull_policy"].(string); ok {
		pullPolicy = v
	}

	return RenderContext{
		ProfileName: p.Name,
		Namespace:   ns,

		OllamaImage:            p.Inference.Image,
		OllamaReplicas:         1,
		MissionControlImage:    p.MissionCtrl.Image,
		MissionControlReplicas: p.MissionCtrl.Replicas,
		ZotImage:               p.Registry.Image,
		ModelName:              p.Model.Name,
		GPUCount:               p.Resources.GPU,

		GPUNodeSelectorKey:   gpuKey,
		GPUNodeSelectorValue: gpuVal,
		ImagePullPolicy:      pullPolicy,

		Profile: p,
	}
}

func mustYAML(p *profiles.Profile) []byte {
	// Use yaml from the same package that already imports it (profiles re-exports or we import directly)
	b, err := yaml.Marshal(p)
	if err != nil {
		return []byte("# failed to marshal profile: " + err.Error())
	}
	return b
}
