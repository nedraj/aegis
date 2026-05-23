package generator

// EngineConfig describes the configuration for a supported inference engine.
type EngineConfig struct {
	Name           string
	DefaultPort    int
	DefaultImage   string
	DeploymentFile string // e.g. "ollama-deployment.yaml" (without .tpl)
}

// Engines is the registry of supported inference backends.
// Adding a new engine here + a corresponding *-deployment.yaml.tpl is the main extension point.
var Engines = map[string]EngineConfig{
	"ollama": {
		Name:           "ollama",
		DefaultPort:    11434,
		DefaultImage:   "ollama/ollama:latest",
		DeploymentFile: "ollama-deployment.yaml",
	},
	"vllm": {
		Name:           "vllm",
		DefaultPort:    8000,
		DefaultImage:   "vllm/vllm-openai:latest",
		DeploymentFile: "vllm-deployment.yaml",
	},
}

// GetEngine returns the config for a given engine name, or falls back to ollama.
func GetEngine(name string) EngineConfig {
	if cfg, ok := Engines[name]; ok {
		return cfg
	}
	return Engines["ollama"]
}