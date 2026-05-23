package generator

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
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
	OllamaImage            string // legacy (populated from Inference when engine=ollama)
	OllamaReplicas         int
	MissionControlImage    string
	MissionControlReplicas int
	ZotImage               string
	ModelName              string
	GPUCount               int

	// Phase 5: Pluggable inference engine support
	InferenceEngine      string // "ollama" | "vllm" | ...
	InferenceImage       string
	InferencePort        int
	InferenceServiceName string // "ollama" or "vllm" (matches deployment/service name)
	InferenceReplicas    int
	ModelQuantization    string
	ModelLocalPath       string // for vLLM: HF snapshot dir under /models (e.g. "phi-3-mini-4k-instruct")

	// Phase 6: Multi-node cluster support
	ClusterMode string // "single-node" | "multi-node"



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

	// Phase 5+: Filter inference deployment templates using the engine registry.
	// Only the deployment file for the selected engine is rendered.
	filtered := make([]string, 0, len(tplFiles))
	for _, pth := range tplFiles {
		base := filepath.Base(pth)
		if strings.Contains(base, "-deployment.yaml.tpl") {
			cfg := GetEngine(ctx.InferenceEngine)
			expectedFile := cfg.DeploymentFile + ".tpl"
			if base != expectedFile {
				continue
			}
		}
		filtered = append(filtered, pth)
	}
	tplFiles = filtered

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

	// Use the engine registry (generalized in Phase 5+)
	engineName := p.Inference.Engine
	if engineName == "" {
		engineName = "ollama"
	}
	engineCfg := GetEngine(engineName)

	infPort := p.Inference.Port
	if infPort == 0 {
		infPort = engineCfg.DefaultPort
	}

	svcName := p.Inference.ServiceName
	if svcName == "" {
		svcName = engineCfg.Name
	}

	infReplicas := 1
	if p.MissionCtrl.Replicas > 0 {
		// inference replicas typically 1 for GPU
	}

	quant := p.Model.Quantization
	if quant == "" && engineCfg.Name == "ollama" {
		quant = "q4_0"
	}

	modelLocalPath := "phi-3-mini-4k-instruct"
	if v, ok := p.TemplateVars["model_local_path"].(string); ok && v != "" {
		modelLocalPath = v
	} else if strings.Contains(strings.ToLower(p.Model.Family), "phi") {
		modelLocalPath = "phi-3-mini-4k-instruct"
	}

	clusterMode := p.Target.ClusterMode
	if clusterMode == "" {
		clusterMode = "single-node"
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

		// Phase 5+ pluggable inference (now registry-driven)
		InferenceEngine:      engineCfg.Name,
		InferenceImage:       p.Inference.Image,
		InferencePort:        infPort,
		InferenceServiceName: svcName,
		InferenceReplicas:    infReplicas,
		ModelQuantization:    quant,
		ModelLocalPath:       modelLocalPath,

		ClusterMode: clusterMode,

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
