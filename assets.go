// Package assets provides the go:embed filesystem containing all static
// manifests (as Go templates) and default deployment profiles.
//
// This file MUST live at the module root so that the embed patterns can
// reference manifests/ and profiles/ as direct children (go:embed forbids "..").
package assets

import "embed"

// FS is the embedded filesystem root.
// It contains:
//   - manifests/k8s/*.yaml.tpl
//   - profiles/*.yaml

//go:embed manifests/k8s/* profiles/*.yaml
var FS embed.FS

// TemplateGlob matches all renderable Kubernetes + shell template files.
const TemplateGlob = "manifests/k8s/*"

// ProfileGlob matches source profile definitions.
const ProfileGlob = "profiles/*.yaml"
